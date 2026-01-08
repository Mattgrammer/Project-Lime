Migration helper
----------------

This repository includes a small admin script to migrate an individual user
document from the `students` collection to `teachers` when an account was
incorrectly stored under `students`.

Files:

- `tools/migrate_teacher.js` — Node script using Firebase Admin SDK.

How to run:

1. Create a Firebase service account JSON and download it to your machine.
2. From the repository root run:

```bash
node tools/migrate_teacher.js ./serviceAccountKey.json <USER_UID>
```

Replace `<USER_UID>` with the uid that needs migrating (for example
`cSwtPMqgMwfyExVXM3RVlbxM2yn2`).

Notes:
- This script must be run from a trusted environment because it uses admin
  credentials. It will copy the document to `teachers/<uid>` and delete
  `students/<uid>`.
- After running, open Firestore console to confirm the migration.
