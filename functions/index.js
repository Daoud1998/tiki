/* eslint-disable */
const admin = require("firebase-admin");
const functions = require("firebase-functions"); // 1st gen Firestore triggers (no Eventarc)
const crypto = require("crypto");
const twilio = require("twilio");

admin.initializeApp();
const db = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;
const HttpsError = functions.https.HttpsError;

const REGION = "europe-west1";

// -----------------------------------------------------------------------------
// Twilio Verify (OTP عبر SMS / WhatsApp)
// -----------------------------------------------------------------------------
const TWILIO_ACCOUNT_SID = (process.env.TWILIO_ACCOUNT_SID || "").trim();
const TWILIO_AUTH_TOKEN = (process.env.TWILIO_AUTH_TOKEN || "").trim();
const TWILIO_VERIFY_SERVICE_SID = (
  process.env.TWILIO_VERIFY_SERVICE_SID || ""
).trim();

const twilioClient =
  TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN
    ? twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
    : null;

function assertTwilioConfigured() {
  if (!twilioClient || !TWILIO_VERIFY_SERVICE_SID) {
    throw new HttpsError("failed-precondition", "TWILIO_NOT_CONFIGURED");
  }
}


function maskPhone(e164) {
  const s = String(e164 || "");
  if (s.length <= 6) return s;
  return s.slice(0, 4) + "…" + s.slice(-2);
}

function wrapCallable(name, handler) {
  return functions.region(REGION).https.onCall(async (data, context) => {
    try {
      return await handler(data, context);
    } catch (e) {
      // Preserve expected callable errors
      if (e instanceof HttpsError) throw e;

      console.error(`[${name}] UNHANDLED`, e);
      throw new HttpsError("internal", "UNHANDLED", {
        name,
        message: e && e.message ? String(e.message) : "unknown",
        stack: e && e.stack ? String(e.stack).slice(0, 1500) : null,
        code: e && e.code ? e.code : null,
        status: e && e.status ? e.status : null,
      });
    }
  });
}

function num(v, dflt) {
  if (typeof v === "number" && !Number.isNaN(v)) return v;
  const asNum = Number(v);
  return Number.isFinite(asNum) ? asNum : dflt;
}

function strArray(v) {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x) => typeof x === "string" && x.trim().length)
    .map((s) => s.trim());
}

function utcDayKey(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/**
 * Supports both payload shapes:
 * - New:  { productId: "...", data: { ...productFields } }
 * - Old:  { ...productFields }
 */
function unwrapIncoming(raw) {
  if (raw && typeof raw === "object") {
    const maybeData = raw.data;
    if (
      maybeData &&
      typeof maybeData === "object" &&
      !Array.isArray(maybeData)
    ) {
      const pid = (raw.productId || raw.id || maybeData.id || "").toString();
      return { productId: pid, payload: maybeData };
    }
    const pid = (raw.productId || raw.id || "").toString();
    return { productId: pid, payload: raw };
  }
  return { productId: "", payload: {} };
}

async function assertAdmin(uid) {
  const snap = await db.doc(`admins/${uid}`).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "ADMIN_ONLY");
  }
}

function asString(v) {
  return (v ?? "").toString().trim();
}

function pickType(v) {
  const t = asString(v);
  if (t === "sales" || t === "deals" || t === "system") return t;
  return "system";
}

function sanitizePromoAttrs(attrs, nowMs) {
  if (!attrs || typeof attrs !== "object" || Array.isArray(attrs)) return attrs;
  const a = { ...attrs };

  // Admin-only promo/VIP fields: users must NOT set these
  const adminOnly = [
    "promo_rank",
    "promo_until_ms",
    "promo_appr_at_ms",
    "promo_reject_reason",
    // camelCase variants (just in case)
    "promoRank",
    "promoUntilMs",
    "promoApprAtMs",
    "promoRejectReason",
  ];

  for (const k of adminOnly) {
    if (Object.prototype.hasOwnProperty.call(a, k)) delete a[k];
  }

  // Prevent forged statuses
  const rawStatus = (a.promo_status ?? a.promoStatus ?? "")
    .toString()
    .trim()
    .toLowerCase();
  if (rawStatus === "approved" || rawStatus === "rejected") {
    // Downgrade to a normal request (admin will decide)
    a.promo_status = "pending";
    if (Object.prototype.hasOwnProperty.call(a, "promoStatus"))
      delete a.promoStatus;
  }

  // If requesting VIP, ensure request timestamp exists
  const st = (a.promo_status ?? "").toString();
  if (st === "pending" && Number.isFinite(Number(nowMs))) {
    if (!a.promo_req_at_ms && !a.promoReqAtMs) {
      a.promo_req_at_ms = Number(nowMs);
    }
  }

  return a;
}

/**
 * Create product (Europe region)
 * Enforces verified/unverified limits and optional pending review for fast-track categories.
 */
