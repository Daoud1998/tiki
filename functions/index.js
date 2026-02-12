/* eslint-disable */
const admin = require('firebase-admin');
const functions = require('firebase-functions'); // 1st gen Firestore triggers (no Eventarc)

admin.initializeApp();
const db = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;
const HttpsError = functions.https.HttpsError;

const REGION = 'europe-west1';

function num(v, dflt) {
  if (typeof v === 'number' && !Number.isNaN(v)) return v;
  const asNum = Number(v);
  return Number.isFinite(asNum) ? asNum : dflt;
}

function strArray(v) {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x) => typeof x === 'string' && x.trim().length)
    .map((s) => s.trim());
}

function utcDayKey(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * Supports both payload shapes:
 * - New:  { productId: "...", data: { ...productFields } }
 * - Old:  { ...productFields }
 */
function unwrapIncoming(raw) {
  if (raw && typeof raw === 'object') {
    const maybeData = raw.data;
    if (maybeData && typeof maybeData === 'object' && !Array.isArray(maybeData)) {
      const pid = (raw.productId || raw.id || maybeData.id || '').toString();
      return { productId: pid, payload: maybeData };
    }
    const pid = (raw.productId || raw.id || '').toString();
    return { productId: pid, payload: raw };
  }
  return { productId: '', payload: {} };
}

async function assertAdmin(uid) {
  const snap = await db.doc(`admins/${uid}`).get();
  if (!snap.exists) {
    throw new HttpsError('permission-denied', 'ADMIN_ONLY');
  }
}

function asString(v) {
  return (v ?? '').toString().trim();
}

function pickType(v) {
  const t = asString(v);
  if (t === 'sales' || t === 'deals' || t === 'system') return t;
  return 'system';
}


function sanitizePromoAttrs(attrs, nowMs) {
  if (!attrs || typeof attrs !== 'object' || Array.isArray(attrs)) return attrs;
  const a = { ...attrs };

  // Admin-only promo/VIP fields: users must NOT set these
  const adminOnly = [
    'promo_rank',
    'promo_until_ms',
    'promo_appr_at_ms',
    'promo_reject_reason',
    // camelCase variants (just in case)
    'promoRank',
    'promoUntilMs',
    'promoApprAtMs',
    'promoRejectReason',
  ];

  for (const k of adminOnly) {
    if (Object.prototype.hasOwnProperty.call(a, k)) delete a[k];
  }

  // Prevent forged statuses
  const rawStatus = (a.promo_status ?? a.promoStatus ?? '').toString().trim().toLowerCase();
  if (rawStatus === 'approved' || rawStatus === 'rejected') {
    // Downgrade to a normal request (admin will decide)
    a.promo_status = 'pending';
    if (Object.prototype.hasOwnProperty.call(a, 'promoStatus')) delete a.promoStatus;
  }

  // If requesting VIP, ensure request timestamp exists
  const st = (a.promo_status ?? '').toString();
  if (st === 'pending' && Number.isFinite(Number(nowMs))) {
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
    throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
  }

  const uid = context.auth.uid;
  const { productId, payload } = unwrapIncoming(data || {});
  const payloadData = payload && typeof payload === 'object' ? payload : {};

  // Basic safety: sellerId must match caller.
  if (payloadData.sellerId && payloadData.sellerId !== uid) {
    throw new HttpsError('failed-precondition', 'SELLER_MISMATCH');
  }

  const limitsRef = db.doc('app_settings/limits');
  const kycSettingsRef = db.doc('app_settings/kyc');
  const kycReqRef = db.doc(`kyc_requests/${uid}`);
  const statsRef = db.doc(`user_stats/${uid}`);
  const productsCol = db.collection('products');

  const nowDate = new Date();
  const nowMs = Date.now();
  const todayKey = utcDayKey(nowDate);
  const nowTs = Timestamp.fromMillis(nowMs);

  return db.runTransaction(async (tx) => {
    const [limitsSnap, kycSettingsSnap, kycReqSnap, statsSnap] = await Promise.all([
      tx.get(limitsRef),
      tx.get(kycSettingsRef),
      tx.get(kycReqRef),
      tx.get(statsRef),
    ]);

    const limits = limitsSnap.exists ? limitsSnap.data() || {} : {};
    const kycSettings = kycSettingsSnap.exists ? kycSettingsSnap.data() || {} : {};
    const kycReq = kycReqSnap.exists ? kycReqSnap.data() || {} : {};

    const isVerified = kycReqSnap.exists && kycReq.status === 'approved';

    const unverifiedMaxActive = num(limits.unverifiedMaxActive, 2);
    const unverifiedDailyLimit = num(limits.unverifiedDailyLimit, 3);
    const verifiedMaxActive = num(limits.verifiedMaxActive, 999999);

    const fastCats = strArray(kycSettings.fastTrackCategories);

    const stats = statsSnap.exists ? statsSnap.data() || {} : {};
    let dailyDate = typeof stats.dailyDate === 'string' ? stats.dailyDate : todayKey;
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
        throw new HttpsError('resource-exhausted', 'DAILY_LIMIT_REACHED', {
          reason: 'daily',
          dailyLimit: unverifiedDailyLimit,
        });
      }
      if (unverifiedMaxActive > 0 && activeCount >= unverifiedMaxActive) {
        // NEW: allow publishing, but send to review instead of blocking.
        limitReached = true;
      }
    } else if (verifiedMaxActive > 0 && activeCount >= verifiedMaxActive) {
      throw new HttpsError('resource-exhausted', 'ACTIVE_LIMIT_REACHED', {
        reason: 'max_active',
        maxActive: verifiedMaxActive,
      });
    }

    const categoryId =
      (typeof payloadData.categoryId === 'string' && payloadData.categoryId.trim()) ||
      (typeof payloadData.category === 'string' && payloadData.category.trim()) ||
      '';

    const categoryNeedsReview = !isVerified && categoryId && fastCats.includes(categoryId);
    const needsReview = categoryNeedsReview || (!isVerified && limitReached);
    const status = needsReview ? 'pending' : 'active';

    const requestedId =
      (productId && productId.trim()) ||
      (typeof payloadData.id === 'string' && payloadData.id.trim()) ||
      '';

    const docRef = requestedId ? productsCol.doc(requestedId) : productsCol.doc();

    // Build final product doc
    const out = { ...payloadData };

    // Block users from forging VIP/promo admin fields inside attrs
    if (out.attrs && typeof out.attrs === 'object' && !Array.isArray(out.attrs)) {
      out.attrs = sanitizePromoAttrs(out.attrs, nowMs);
    }


    out.id = docRef.id;
    out.sellerId = uid;
    out.status = status;

    // Feed-required fields
    out.isHidden = payloadData.isHidden === true;
    out.reviewStatus = needsReview ? 'pending' : 'approved';

    // Avoid wrapper payloads (some clients may send nested {data:{...}})
    if (out.data && typeof out.data === 'object' && !Array.isArray(out.data)) {
      delete out.data;
    }

    // Timestamps expected by the app queries
    out.createdAt = nowTs;
    out.updatedAt = nowTs;
    out.createdAtMs = nowMs;
    out.updatedAtMs = nowMs;

    if (status === 'active') {
      out.publishedAt = nowTs;
      out.publishedAtMs = nowMs;
    } else {
      // Ensure field exists so ordering doesn't break older feeds.
      out.publishedAt = out.publishedAt || null;
    }

    tx.set(docRef, out, { merge: false });

    // Update counters
    dailyCount += 1;
    if (status === 'active') activeCount += 1;

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

    return { productId: docRef.id, status, needsReview, limitReached, reviewStatus: out.reviewStatus };
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
  .firestore
  .document('products/{productId}')
  .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    const update = {};

    // Required by indexes/queries used in the home feed
    if (typeof d.isHidden !== 'boolean') update.isHidden = false;

    const rawStatus = (d.status || '').toString();
    const effectiveStatus = rawStatus === 'approved' ? 'active' : rawStatus;
    if (rawStatus === 'approved') update.status = 'active';

    // If product fields were mistakenly written under data:{...}, copy the important ones.
    const inner = d.data;
    if (inner && typeof inner === 'object' && !Array.isArray(inner)) {
      const keysToCopy = [
        'title',
        'description',
        'body',
        'price',
        'currency',
        'category',
        'categoryId',
        'images',
        'imageUrls',
        'photos',
        'city',
        'country',
        'location',
        'lat',
        'lng',
        'geo',
        'condition',
        'brand',
        'model',
        'searchTokens',
        'searchTokensNormalized',
      ];

      for (const k of keysToCopy) {
        if (d[k] === undefined && inner[k] !== undefined) update[k] = inner[k];
      }

      if (d.sellerId === undefined && inner.sellerId !== undefined) update.sellerId = inner.sellerId;
      if (d.id === undefined && inner.id !== undefined) update.id = inner.id;
    }

    // Ensure publishedAt exists for active products (some queries order by it).
    if (effectiveStatus === 'active') {
      if (!d.publishedAt) update.publishedAt = FieldValue.serverTimestamp();
      if (typeof d.publishedAtMs !== 'number') update.publishedAtMs = Date.now();
    }

    if (!Object.keys(update).length) return null;

    try {
      await snap.ref.set(update, { merge: true });
    } catch (e) {
      console.error('[onProductCreatedNormalize] failed:', context.params.productId, e);
    }

    return null;
  });

