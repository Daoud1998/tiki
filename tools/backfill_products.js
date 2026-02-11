const admin = require("firebase-admin");

// ضع مسار serviceAccount.json المحلي عندك
admin.initializeApp({
  credential: admin.credential.cert(require("./serviceAccount.json")),
});

const db = admin.firestore();

(async () => {
  const snap = await db.collection("products").get();

  let batch = db.batch();
  let count = 0;
  const BATCH_SIZE = 400;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const update = {};

    if (d.isHidden === undefined) update.isHidden = false;

    if (!d.status) {
      const approved = d.approvedAt || d.approvedAtMs;
      update.status = approved ? "active" : "pending";
    }

    if (Object.keys(update).length) {
      batch.update(doc.ref, update);
      count++;

      if (count % BATCH_SIZE === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
  }

  await batch.commit();
  console.log("Updated products:", count);
  process.exit(0);
})();