exports.createProduct = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new HttpsError("unauthenticated", "AUTH_REQUIRED");
    }

    const uid = context.auth.uid;
    const { productId, payload } = unwrapIncoming(data || {});
    const payloadData = payload && typeof payload === "object" ? payload : {};

    // Basic safety: sellerId must match caller.
    if (payloadData.sellerId && payloadData.sellerId !== uid) {
      throw new HttpsError("failed-precondition", "SELLER_MISMATCH");
    }

    const limitsRef = db.doc("app_settings/limits");
    const kycSettingsRef = db.doc("app_settings/kyc");
    const kycReqRef = db.doc(`kyc_requests/${uid}`);
    const statsRef = db.doc(`user_stats/${uid}`);
    const productsCol = db.collection("products");

    const nowDate = new Date();
    const nowMs = Date.now();
    const todayKey = utcDayKey(nowDate);
    const nowTs = Timestamp.fromMillis(nowMs);

    return db.runTransaction(async (tx) => {
      const [limitsSnap, kycSettingsSnap, kycReqSnap, statsSnap] =
        await Promise.all([
          tx.get(limitsRef),
          tx.get(kycSettingsRef),
          tx.get(kycReqRef),
          tx.get(statsRef),
        ]);

      const limits = limitsSnap.exists ? limitsSnap.data() || {} : {};
      const kycSettings = kycSettingsSnap.exists
        ? kycSettingsSnap.data() || {}
        : {};
      const kycReq = kycReqSnap.exists ? kycReqSnap.data() || {} : {};

      const isVerified = kycReqSnap.exists && kycReq.status === "approved";

      const unverifiedMaxActive = num(limits.unverifiedMaxActive, 2);
      const unverifiedDailyLimit = num(limits.unverifiedDailyLimit, 3);
      const verifiedMaxActive = num(limits.verifiedMaxActive, 999999);

      const fastCats = strArray(kycSettings.fastTrackCategories);

      const stats = statsSnap.exists ? statsSnap.data() || {} : {};
      let dailyDate =
        typeof stats.dailyDate === "string" ? stats.dailyDate : todayKey;
      let dailyCount = num(stats.dailyCount, 0);
      let activeCount = num(stats.activeCount, 0);

      if (dailyDate !== todayKey) {
        dailyDate = todayKey;
        dailyCount = 0;
      }

      // Enforce limits
      let limitReached = false;
      if (!isVerified) {
        if (unverifiedDailyLimit > 0 && dailyCount >= unverifiedDailyLimit) {
          throw new HttpsError("resource-exhausted", "DAILY_LIMIT_REACHED", {
            reason: "daily",
            dailyLimit: unverifiedDailyLimit,
          });
        }
        if (unverifiedMaxActive > 0 && activeCount >= unverifiedMaxActive) {
          // NEW: allow publishing, but send to review instead of blocking.
          limitReached = true;
        }
      } else if (verifiedMaxActive > 0 && activeCount >= verifiedMaxActive) {
        throw new HttpsError("resource-exhausted", "ACTIVE_LIMIT_REACHED", {
          reason: "max_active",
          maxActive: verifiedMaxActive,
        });
      }

      const categoryId =
        (typeof payloadData.categoryId === "string" &&
          payloadData.categoryId.trim()) ||
        (typeof payloadData.category === "string" &&
          payloadData.category.trim()) ||
        "";

      const categoryNeedsReview =
        !isVerified && categoryId && fastCats.includes(categoryId);
      const needsReview = categoryNeedsReview || (!isVerified && limitReached);
      const status = needsReview ? "pending" : "active";

      const requestedId =
        (productId && productId.trim()) ||
        (typeof payloadData.id === "string" && payloadData.id.trim()) ||
        "";

      const docRef = requestedId
        ? productsCol.doc(requestedId)
        : productsCol.doc();

      // Build final product doc
      const out = { ...payloadData };

      // Block users from forging VIP/promo admin fields inside attrs
      if (
        out.attrs &&
        typeof out.attrs === "object" &&
        !Array.isArray(out.attrs)
      ) {
        out.attrs = sanitizePromoAttrs(out.attrs, nowMs);
      }

      out.id = docRef.id;
      out.sellerId = uid;
      out.status = status;

      // Feed-required fields
      out.isHidden = payloadData.isHidden === true;
      out.reviewStatus = needsReview ? "pending" : "approved";

      // Avoid wrapper payloads (some clients may send nested {data:{...}})
      if (
        out.data &&
        typeof out.data === "object" &&
        !Array.isArray(out.data)
      ) {
        delete out.data;
      }

      // Timestamps expected by the app queries
      out.createdAt = nowTs;
      out.updatedAt = nowTs;
      out.createdAtMs = nowMs;
      out.updatedAtMs = nowMs;

      if (status === "active") {
        out.publishedAt = nowTs;
        out.publishedAtMs = nowMs;
      } else {
        // Ensure field exists so ordering doesn't break older feeds.
        out.publishedAt = out.publishedAt || null;
      }

      tx.set(docRef, out, { merge: false });

      // Update counters
      dailyCount += 1;
      if (status === "active") activeCount += 1;

      tx.set(
        statsRef,
        {
          dailyDate,
          dailyCount,
          activeCount,
          updatedAtMs: nowMs,
        },
        { merge: true },
      );

      return {
        productId: docRef.id,
        status,
        needsReview,
        limitReached,
        reviewStatus: out.reviewStatus,
      };
    });
  });