/**
 * Notify user when Admin moderates a product (pending -> active/rejected).
 * 1st gen trigger avoids Eventarc permission issues.
 */
exports.onProductModerated = functions
  .region(REGION)
  .firestore
  .document('products/{productId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const oldS = (before.status || '').toString();
    const newS = (after.status || '').toString();
    const effectiveS = newS === 'approved' ? 'active' : newS;


    if (oldS === newS) return null;
    if (oldS !== 'pending') return null;
    if (effectiveS !== 'active' && effectiveS !== 'rejected') return null;

    // If admin UI uses status=approved instead of active, normalize so the home feed query works.
    if (newS === 'approved' && oldS === 'pending') {
      const patch = {
        status: 'active',
        isHidden: false,
        approvedAt: FieldValue.serverTimestamp(),
        approvedAtMs: Date.now(),
      };

      if (!after.publishedAt) patch.publishedAt = FieldValue.serverTimestamp();
      if (typeof after.publishedAtMs !== 'number') patch.publishedAtMs = Date.now();

      try {
        await change.after.ref.set(patch, { merge: true });
      } catch (e) {
        console.error('[onProductModerated] normalize approved->active failed:', e);
      }
    }

    const uid = (after.sellerId || after.ownerUserId || '').toString();
    if (!uid) return null;

    const productId = context.params.productId;

    const notifTitle = effectiveS === 'active' ? 'تمت الموافقة على إعلانك' : 'تم رفض إعلانك';
    const reason = (after.rejectReason || '').toString();
    const notifBody = effectiveS === 'active'
      ? 'إعلانك أصبح ظاهرًا الآن للناس.'
      : (reason ? `تم رفض إعلانك. السبب: ${reason}` : 'تم رفض إعلانك.');

    // 1) Inbox
    const inboxRef = await db
      .collection('user_inbox').doc(uid)
      .collection('items')
      .add({
        scope: 'product_moderation',
        type: 'sales',
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
      .collection('user_devices').doc(uid)
      .collection('tokens').get();

    const tokens = tokensSnap.docs.map((d) => d.id).filter(Boolean);
    if (!tokens.length) return null;

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: notifTitle, body: notifBody },
      data: {
        type: 'product_moderation',
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
        const code = (r.error && r.error.code) ? r.error.code : '';
        if (
          String(code).includes('registration-token-not-registered') ||
          String(code).includes('invalid-argument')
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
    throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
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
    throw new HttpsError('invalid-argument', 'TITLE_BODY_REQUIRED');
  }

  const nowMs = Date.now();

  // Always log for admins
  const logRef = await db.collection('notifications_log').add({
    mode: mode || 'all',
    notifType,
    title,
    body,
    deepLink: deepLink || null,
    createdAt: FieldValue.serverTimestamp(),
    createdAtMs: nowMs,
    createdBy: adminUid,
    topic: mode === 'topic' || mode === 'all' ? (asString(d.topic) || 'all_users') : null,
    targetUid: mode === 'user' ? asString(d.uid) : null,
  });

  if (mode === 'user') {
    const uid = asString(d.uid);
    if (!uid) throw new HttpsError('invalid-argument', 'UID_REQUIRED');

    // Firestore inbox item (source of truth)
    const inboxRef = await db
      .collection('user_inbox').doc(uid)
      .collection('items')
      .add({
        scope: 'admin_direct',
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
      .collection('user_devices').doc(uid)
      .collection('tokens').get();

    const tokens = tokensSnap.docs.map((x) => x.id).filter(Boolean);
    if (!tokens.length) {
      return {
        ok: true,
        mode: 'user',
        uid,
        logId: logRef.id,
        inboxId: inboxRef.id,
        push: { sent: 0, note: 'NO_TOKENS' },
      };
    }

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: 'admin_notification',
        scope: 'user',
        notifType: notifType,
        deepLink: deepLink || '',
        inboxId: inboxRef.id,
      },
    });

    // Cleanup invalid tokens
    const deletions = [];
    for (let i = 0; i < resp.responses.length; i++) {
      const r = resp.responses[i];
      if (!r.success) {
        const code = (r.error && r.error.code) ? r.error.code : '';
        if (
          String(code).includes('registration-token-not-registered') ||
          String(code).includes('invalid-argument')
        ) {
          deletions.push(tokensSnap.docs[i].ref.delete());
        }
      }
    }
    await Promise.all(deletions);

    return {
      ok: true,
      mode: 'user',
      uid,
      logId: logRef.id,
      inboxId: inboxRef.id,
      push: { sent: resp.successCount, failed: resp.failureCount },
    };
  }

  // mode: all/topic -> send via FCM topic + write broadcast doc
  const topic = mode === 'topic' ? asString(d.topic) : 'all_users';
  const topicName = topic || 'all_users';

  const broadcastRef = await db.collection('broadcast_notifications').add({
    scope: mode === 'topic' ? 'admin_topic' : 'admin_all',
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
      type: 'admin_notification',
      scope: mode === 'topic' ? 'topic' : 'all',
      notifType: notifType,
      deepLink: deepLink || '',
      broadcastId: broadcastRef.id,
    },
  });

  return {
    ok: true,
    mode: mode === 'topic' ? 'topic' : 'all',
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
const { jwtVerify, createRemoteJWKSet } = require('jose');

const FPNV_PROJECT_NUMBER = '36657885045';
const FPNV_PROJECT_ID = 'tiki-a9d30';
const FPNV_ISSUER = `https://fpnv.googleapis.com/projects/${FPNV_PROJECT_NUMBER}`;
const FPNV_AUDIENCES = [
  `https://fpnv.googleapis.com/projects/${FPNV_PROJECT_NUMBER}`,
  `https://fpnv.googleapis.com/projects/${FPNV_PROJECT_ID}`,
];
const FPNV_JWKS = createRemoteJWKSet(new URL('https://fpnv.googleapis.com/v1beta/jwks'));

exports.signInWithFpnv = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    const token = (data && data.token ? String(data.token) : '').trim();
    if (!token) throw new HttpsError('invalid-argument', 'MISSING_TOKEN');

    let payload;
    try {
      const verified = await jwtVerify(token, FPNV_JWKS, {
        issuer: FPNV_ISSUER,
        audience: FPNV_AUDIENCES,
      });
      payload = verified.payload || {};
    } catch (e) {
      console.error('[signInWithFpnv] token verify failed:', e);
      throw new HttpsError('permission-denied', 'INVALID_PNV_TOKEN');
    }

    const phoneNumber = (payload.sub ? String(payload.sub) : '').trim();
    if (!phoneNumber || !phoneNumber.startsWith('+')) {
      throw new HttpsError('permission-denied', 'INVALID_PHONE_IN_TOKEN');
    }

    // Get-or-create user by phoneNumber, then mint a Firebase custom token
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByPhoneNumber(phoneNumber);
    } catch (e) {
      const code = (e && e.code) ? String(e.code) : '';
      if (code.includes('auth/user-not-found')) {
        userRecord = await admin.auth().createUser({ phoneNumber });
      } else {
        console.error('[signInWithFpnv] getUserByPhoneNumber failed:', e);
        throw new HttpsError('internal', 'AUTH_LOOKUP_FAILED');
      }
    }

    const customToken = await admin.auth().createCustomToken(userRecord.uid);
    return { ok: true, uid: userRecord.uid, phoneNumber, customToken };
  });

