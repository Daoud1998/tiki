const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");

admin.initializeApp();
const db = admin.firestore();
const { Timestamp } = admin.firestore;


const functions = require("firebase-functions"); // ✅ 1st gen Firestore triggers (بدون Eventarc)

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

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function sendToUser(uid, title, body, data) {
  // 1) Always write an inbox item (حتى لو ما فيه tokens)
  const nowMs = Date.now();
  const itemRef = db
    .collection("user_inbox")
    .doc(uid)
    .collection("items")
    .doc();

  await itemRef.set({
    title,
    body,
    data: data || {},
    read: false,
    createdAt: Timestamp.fromMillis(nowMs),
    createdAtMs: nowMs,
  });

  // 2) Send push notifications (if tokens exist)
  const tokensSnap = await db
    .collection("user_devices")
    .doc(uid)
    .collection("tokens")
    .get();

  const tokens = tokensSnap.docs
    .map((d) => d.id)
    .filter((t) => typeof t === "string" && t.length > 10);

  if (!tokens.length) return;

  const payloadData = {};
  // FCM data must be strings
  Object.entries(data || {}).forEach(([k, v]) => {
    payloadData[k] = v == null ? "" : String(v);
  });

  const batches = chunk(tokens, 500);
  for (const batch of batches) {
    const resp = await admin.messaging().sendEachForMulticast({
      tokens: batch,
      notification: { title, body },
      data: payloadData,
    });

    // Clean up invalid tokens
    const toDelete = [];
    resp.responses.forEach((r, idx) => {
      if (!r.success) {
        const code = r.error && r.error.code ? r.error.code : "";
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          toDelete.push(batch[idx]);
        }
      }
    });

    if (toDelete.length) {
      const uidRef = db
        .collection("user_devices")
        .doc(uid)
        .collection("tokens");
      await Promise.all(
        toDelete.map((t) =>
          uidRef
            .doc(t)
            .delete()
            .catch(() => null),
        ),
      );
    }
  }
}

// --- 1) Create product (enforce limits + pending for sensitive categories) ---
exports.createProduct = onCall({ region: "europe-west1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "AUTH_REQUIRED");
  }

  const uid = request.auth.uid;
  const { productId, payload } = unwrapIncoming(request.data || {});
  const data = payload && typeof payload === "object" ? payload : {};

  // Basic safety: sellerId must match caller.
  if (data.sellerId && data.sellerId !== uid) {
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
    if (!isVerified) {
      if (unverifiedDailyLimit > 0 && dailyCount >= unverifiedDailyLimit) {
        throw new HttpsError("resource-exhausted", "DAILY_LIMIT_REACHED", {
          reason: "daily",
          dailyLimit: unverifiedDailyLimit,
        });
      }
      if (unverifiedMaxActive > 0 && activeCount >= unverifiedMaxActive) {
        throw new HttpsError("resource-exhausted", "ACTIVE_LIMIT_REACHED", {
          reason: "max_active",
          maxActive: unverifiedMaxActive,
        });
      }
    } else if (verifiedMaxActive > 0 && activeCount >= verifiedMaxActive) {
      throw new HttpsError("resource-exhausted", "ACTIVE_LIMIT_REACHED", {
        reason: "max_active",
        maxActive: verifiedMaxActive,
      });
    }

    const categoryId =
      (typeof data.categoryId === "string" && data.categoryId.trim()) ||
      (typeof data.category === "string" && data.category.trim()) ||
      "";

    const needsReview =
      !isVerified && categoryId && fastCats.includes(categoryId);
    const status = needsReview ? "pending" : "active";

    const requestedId =
      (productId && productId.trim()) ||
      (typeof data.id === "string" && data.id.trim()) ||
      "";

    const docRef = requestedId
      ? productsCol.doc(requestedId)
      : productsCol.doc();

    const out = { ...data };
    out.id = docRef.id;
    out.sellerId = uid;
    out.status = status;

    // timestamps expected by app queries
    out.createdAt = nowTs;
    out.updatedAt = nowTs;
    out.createdAtMs = nowMs;
    out.updatedAtMs = nowMs;

    if (status === "active") {
      out.publishedAt = nowTs;
      out.publishedAtMs = nowMs;
    } else {
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

    return { productId: docRef.id, status };
  });
});

// --- 2) Auto notify user when admin moderates a product ---
exports.onProductModerated = functions
  .region("europe-west1")
  .firestore.document("products/{productId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const oldS = (before.status || "").toString();
    const newS = (after.status || "").toString();

    // نهتم فقط بتغيير الحالة من pending -> active/rejected
    if (oldS === newS) return null;
    if (oldS !== "pending") return null;
    if (newS !== "active" && newS !== "rejected") return null;

    const uid = (after.sellerId || after.ownerUserId || "").toString();
    if (!uid) return null;

    const productId = context.params.productId;
    const title = (
      after.title ||
      after.name ||
      after.titles?.ar ||
      ""
    ).toString();

    const notifTitle =
      newS === "active" ? "تمت الموافقة على إعلانك" : "تم رفض إعلانك";
    const reason = (after.rejectReason || "").toString();
    const notifBody =
      newS === "active"
        ? "إعلانك أصبح ظاهرًا الآن للناس."
        : reason.isNotEmpty
          ? `تم رفض إعلانك. السبب: ${reason}`
          : "تم رفض إعلانك.";

    // 1) Inbox داخل Firestore
    await admin
      .firestore()
      .collection("user_inbox")
      .doc(uid)
      .collection("items")
      .add({
        type: "product_moderation",
        productId,
        status: newS,
        title: title.isEmpty ? productId : title,
        body: notifBody,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtMs: Date.now(),
      });

    // 2) Push عبر FCM (لو عنده tokens)
    const tokensSnap = await admin
      .firestore()
      .collection("user_devices")
      .doc(uid)
      .collection("tokens")
      .get();

    const tokens = tokensSnap.docs.map((d) => d.id).filter(Boolean);
    if (!tokens.length) return null;

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: notifTitle, body: notifBody },
      data: { type: "product_moderation", productId, status: newS },
    });

    // تنظيف التوكنات غير الصالحة
    const deletions = [];
    for (let i = 0; i < resp.responses.length; i++) {
      const r = resp.responses[i];
      if (!r.success) {
        const code = r.error && r.error.code ? r.error.code : "";
        if (
          code.includes("registration-token-not-registered") ||
          code.includes("invalid-argument")
        ) {
          deletions.push(tokensSnap.docs[i].ref.delete());
        }
      }
    }
    await Promise.all(deletions);

    return null;
  });