/**
 * Normalize newly created product docs so the home feed query works reliably.
 * Fixes common issues:
 * - missing isHidden
 * - status 'approved' -> 'active'
 * - wrapper bug (fields nested under data{})
 */
exports.onProductCreatedNormalize = functions
  .region(REGION)
  .firestore.document("products/{productId}")
  .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    const update = {};

    // Required by indexes/queries used in the home feed
    if (typeof d.isHidden !== "boolean") update.isHidden = false;

    const rawStatus = (d.status || "").toString();
    const effectiveStatus = rawStatus === "approved" ? "active" : rawStatus;
    if (rawStatus === "approved") update.status = "active";

    // If product fields were mistakenly written under data:{...}, copy the important ones.
    const inner = d.data;
    if (inner && typeof inner === "object" && !Array.isArray(inner)) {
      const keysToCopy = [
        "title",
        "description",
        "body",
        "price",
        "currency",
        "category",
        "categoryId",
        "images",
        "imageUrls",
        "photos",
        "city",
        "country",
        "location",
        "lat",
        "lng",
        "geo",
        "condition",
        "brand",
        "model",
        "searchTokens",
        "searchTokensNormalized",
      ];

      for (const k of keysToCopy) {
        if (d[k] === undefined && inner[k] !== undefined) update[k] = inner[k];
      }

      if (d.sellerId === undefined && inner.sellerId !== undefined)
        update.sellerId = inner.sellerId;
      if (d.id === undefined && inner.id !== undefined) update.id = inner.id;
    }

    // Ensure publishedAt exists for active products (some queries order by it).
    if (effectiveStatus === "active") {
      if (!d.publishedAt) update.publishedAt = FieldValue.serverTimestamp();
      if (typeof d.publishedAtMs !== "number")
        update.publishedAtMs = Date.now();
    }

    if (!Object.keys(update).length) return null;

    try {
      await snap.ref.set(update, { merge: true });
    } catch (e) {
      console.error(
        "[onProductCreatedNormalize] failed:",
        context.params.productId,
        e,
      );
    }

    return null;
  });

/**
 * Notify user when Admin moderates a product (pending -> active/rejected).
 * 1st gen trigger avoids Eventarc permission issues.
 */
exports.onProductModerated = functions
  .region(REGION)
  .firestore.document("products/{productId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const oldS = (before.status || "").toString();
    const newS = (after.status || "").toString();
    const effectiveS = newS === "approved" ? "active" : newS;

    if (oldS === newS) return null;
    if (oldS !== "pending") return null;
    if (effectiveS !== "active" && effectiveS !== "rejected") return null;

    // If admin UI uses status=approved instead of active, normalize so the home feed query works.
    if (newS === "approved" && oldS === "pending") {
      const patch = {
        status: "active",
        isHidden: false,
        approvedAt: FieldValue.serverTimestamp(),
        approvedAtMs: Date.now(),
      };

      if (!after.publishedAt) patch.publishedAt = FieldValue.serverTimestamp();
      if (typeof after.publishedAtMs !== "number")
        patch.publishedAtMs = Date.now();

      try {
        await change.after.ref.set(patch, { merge: true });
      } catch (e) {
        console.error(
          "[onProductModerated] normalize approved->active failed:",
          e,
        );
      }
    }

    const uid = (after.sellerId || after.ownerUserId || "").toString();
    if (!uid) return null;

    const productId = context.params.productId;

    const notifTitle =
      effectiveS === "active" ? "تمت الموافقة على إعلانك" : "تم رفض إعلانك";
    const reason = (after.rejectReason || "").toString();
    const notifBody =
      effectiveS === "active"
        ? "إعلانك أصبح ظاهرًا الآن للناس."
        : reason
          ? `تم رفض إعلانك. السبب: ${reason}`
          : "تم رفض إعلانك.";

    // 1) Inbox
    const inboxRef = await db
      .collection("user_inbox")
      .doc(uid)
      .collection("items")
      .add({
        scope: "product_moderation",
        type: "sales",
        productId,
        status: effectiveS,
        title: notifTitle,
        body: notifBody,
        deepLink: `/product/${productId}`,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
        createdAtMs: Date.now(),
      });

    // 2) Push
    const tokensSnap = await db
      .collection("user_devices")
      .doc(uid)
      .collection("tokens")
      .get();

    const tokens = tokensSnap.docs.map((d) => d.id).filter(Boolean);
    if (!tokens.length) return null;

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: notifTitle, body: notifBody },
      data: {
        type: "product_moderation",
        productId: String(productId),
        status: String(effectiveS),
        inboxId: inboxRef.id,
      },
    });

    // Cleanup invalid tokens
    const deletions = [];
    for (let i = 0; i < resp.responses.length; i++) {
      const r = resp.responses[i];
      if (!r.success) {
        const code = r.error && r.error.code ? r.error.code : "";
        if (
          String(code).includes("registration-token-not-registered") ||
          String(code).includes("invalid-argument")
        ) {
          deletions.push(tokensSnap.docs[i].ref.delete());
        }
      }
    }
    await Promise.all(deletions);

    return null;
  });

