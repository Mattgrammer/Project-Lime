/**
 * Usage:
 *  node migrate_teacher.js <SERVICE_ACCOUNT_JSON> <USER_UID>
 *
 * Example:
 *  node migrate_teacher.js ./serviceAccountKey.json cSwtPMqgMwfyExVXM3RVlbxM2yn2
 *
 * This script copies the document from `students/<uid>` to `teachers/<uid>`
 * merging fields and then deletes the original `students/<uid>` doc.
 *
 * WARNING: This uses the Firebase Admin SDK with service account credentials.
 * Run it only from a trusted environment.
 */

const admin = require('firebase-admin');
const fs = require('fs');

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node migrate_teacher.js <serviceAccount.json> <uid>');
    process.exit(1);
  }

  const svcPath = args[0];
  const uid = args[1];

  if (!fs.existsSync(svcPath)) {
    console.error('Service account file not found:', svcPath);
    process.exit(1);
  }

  const serviceAccount = require(svcPath);

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();

  try {
    const studentRef = db.collection('students').doc(uid);
    const teacherRef = db.collection('teachers').doc(uid);

    const studentSnap = await studentRef.get();
    if (!studentSnap.exists) {
      console.error('No document found in students for uid', uid);
      process.exit(1);
    }

    const data = studentSnap.data() || {};

    // Ensure userType is set to Teacher when copying
    const copy = Object.assign({}, data, { userType: 'Teacher' });
    if (!copy.createdAt) {
      copy.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }

    // Merge into teachers doc (won't overwrite existing fields unless null)
    await teacherRef.set(copy, { merge: true });
    console.log('Copied data to teachers/', uid);

    // Delete original student doc
    await studentRef.delete();
    console.log('Deleted students/', uid);

    console.log('Migration complete for', uid);
    process.exit(0);
  } catch (err) {
    console.error('Migration error:', err);
    process.exit(2);
  }
}

main();
