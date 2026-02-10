/* eslint-disable no-console */
const admin = require('firebase-admin');

/**
 * One-time migration to make products visible in the home feed:
 * - status: "approved" -> "active"
 * - add isHidden:false when missing for active products
 * - ensure publishedAt/publishedAtMs for active products
 * - flatten accidental wrapper field `data { ... }` into root (keeps `data` as-is for safety)
 *
 * Usage (from functions/):
 *   1) Set credentials (one of):
 *      - export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
 *      - or run in an environment with Application Default Credentials
 *   2) Run:
 *      node tools/migrate_products.js --project YOUR_PROJECT_ID
 *
 * Options:
 *   --dry-run      : don't write, just print counts
 *   --limit N      : stop after N docs processed (default: all)
 *   --page-size N  : page size per query (default: 300)
 */

function parseArgs(argv) {
  const out = { dryRun: false, limit: 0, pageSize: 300, projectId: '' };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') out.dryRun = true;
    else if (a === '--project') out.projectId = String(argv[++i] || '');
    else if (a === '--limit') out.limit = Number(argv[++i] || 0) || 0;
    else if (a === '--page-size') out.pageSize = Number(argv[++i] || 300) || 300;
  }
  if (!out.projectId) out.projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || '';
  return out;
}

function shouldCopyRootValue(root, k) {
  const v = root[k];
  return v === undefined || v === null || v === '';
}

async function main() {
  const args = parseArgs(process.argv);
  if (!args.projectId) {
    console.error('Missing --project <PROJECT_ID> (or set GCLOUD_PROJECT env).');
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: args.projectId,
  });

  const db = admin.firestore();
  const { FieldValue, Timestamp } = admin.firestore;
  const FieldPath = admin.firestore.FieldPath;

  let processed = 0;
  let updated = 0;
  let toActive = 0;
  let addedIsHidden = 0;
  let addedPublishedAt = 0;
  let flattened = 0;

  let lastDoc = null;

  while (true) {
    let q = db.collection('products')
      .orderBy(FieldPath.documentId())
      .limit(args.pageSize);

    if (lastDoc) q = q.startAfter(lastDoc.id);

    const snap = await q.get();
    if (snap.empty) break;

    let batch = db.batch();
    let batchOps = 0;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const updates = {};

      const status = String(data.status || '');
      const willBeActive = (status === 'active' || status === 'approved');

      if (!data.id) updates.id = doc.id;
      if (!data.productId) updates.productId = doc.id;

      if (status === 'approved') {
        updates.status = 'active';
        updates.reviewStatus = data.reviewStatus || 'approved';
        toActive += 1;
      }

      if (willBeActive) {
        if (data.isHidden === undefined) {
          updates.isHidden = false;
          addedIsHidden += 1;
        }

        if (data.publishedAt === undefined || data.publishedAt === null) {
          updates.publishedAt = data.approvedAt || Timestamp.now();
          addedPublishedAt += 1;
        }
        if (data.publishedAtMs === undefined || data.publishedAtMs === null) {
          updates.publishedAtMs = (typeof data.approvedAtMs === 'number') ? data.approvedAtMs : Date.now();
        }

        if (!data.reviewStatus && updates.reviewStatus === undefined) {
          updates.reviewStatus = 'approved';
        }
      }

      const wrapped = data.data;
      if (wrapped && typeof wrapped === 'object' && !Array.isArray(wrapped)) {
        let did = false;
        for (const [k, v] of Object.entries(wrapped)) {
          if (shouldCopyRootValue(data, k)) {
            updates[k] = v;
            did = true;
          }
        }
        if (did) flattened += 1;
      }

      if (Object.keys(updates).length) {
        updated += 1;
        if (!args.dryRun) {
          batch.update(doc.ref, updates);
          batchOps += 1;
          if (batchOps >= 450) {
            await batch.commit();
            batch = db.batch();
            batchOps = 0;
          }
        }
      }

      processed += 1;
      lastDoc = doc;

      if (args.limit > 0 && processed >= args.limit) break;
    }

    if (!args.dryRun && batchOps > 0) {
      await batch.commit();
    }

    if (args.limit > 0 && processed >= args.limit) break;
  }

  console.log('Done.');
  console.log(JSON.stringify({
    projectId: args.projectId,
    dryRun: args.dryRun,
    processed,
    updated,
    toActive,
    addedIsHidden,
    addedPublishedAt,
    flattened,
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