/**
 * Admin: send notification to:
 * - all users (topic: all_users)
 * - a topic (verified/unverified/country_mr/country_eu)
 * - a specific user UID (via stored tokens)
 *
 * Writes to Firestore so user can always see notifications even if push fails:
 * - Direct: user_inbox/{uid}/items/{id}
 * - Broadcast: broadcast_notifications/{id}
 * - Log: notifications_log/{id} (admin only)
 */
exports.sendAdminNotification = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new HttpsError("unauthenticated", "AUTH_REQUIRED");
    }
    const adminUid = context.auth.uid;
    await assertAdmin(adminUid);

    const d = data || {};
    const mode = asString(d.mode); // 'all' | 'topic' | 'user'
    const notifType = pickType(d.notifType);

    const title = asString(d.title);
    const body = asString(d.body);
    const deepLink = asString(d.deepLink);

    if (!title || !body) {
      throw new HttpsError("invalid-argument", "TITLE_BODY_REQUIRED");
    }

    const nowMs = Date.now();

    // Always log for admins
    const logRef = await db.collection("notifications_log").add({
      mode: mode || "all",
      notifType,
      title,
      body,
      deepLink: deepLink || null,
      createdAt: FieldValue.serverTimestamp(),
      createdAtMs: nowMs,
      createdBy: adminUid,
      topic:
        mode === "topic" || mode === "all"
          ? asString(d.topic) || "all_users"
          : null,
      targetUid: mode === "user" ? asString(d.uid) : null,
    });

    if (mode === "user") {
      const uid = asString(d.uid);
      if (!uid) throw new HttpsError("invalid-argument", "UID_REQUIRED");

      // Firestore inbox item (source of truth)
      const inboxRef = await db
        .collection("user_inbox")
        .doc(uid)
        .collection("items")
        .add({
          scope: "admin_direct",
          type: notifType,
          title,
          body,
          deepLink: deepLink || null,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
          createdAtMs: nowMs,
          createdBy: adminUid,
        });

      // Push to user's tokens
      const tokensSnap = await db
        .collection("user_devices")
        .doc(uid)
        .collection("tokens")
        .get();

      const tokens = tokensSnap.docs.map((x) => x.id).filter(Boolean);
      if (!tokens.length) {
        return {
          ok: true,
          mode: "user",
          uid,
          logId: logRef.id,
          inboxId: inboxRef.id,
          push: { sent: 0, note: "NO_TOKENS" },
        };
      }

      const resp = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: {
          type: "admin_notification",
          scope: "user",
          notifType: notifType,
          deepLink: deepLink || "",
          inboxId: inboxRef.id,
        },
      });

      // Cleanup invalid tokens
      const deletions = [];
      for (let i = 0; i < resp.responses.length; i++) {
        const r = resp.responses[i];
        if (!r.success) {
          const code = r.error && r.error.code ? r.error.code : "";
          if (
            String(code).includes("registration-token-not-registered") ||
            String(code).includes("invalid-argument")
          ) {
            deletions.push(tokensSnap.docs[i].ref.delete());
          }
        }
      }
      await Promise.all(deletions);

      return {
        ok: true,
        mode: "user",
        uid,
        logId: logRef.id,
        inboxId: inboxRef.id,
        push: { sent: resp.successCount, failed: resp.failureCount },
      };
    }

    // mode: all/topic -> send via FCM topic + write broadcast doc
    const topic = mode === "topic" ? asString(d.topic) : "all_users";
    const topicName = topic || "all_users";

    const broadcastRef = await db.collection("broadcast_notifications").add({
      scope: mode === "topic" ? "admin_topic" : "admin_all",
      type: notifType,
      title,
      body,
      deepLink: deepLink || null,
      topics: [topicName],
      createdAt: FieldValue.serverTimestamp(),
      createdAtMs: nowMs,
      createdBy: adminUid,
      logId: logRef.id,
    });

    const msg = await admin.messaging().send({
      topic: topicName,
      notification: { title, body },
      data: {
        type: "admin_notification",
        scope: mode === "topic" ? "topic" : "all",
        notifType: notifType,
        deepLink: deepLink || "",
        broadcastId: broadcastRef.id,
      },
    });

    return {
      ok: true,
      mode: mode === "topic" ? "topic" : "all",
      topic: topicName,
      logId: logRef.id,
      broadcastId: broadcastRef.id,
      messageId: msg,
    };
  });

/**
 * Firebase Phone Number Verification (FPNV / PNV) -> Firebase Auth sign-in
 * Callable: signInWithFpnv({ token })
 *
 * Requirements (functions/):
 *   npm i jose
 */
const { jwtVerify, createRemoteJWKSet } = require("jose");

