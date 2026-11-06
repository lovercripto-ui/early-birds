# Early Birds Phone PWA

Android/iPhone Home Screen app, served as static files on GitHub Pages with Supabase Auth, private media and transactional data operations.

Runtime files are at the repository root. No local Python/Node server, App Store payment or paid hosting was introduced. Supabase organization was verified as Free.

- Backend migration `phone_pwa_gateway_v1` applied after owner authorization and a private pre-change snapshot.
- Managed account function `early-birds-phone-users` deployed with JWT verification.
- Existing data in 14 public tables compared before/after: unchanged, apart from additive profile flags at their defaults.
- Hosted role-simulated transaction smoke checks: 11 passed; all test data rolled back.
- Local database, browser and account-handler evidence is under `evidence/`.
- Actual owner login, Google OAuth consent and physical Android/iPhone GPS/install checks require the owner; no password was requested or reset by the assistant.

Use the existing cloud Admin email/password. Supervisor accounts are created by Admin; no public signup is offered. If this browser has old local-only data, the app offers a private export without deleting it or copying old password hashes.

See `READ_ME_FIRST_SINHALA.md` for phone instructions and the remaining limitations. See `backend/rollback.sql` before reverting server routing; do not delete financial history. Historical old-client data is never automatically imported into the cloud.
