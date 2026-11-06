# Setup and ownership

This release uses **one customer per Supabase project and site deployment**. Never point multiple buyers at the seller's live database. The phone gateway is not a shared multi-tenant service.

For a new buyer, provision an empty project with the base application schema, then apply `backend/phone.sql` followed by `backend/installation.sql`. Existing profiles deliberately lock first-time setup. Do not delete profiles to reopen the wizard.

Configure that copy's `config.js` with its own Supabase URL and publishable key. Update the Supabase origins in the CSP of `index.html` and `recover.html`. Keep service-role keys out of all frontend files. Deploy `backend/phone-users.ts` as `early-birds-phone-users` and `backend/phone-install.ts` as `early-birds-phone-install` with JWT verification enabled. Set `EB_APP_ORIGIN` on both functions to the buyer's website origin. Set `EB_INSTALL_TOKEN` to at least 32 random characters on the install function; share this token privately with the buyer. Never commit it. Configure Auth Site URL and allowed redirect URL to the deployed app and `recover.html`.

The buyer opens the site, enters company name, Admin name, a real email, their own password and installation token. The server reserves setup, creates exactly one Admin, and locks setup. A concurrent attempt cannot become a second Admin. Remove the install token after setup. An incomplete claim expires after ten minutes; if the final commit outcome cannot be confirmed, the handler retains the account for operator investigation instead of deleting a possible Admin.

The installation token authorizes the first account creation; it does not prove email mailbox ownership. The buyer must enter their real, accessible mailbox. Ordinary email changes use Supabase's native confirmation flow and require the current Admin password. Keep secure email-change confirmation enabled. No email or password is hardcoded into the wizard.

After login, Settings permits company-name changes and an Admin email change with current-password verification. For an ownership handover, confirm the email change, let the new owner reset the password through their own mailbox, and separately transfer hosting/database control. The same Admin UUID and all existing data/history remain. This is an account handover, not a transfer of the hosting provider's billing or project ownership.

Password recovery is at `recover.html`, linked from Login. A valid recovery link can open the page directly. If an old Auth redirect still points to localhost, copy the email's original Supabase Reset Password hyperlink and paste it into the recovery page's link field. Verification occurs only with the configured Supabase host; no token goes to another service or persistent local storage. Never send recovery links through chat.

Hosted Supabase's built-in mail service only sends to organization-team email addresses and has low rate limits. Before selling to unrelated buyers/users, configure a suitable SMTP provider or Send Email hook and verify real delivery. This release does not activate a paid service or claim unrestricted production email delivery. Physical device checks, live owner login and external-buyer installation acceptance remain necessary.

For this existing installation, first-time setup remains permanently locked and the existing Admin UUID/data are retained. The requested email correction is an operator recovery action, not a public wizard capability. Its temporary maintenance endpoint was replaced by a permanent HTTP 410 tombstone immediately after completion.