const FPNV_PROJECT_NUMBER = "36657885045";
const FPNV_PROJECT_ID = "tiki-a9d30";
const FPNV_ISSUER = `https://fpnv.googleapis.com/projects/${FPNV_PROJECT_NUMBER}`;
const FPNV_AUDIENCES = [
  `https://fpnv.googleapis.com/projects/${FPNV_PROJECT_NUMBER}`,
  `https://fpnv.googleapis.com/projects/${FPNV_PROJECT_ID}`,
];
const FPNV_JWKS = createRemoteJWKSet(
  new URL("https://fpnv.googleapis.com/v1beta/jwks"),
);

exports.signInWithFpnv = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    const token = (data && data.token ? String(data.token) : "").trim();
    if (!token) throw new HttpsError("invalid-argument", "MISSING_TOKEN");

    let payload;
    try {
      const verified = await jwtVerify(token, FPNV_JWKS, {
        issuer: FPNV_ISSUER,
        audience: FPNV_AUDIENCES,
      });
      payload = verified.payload || {};
    } catch (e) {
      console.error("[signInWithFpnv] token verify failed:", e);
      throw new HttpsError("permission-denied", "INVALID_PNV_TOKEN");
    }

    const phoneNumber = (payload.sub ? String(payload.sub) : "").trim();
    if (!phoneNumber || !phoneNumber.startsWith("+")) {
      throw new HttpsError("permission-denied", "INVALID_PHONE_IN_TOKEN");
    }

    // Get-or-create user by phoneNumber, then mint a Firebase custom token.
    // Fallback to deterministic UID if Auth lookup fails unexpectedly.
    let uid;
    let userRecord = null;
    try {
      userRecord = await admin.auth().getUserByPhoneNumber(phoneNumber);
      uid = userRecord.uid;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      if (code.includes("auth/user-not-found")) {
        userRecord = await admin.auth().createUser({ phoneNumber });
        uid = userRecord.uid;
      } else {
        console.error("[signInWithFpnv] getUserByPhoneNumber failed:", e);
        uid = uidFromPhoneE164(phoneNumber);
        try {
          userRecord = await admin.auth().getUser(uid);
        } catch (_) {}
      }
    }

    const customToken = await admin.auth().createCustomToken(uid);
    return { ok: true, uid, phoneNumber, customToken };
  });
/**
 * -----------------------------------------------------------------------------
 * WhatsApp OTP (WhatsApp Cloud API) for Login/Register
 * -----------------------------------------------------------------------------
 * Callable:
 *   - sendWhatsappOtp({ phoneE164: "+222xxxxxxxx", languageCode?: "ar"|"en" })
 *   - verifyWhatsappOtp({ phoneE164: "+222xxxxxxxx", code: "123456" })
 *
 * Env vars (functions/.env):
 *   WHATSAPP_TOKEN
 *   WHATSAPP_PHONE_NUMBER_ID
 *   WHATSAPP_TEMPLATE_NAME
 *   OTP_SALT                 (pepper; keep secret)
 * Optional:
 *   OTP_TTL_SECONDS          (default 300)
 *   OTP_COOLDOWN_SECONDS     (default 45)
 *   OTP_MAX_SENDS_PER_DAY    (default 20)
 *   OTP_MAX_ATTEMPTS         (default 6)
 *   OTP_BLOCK_SECONDS        (default 900)
 */
const WHATSAPP_TOKEN = (process.env.WHATSAPP_TOKEN || "").trim();
const WHATSAPP_PHONE_NUMBER_ID = (
  process.env.WHATSAPP_PHONE_NUMBER_ID || ""
).trim();
const WHATSAPP_TEMPLATE_NAME = (
  process.env.WHATSAPP_TEMPLATE_NAME || ""
).trim();
const OTP_PEPPER = (process.env.OTP_SALT || "").trim();

const OTP_TTL_SECONDS = num(process.env.OTP_TTL_SECONDS, 300);
const OTP_COOLDOWN_SECONDS = num(process.env.OTP_COOLDOWN_SECONDS, 45);
const OTP_MAX_SENDS_PER_DAY = num(process.env.OTP_MAX_SENDS_PER_DAY, 20);
const OTP_MAX_ATTEMPTS = num(process.env.OTP_MAX_ATTEMPTS, 6);
const OTP_BLOCK_SECONDS = num(process.env.OTP_BLOCK_SECONDS, 900);

function assertOtpConfigured() {
  if (
    !WHATSAPP_TOKEN ||
    !WHATSAPP_PHONE_NUMBER_ID ||
    !WHATSAPP_TEMPLATE_NAME ||
    !OTP_PEPPER
  ) {
    throw new HttpsError(
      "failed-precondition",
      "OTP_NOT_CONFIGURED",
      "Missing env vars: WHATSAPP_TOKEN, WHATSAPP_PHONE_NUMBER_ID, WHATSAPP_TEMPLATE_NAME, OTP_SALT",
    );
  }
}

