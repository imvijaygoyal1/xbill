# xBill App Store Review Plan

Last reviewed: 2026-06-14

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
  - Use `APPSTORE_PRIVACY_RECONCILIATION.md` as the source of truth for App Store Connect privacy labels.
  - Keep `web/privacy/index.html` aligned with any future code or backend data-flow changes.

### 3. Make Account Deletion Scope Review-Proof

- Risk: Apple requires in-app account deletion for apps with account creation. The app has deletion UI and an Edge Function, and shared expense history is intentionally retained for other group members.
- Current evidence: `delete-account` removes device tokens, the profile row, the auth user, and the user's avatar object from Supabase Storage. Profile UI says shared expense records remain in groups. Migration 036 keeps inactive historical group-membership snapshots so names can remain readable after access is removed.
- Plan:
  - Decide the product retention policy for shared expenses after an account is deleted.
  - Keep deletion flow and policy copy aligned so they clearly distinguish account deletion, shared group record retention, historical member snapshots, and storage cleanup.
  - If retaining shared records, keep direct personal data removal limited to profile/avatar/device-token cleanup and document retained shared history for reviewers.
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

- Status: Product decision is OCR-only receipt scanning. Receipt images are used temporarily for Vision/OCR and are not uploaded or attached to saved expenses.
- Current evidence: `ExpenseService.createExpense(...)` always sends `p_receipt_url = nil`, and the unused Supabase receipt-image upload helper was removed.
- Plan:
  - Keep App Store privacy labels and the privacy policy aligned with OCR-only behavior.
  - If receipt attachment is added later, reintroduce upload deliberately and update privacy labels/policy before release.

### 7. Required Reason API Reason for App Group UserDefaults

- Status: fixed in manifests on 2026-06-14 after checking Apple's current required-reason API documentation.
- Previous risk: privacy manifests declared only UserDefaults reason `CA92.1`, which Apple defines for information accessible only to the app itself. The app and widget also use an App Group suite so the widget can read cached balance data.
- Current evidence: `CacheService.defaults` and `xBillBalanceWidget` use `UserDefaults(suiteName: "group.com.vijaygoyal.xbill")`. Apple documents `1C8F.1` for UserDefaults data accessible to apps, app extensions, and App Clips in the same App Group. Both `xBill/PrivacyInfo.xcprivacy` and `xBillWidget/PrivacyInfo.xcprivacy` now declare `CA92.1` and `1C8F.1`.
- Plan:
  - Re-check Apple's current required-reason list again immediately before submission in case Apple changes reason IDs.
  - Keep sensitive cached groups, expenses, members, and notifications encrypted.
  - Document that the widget receives only balance summary values and encrypted app data is unreadable without the app keychain key.

### 8. Push Notification Defaults and Consent

- Status: fixed in app code on 2026-06-14.
- Previous risk: in-app notification category toggles defaulted to enabled before OS-level permission. App Review can scrutinize consent semantics when preference UI appears enabled before permission is granted.
- Current evidence: notification category defaults are registered as off until permission is granted; first-grant flow enables category defaults once. Profile shows either an enable/settings state or editable category toggles only when iOS authorization allows push registration. APNs token upload is guarded by current authorization, and stored device tokens are deleted when permission is denied.
- Plan:
  - Keep all app functionality usable when notifications are declined.
  - Keep privacy policy wording limited to storing device push tokens if the user allows notifications.
  - Re-test the fresh-install, denied, and granted notification states before submission.

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
- Confirm App Store Connect privacy labels match `APPSTORE_PRIVACY_RECONCILIATION.md`.
- Confirm Terms and Privacy links work from logged-out and logged-in states.
- Confirm account deletion succeeds for email/password and Sign in with Apple users.
- Confirm deletion removes or anonymizes direct personal data according to the published retention policy.
- Provide review notes with demo account, backend status, notification behavior, receipt OCR behavior, and third-party service disclosures.
