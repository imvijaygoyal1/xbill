# xBill App Store Review Plan

Last reviewed: 2026-05-03

This plan tracks issues that can block or slow App Store review. It is intentionally limited to future work; do not treat any item here as implemented unless the referenced code or metadata has changed.

## Highest Risk Before Submission

### 1. Keep Invite URL Production-Safe

- Status: fixed and publicly verified on 2026-05-03.
- Previous risk: `AddFriendView` shared `https://apps.apple.com/app/xbill/id0000000000`, which was placeholder metadata and could be flagged under App Review Guideline 2.1 for incomplete content.
- Current implementation: `XBillURLs.appInvite` centralizes the invite destination as `https://xbill.vijaygoyal.org/invite`; `AddFriendView` uses that constant in the invite `ShareLink`.
- Web status: Cloudflare Pages serves `https://xbill.vijaygoyal.org/invite` as valid raw HTML with `HTTP 200`.
- Plan:
  - After the App Store listing exists, either keep `/invite` as the stable redirect/landing route or update the website to include the real App Store link.
  - Add a pre-submission grep check for `id0000000000`, `placeholder`, `example.com`, and local/test URLs.
  - Keep the app pointed at the stable custom domain `xbill.vijaygoyal.org`; do not switch Swift constants to a generated `*.pages.dev` URL unless the custom domain is intentionally retired.

### 2. Validate Privacy Policy URL and Content

- Risk: Apple requires a privacy policy link in App Store Connect metadata and inside the app. The app exposes `https://xbill.vijaygoyal.org/privacy`, but review can reject if the URL is unavailable, incomplete, or inconsistent with collected data.
- Current evidence: `XBillURLs.privacyPolicy` points to `https://xbill.vijaygoyal.org/privacy`; the policy is opened from Auth and Profile.
- Web status: Cloudflare Pages serves `https://xbill.vijaygoyal.org/privacy` as valid raw HTML; `/privacy` redirects to `/privacy/` then returns `HTTP 200`.
- Plan:
  - Ensure it explicitly covers Supabase, Resend email invites, APNs/device tokens, contact-email lookup, avatar uploads, receipt images/OCR, exchange-rate network calls, deletion and retention policy, and support contact.
  - Match App Store Connect privacy nutrition labels to `xBill/PrivacyInfo.xcprivacy`.
  - Keep `web/privacy/index.html` aligned with any future code or backend data-flow changes.

### 3. Make Account Deletion Scope Review-Proof

- Risk: Apple requires in-app account deletion for apps with account creation. The app has deletion UI and an Edge Function, but currently deletion removes `device_tokens`, `profiles`, and the auth user while group expenses, splits, comments, invite records, receipt storage objects, and avatar storage may remain depending on database/storage rules.
- Current evidence: `delete-account` deletes only device tokens, profile, and auth user; Profile UI says expenses remain in groups.
- Plan:
  - Decide the product retention policy for shared expenses after an account is deleted.
  - Update deletion flow and policy copy so they clearly distinguish account deletion, shared group record retention, anonymization, and storage cleanup.
  - If retaining shared records, anonymize or detach deleted-user identifiers and delete direct personal data such as avatar and device token.
  - Add a reviewer note explaining shared expense retention if retained for other group members.

### 4. Review Contact Discovery for Consent and Data Minimization

- Risk: Contact import sends selected contact email addresses to Supabase lookup RPCs. Apple allows data collection with consent and prefers pickers, but the App Store privacy policy and purpose strings must clearly explain this use.
- Current evidence: `CNContactPickerViewController` is used, `NSContactsUsageDescription` says contacts are used to find friends already on xBill, and privacy manifest declares Contacts.
- Plan:
  - Keep using the out-of-process contact picker; do not request full address book access.
  - Add UI copy near the import action stating selected emails are checked against xBill users.
  - Ensure the privacy policy says contact emails are used only for friend/member discovery and invite delivery, and are not used for tracking or advertising.

### 5. Confirm Third-Party Network Disclosures

- Risk: The app contacts services beyond Apple and Supabase, including `open.er-api.com` for exchange rates and Resend for email invites. Reviewers can flag missing privacy disclosures or broken URLs.
- Current evidence: `ExchangeRateService` calls `https://open.er-api.com/v6/latest/{base}`; Supabase Edge Functions call Resend and APNs.
- Plan:
  - Document every third-party service in the privacy policy.
  - Confirm exchange-rate requests do not include user identifiers.
  - Add backend/service availability notes for review, including a demo account and test group data if required.