function normalizeE164(raw) {
  const s = (raw || "").toString().trim().replace(/\s+/g, "");
  if (!s.startsWith("+"))
    throw new HttpsError("invalid-argument", "PHONE_E164_REQUIRED");
  if (!/^\+[0-9]{7,19}$/.test(s))
    throw new HttpsError("invalid-argument", "PHONE_E164_INVALID");
  return s;
}

// Deterministic UID fallback (used only when Firebase Auth lookup fails unexpectedly).
// This avoids blocking sign-in if Auth lookups are temporarily unavailable.
function uidFromPhoneE164(phoneE164) {
  const h = crypto.createHash("sha256").update(String(phoneE164)).digest("hex");
  // 2 + 24 = 26 chars (safe and short)
  return `p_${h.slice(0, 24)}`;
}

function pickLang(raw) {
  const s = (raw || "").toString().trim().toLowerCase();
  if (s === "en" || s === "en_us" || s === "en-gb" || s === "en_us")
    return "en";
  // default Arabic
  return "ar";
}

function otpDocId(phoneE164) {
  return crypto.createHash("sha256").update(phoneE164).digest("hex");
}

function randomOtp6() {
  const n = crypto.randomInt(0, 1000000);
  return String(n).padStart(6, "0");
}

function sha256Hex(input) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

function timingSafeEqualHex(aHex, bHex) {
  try {
    const a = Buffer.from(aHex, "hex");
    const b = Buffer.from(bHex, "hex");
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch (_) {
    return false;
  }
}

/**
 * Send WhatsApp authentication template using Cloud API.
 * Tries (body+button) first, then falls back to (body only) if template doesn't have the button.
 */
async function sendWhatsAppOtpTemplate({ toE164, languageCode, otp }) {
  const toDigits = toE164.replace(/^\+/, "");
  const url = `https://graph.facebook.com/v20.0/${WHATSAPP_PHONE_NUMBER_ID}/messages`;

  const payloadWithButton = {
    messaging_product: "whatsapp",
    to: toDigits,
    type: "template",
    template: {
      name: WHATSAPP_TEMPLATE_NAME,
      language: { code: languageCode || "ar" },
      components: [
        {
          type: "body",
          parameters: [{ type: "text", text: otp }],
        },
        {
          type: "button",
          sub_type: "url",
          index: 0,
          parameters: [{ type: "text", text: otp }],
        },
      ],
    },
  };

  const payloadBodyOnly = {
    messaging_product: "whatsapp",
    to: toDigits,
    type: "template",
    template: {
      name: WHATSAPP_TEMPLATE_NAME,
      language: { code: languageCode || "ar" },
      components: [
        {
          type: "body",
          parameters: [{ type: "text", text: otp }],
        },
      ],
    },
  };

  async function post(payload) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${WHATSAPP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    const text = await res.text();
    if (!res.ok) {
      const errMsg = `WhatsApp API error ${res.status}: ${text}`;
      return { ok: false, errMsg };
    }
    return { ok: true, text };
  }

  // Try with button (most authentication templates have it)
  const r1 = await post(payloadWithButton);
  if (r1.ok) return r1.text;

  // Fallback without button (in case your template is body-only)
  const r2 = await post(payloadBodyOnly);
  if (r2.ok) return r2.text;

  throw new HttpsError("internal", "WHATSAPP_SEND_FAILED", {
    withButton: r1.errMsg,
    bodyOnly: r2.errMsg,
  });
}

exports.sendWhatsappOtp = functions
  .region(REGION)
  .https.onCall(async (data) => {
    assertOtpConfigured();

    const phoneE164 = normalizeE164(data && data.phoneE164);
    const languageCode = pickLang(data && data.languageCode);

    const nowMs = Date.now();
    const todayKey = utcDayKey(new Date(nowMs));
    const ref = db.collection("whatsappOtps").doc(otpDocId(phoneE164));

    // Prepare OTP
    const otp = randomOtp6();
    const perOtpSalt = crypto.randomBytes(16).toString("hex");
    const otpHash = sha256Hex(
      `${OTP_PEPPER}|${perOtpSalt}|${phoneE164}|${otp}`,
    );
    const expiresAtMs = nowMs + OTP_TTL_SECONDS * 1000;

    // Rate limit + store
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const prev = snap.exists ? snap.data() || {} : {};

      const blockedUntilMs = num(prev.blockedUntilMs, 0);
      if (blockedUntilMs && blockedUntilMs > nowMs) {
        const retryAfterSeconds = Math.ceil((blockedUntilMs - nowMs) / 1000);
        throw new HttpsError("resource-exhausted", "OTP_BLOCKED", {
          retryAfterSeconds,
        });
      }

      const lastSentAtMs = num(prev.lastSentAtMs, 0);
      const cooldownMs = OTP_COOLDOWN_SECONDS * 1000;
      if (
        lastSentAtMs &&
        nowMs - lastSentAtMs < cooldownMs &&
        prev.status !== "send_failed"
      ) {
        const retryAfterSeconds = Math.ceil(
          (cooldownMs - (nowMs - lastSentAtMs)) / 1000,
        );
        throw new HttpsError("resource-exhausted", "OTP_COOLDOWN", {
          retryAfterSeconds,
        });
      }

      let dailyDate = (prev.dailyDate || todayKey).toString();
      let dailyCount = num(prev.dailyCount, 0);
      if (dailyDate !== todayKey) {
        dailyDate = todayKey;
        dailyCount = 0;
      }

      if (OTP_MAX_SENDS_PER_DAY > 0 && dailyCount >= OTP_MAX_SENDS_PER_DAY) {
        throw new HttpsError("resource-exhausted", "OTP_DAILY_LIMIT", {
          dailyLimit: OTP_MAX_SENDS_PER_DAY,
        });
      }

      tx.set(
        ref,
        {
          phoneE164,
          otpHash,
          otpSalt: perOtpSalt,
          expiresAtMs,
          attemptsLeft: OTP_MAX_ATTEMPTS,
          blockedUntilMs: 0,
          dailyDate,
          dailyCount: dailyCount + 1,
          lastSentAtMs: nowMs,
          status: "pending_send",
          updatedAtMs: nowMs,
          createdAtMs: prev.createdAtMs || nowMs,
        },
        { merge: true },
      );
    });

    // Send WhatsApp
    try {
      await sendWhatsAppOtpTemplate({ toE164: phoneE164, languageCode, otp });
      await ref.set({ status: "sent", sentAtMs: nowMs }, { merge: true });
      return {
        ok: true,
        ttlSeconds: OTP_TTL_SECONDS,
        cooldownSeconds: OTP_COOLDOWN_SECONDS,
      };
    } catch (e) {
      // Mark as send_failed so user can retry
      await ref.set(
        {
          status: "send_failed",
          sendFailedAtMs: nowMs,
          sendFailedReason: e && e.message ? String(e.message) : "unknown",
        },
        { merge: true },
      );
      throw e;
    }
  });

exports.verifyWhatsappOtp = functions
  .region(REGION)
  .https.onCall(async (data) => {
    assertOtpConfigured();

    const phoneE164 = normalizeE164(data && data.phoneE164);
    const code = (data && data.code ? String(data.code) : "").trim();

    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "OTP_INVALID_FORMAT");
    }

    const nowMs = Date.now();
    const ref = db.collection("whatsappOtps").doc(otpDocId(phoneE164));

    // Verify and update attempts atomically
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError("failed-precondition", "OTP_NOT_REQUESTED");
      }

      const d = snap.data() || {};
      const expiresAtMs = num(d.expiresAtMs, 0);
      const blockedUntilMs = num(d.blockedUntilMs, 0);
      let attemptsLeft = num(d.attemptsLeft, OTP_MAX_ATTEMPTS);

      if (blockedUntilMs && blockedUntilMs > nowMs) {
        const retryAfterSeconds = Math.ceil((blockedUntilMs - nowMs) / 1000);
        throw new HttpsError("resource-exhausted", "OTP_BLOCKED", {
          retryAfterSeconds,
        });
      }

      if (!expiresAtMs || nowMs > expiresAtMs) {
        tx.delete(ref);
        throw new HttpsError("deadline-exceeded", "OTP_EXPIRED");
      }

      const expectedHash = (d.otpHash || "").toString();
      const otpSalt = (d.otpSalt || "").toString();

      const providedHash = sha256Hex(
        `${OTP_PEPPER}|${otpSalt}|${phoneE164}|${code}`,
      );
      const match =
        expectedHash && timingSafeEqualHex(expectedHash, providedHash);

      // Consume attempt
      attemptsLeft = Math.max(0, attemptsLeft - 1);

      if (!match) {
        const updates = { attemptsLeft, lastAttemptAtMs: nowMs };
        if (attemptsLeft <= 0) {
          updates.blockedUntilMs = nowMs + OTP_BLOCK_SECONDS * 1000;
        }
        tx.set(ref, updates, { merge: true });
        throw new HttpsError("permission-denied", "OTP_WRONG", {
          attemptsLeft,
        });
      }

      // Success: delete OTP
      tx.delete(ref);
      return { ok: true };
    });

    // Get-or-create Firebase user by phoneNumber, then mint a custom token.
    // Fallback to deterministic UID if Auth lookup fails unexpectedly.
    let uid;
    let userRecord = null;
    try {
      userRecord = await admin.auth().getUserByPhoneNumber(phoneE164);
      uid = userRecord.uid;
    } catch (e) {
      const code = e && e.code ? String(e.code) : "";
      if (code.includes("auth/user-not-found")) {
        userRecord = await admin.auth().createUser({ phoneNumber: phoneE164 });
        uid = userRecord.uid;
      } else {
        console.error("[verifyWhatsappOtp] getUserByPhoneNumber failed:", e);
        uid = uidFromPhoneE164(phoneE164);
        try {
          userRecord = await admin.auth().getUser(uid);
        } catch (_) {}
      }
    }

    // Ensure users/{uid} exists (optional but useful for your app)
    const userDocRef = db.collection("users").doc(uid);
    const userSnap = await userDocRef.get();
    const userPatch = {
      uid,
      phoneE164,
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: nowMs,
    };
    if (!userSnap.exists) {
      userPatch.createdAt = FieldValue.serverTimestamp();
      userPatch.createdAtMs = nowMs;
    }
    await userDocRef.set(userPatch, { merge: true });

    const customToken = await admin
      .auth()
      .createCustomToken(uid, { authProvider: "whatsapp" });
    return { ok: true, uid, phoneE164, customToken };
  });