## Medium Risk

### 6. Receipt and Photo Data Consistency

- Risk: Privacy manifest declares photos/videos as unlinked, but the app has a receipt upload method that stores receipt images under an expense ID. If that path is used, receipt images become linked to a user/group/expense and should be disclosed accordingly.
- Current evidence: receipt scan is on-device, but `ExpenseService.uploadReceiptImage(_:expenseID:)` uploads to Supabase Storage.
- Plan:
  - Verify whether receipt image upload is reachable in production.
  - If reachable, update privacy nutrition labels and privacy policy to treat receipt images as linked financial/user content.
  - If not reachable, document that receipt OCR is on-device and images are not uploaded.

### 7. Required Reason API Reason for App Group UserDefaults

- Risk: Privacy manifest declares UserDefaults reason `CA92.1`, which is for app-only storage. The app also uses an App Group suite so the widget can read cached balance data. Apple may treat App Group sharing as outside the narrow "only accessible to the app itself" wording.
- Current evidence: `CacheService.defaults` uses `UserDefaults(suiteName: "group.com.vijaygoyal.xbill")`; both app and widget declare `CA92.1`.
- Plan:
  - Re-check Apple's current required-reason list before submission for the best App Group/widget reason.
  - Keep sensitive cached groups, expenses, members, and notifications encrypted.
  - Document that the widget receives only balance summary values and encrypted app data is unreadable without the app keychain key.

### 8. Push Notification Defaults and Consent

- Risk: In-app notification category toggles default to enabled before OS-level permission. This is probably acceptable because OS permission is still requested through a pre-prompt, but App Review can scrutinize notification consent flows.
- Current evidence: defaults are registered as `true`; OS permission is requested only after `NotificationPermissionView`.
- Plan:
  - Keep all app functionality usable when notifications are declined.
  - Consider defaulting category preferences only after the user taps "Allow Notifications" to avoid confusing consent semantics.
  - Make privacy policy mention device token collection only after notification registration.

### 9. App Completeness and Reviewer Access

- Risk: Apps with sign-in must provide reviewer access or a demo mode, and the backend must be live.
- Current evidence: app requires account-based Supabase functionality and does not include an offline demo mode.
- Plan:
  - Create a stable review account with seeded groups, friends, expenses, comments, receipts, and notification settings.
  - Include Sign in with Apple and email/password test paths in review notes.
  - Verify Supabase migrations, Edge Functions, APNs production environment, Resend, and legal pages are deployed before submit.

## Pre-Submission Checklist

- Confirm Cloudflare Pages direct-upload source in `web/` is current and deploy the whole folder, not a single subfolder.
- If using the separate Git-backed web repo at `/Users/vijaygoyal/Documents/xbill-web`, confirm it contains only raw static page files and no `_redirects` catch-all. Expected files: `index.html`, `invite/index.html`, `privacy/index.html`, `terms/index.html`.
- Do not use `_redirects` rule `/* /index.html 200` for this static site. Cloudflare Pages can flag it as an infinite loop; directory `index.html` routing already handles `/invite`, `/privacy`, and `/terms`.
- Treat Cloudflare `308` redirects from `/privacy` to `/privacy/` or `/terms` to `/terms/` as normal if `curl -L -I` ends at `HTTP 200`.
- Verify public pages:
  `curl -L -I https://xbill.vijaygoyal.org`,
  `curl -L -I https://xbill.vijaygoyal.org/invite`,
  `curl -L -I https://xbill.vijaygoyal.org/privacy`,
  `curl -L -I https://xbill.vijaygoyal.org/terms`.
- Confirm legal page content starts with raw `<!DOCTYPE html>` and does not contain `Cocoa HTML Writer`, `<p class="p1">`, or escaped `&lt;!DOCTYPE`.
- Run `rg -n "id0000000000|placeholder|example\\.com|localhost|127\\.0\\.0\\.1|TODO|FIXME" .`.
- Build Release with production entitlements and production APNs.
- Validate `xBill/PrivacyInfo.xcprivacy` and `xBillWidget/PrivacyInfo.xcprivacy` are included in built products.
- Confirm App Store Connect privacy labels match the app, widget, Supabase, Edge Functions, and privacy policy.
- Confirm Terms and Privacy links work from logged-out and logged-in states.
- Confirm account deletion succeeds for email/password and Sign in with Apple users.
- Confirm deletion removes or anonymizes direct personal data according to the published retention policy.
- Provide review notes with demo account, backend status, notification behavior, receipt OCR behavior, and third-party service disclosures.