/**
 * -----------------------------------------------------------------------------
 * Twilio Verify OTP (SMS / WhatsApp)
 * -----------------------------------------------------------------------------
 * Callable:
 *   - twilioStartOtp({ phoneE164: "+222xxxxxxxx", channel?: "sms"|"whatsapp" })
 *   - twilioVerifyOtp({ phoneE164: "+222xxxxxxxx", code: "123456" })
 *
 * Env vars (functions/.env):
 *   TWILIO_ACCOUNT_SID
 *   TWILIO_AUTH_TOKEN
 *   TWILIO_VERIFY_SERVICE_SID
 */

exports.twilioStartOtp = wrapCallable("twilioStartOtp", async (data, context) => {
  assertTwilioConfigured();

  const phoneE164 = normalizeE164(data && data.phoneE164);
  const channelRaw = (data && data.channel ? String(data.channel) : "sms")
    .trim()
    .toLowerCase();
  const channel = channelRaw === "whatsapp" ? "whatsapp" : "sms";

  console.log("[twilioStartOtp] to:", maskPhone(phoneE164), "channel:", channel, "appCheck:", !!(context && context.app));

  try {
    await twilioClient.verify.v2
      .services(TWILIO_VERIFY_SERVICE_SID)
      .verifications.create({ to: phoneE164, channel });
    return { ok: true };
  } catch (e) {
    console.error("[twilioStartOtp] Twilio error:", e);
    throw new HttpsError("internal", "TWILIO_SEND_FAILED", {
      message: e && e.message ? String(e.message) : "unknown",
      code: e && e.code ? e.code : null,
      status: e && e.status ? e.status : null,
    });
  }
});


exports.twilioVerifyOtp = wrapCallable("twilioVerifyOtp", async (data, context) => {
  assertTwilioConfigured();

  const phoneE164 = normalizeE164(data && data.phoneE164);
  const code = (data && data.code ? String(data.code) : "").trim();

  if (!/^\d{4,10}$/.test(code)) {
    throw new HttpsError("invalid-argument", "OTP_INVALID_FORMAT");
  }

  console.log("[twilioVerifyOtp] to:", maskPhone(phoneE164), "appCheck:", !!(context && context.app));

  let check;
  try {
    check = await twilioClient.verify.v2
      .services(TWILIO_VERIFY_SERVICE_SID)
      .verificationChecks.create({ to: phoneE164, code });
  } catch (e) {
    console.error("[twilioVerifyOtp] Twilio error:", e);
    throw new HttpsError("internal", "TWILIO_VERIFY_FAILED", {
      message: e && e.message ? String(e.message) : "unknown",
      code: e && e.code ? e.code : null,
      status: e && e.status ? e.status : null,
    });
  }

  if (!check || check.status !== "approved") {
    return { ok: false, status: check ? check.status : "failed" };
  }

  // Get-or-create Firebase user by phoneNumber, then mint a custom token.
  // If Auth lookup fails unexpectedly (permissions / API / transient outage),
  // fall back to a deterministic UID so the client can still sign in.
  let uid;
  let userRecord = null;
  try {
    userRecord = await admin.auth().getUserByPhoneNumber(phoneE164);
    uid = userRecord.uid;
  } catch (e) {
    const code = e && e.code ? String(e.code) : "";
    if (code.includes("auth/user-not-found")) {
      userRecord = await admin.auth().createUser({ phoneNumber: phoneE164 });
      uid = userRecord.uid;
    } else {
      console.error("[twilioVerifyOtp] getUserByPhoneNumber failed:", e);
      // Fallback: deterministic UID
      uid = uidFromPhoneE164(phoneE164);
      // Best-effort: if that UID already exists, keep it.
      try {
        userRecord = await admin.auth().getUser(uid);
      } catch (_) {
        // ignore
      }
    }
  }

  const nowMs = Date.now();

  // Ensure users/{uid} exists (optional but useful for your app)
  const userDocRef = db.collection("users").doc(uid);
  const userSnap = await userDocRef.get();
  const userPatch = {
    uid,
    phoneE164,
    updatedAt: FieldValue.serverTimestamp(),
    updatedAtMs: nowMs,
  };
  if (!userSnap.exists) {
    userPatch.createdAt = FieldValue.serverTimestamp();
    userPatch.createdAtMs = nowMs;
  }
  await userDocRef.set(userPatch, { merge: true });

  const customToken = await admin.auth().createCustomToken(uid, { authProvider: "twilio" });

  return { ok: true, uid, phoneE164, customToken };
});

