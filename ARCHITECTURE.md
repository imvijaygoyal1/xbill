# xBill Architecture

Last updated: 2026-05-03

## Overview

xBill is an iPhone-only SwiftUI app for shared expense tracking. The client is built with SwiftUI, Swift 6 strict concurrency, `@Observable` view models, Supabase Auth/Postgres/Realtime/Storage, APNs through Supabase Edge Functions, and a WidgetKit balance widget.

This document focuses on architectural surfaces that matter for App Store review, privacy, and future implementation decisions.

## Client Targets

- `xBill`: primary iOS app, bundle ID `com.vijaygoyal.xbill`.
- `xBillWidget`: WidgetKit extension, bundle ID `com.vijaygoyal.xbill.widget`.
- App Group: `group.com.vijaygoyal.xbill` for widget balance sharing.
- URL scheme: `xbill://` for auth redirects, group invites, and add-friend QR links.

## Authentication and Account Lifecycle

- Sign-in paths: email/password and Sign in with Apple.
- Session storage: Supabase auth session backed by `KeychainSessionStorage`.
- Profile data: `profiles` table stores email, display name, avatar URL, and timestamps.
- Account deletion: app calls `delete-account` Edge Function, which verifies the JWT and deletes device tokens, profile row, and auth user.

Review-sensitive note: deletion currently needs a documented retention/anonymization policy for shared records such as expenses, splits, comments, group memberships, invites, avatars, and receipt images. Shared financial history may be retained for other group members only if the product and privacy policy explain it clearly.

## Data Model

Core Supabase tables:

- `profiles`: user profile and account metadata.
- `groups` and `group_members`: shared expense groups.
- `expenses` and `splits`: financial records and balances.
- `comments`: expense discussion.
- `group_invites`: join links.
- `ious`: friend-level debts.
- `friends`: friend graph and request status.
- `device_tokens`: APNs token registration.

The main financial operation is the `add_expense_with_splits` RPC, which atomically creates an expense and its splits.

## Privacy and Local Storage

- Keychain stores auth session material, cache encryption key, and app-lock preference.
- App Group UserDefaults stores encrypted groups, expenses, members, and notifications.
- Widget-readable balance summary values are intentionally unencrypted because the widget displays them.
- Privacy manifests exist for both app and widget.

Review-sensitive note: because App Group UserDefaults is shared with the widget, required-reason API declarations should be rechecked before each submission against Apple's latest reason list.

## Permissions

Declared permission strings:

- Camera: receipt scanning.
- Photo Library: importing receipt/profile images.
- Contacts: selected-contact friend/member discovery.
- Face ID: optional app lock.

Architecture decision: contact discovery uses `CNContactPickerViewController`, not full address book access. Future changes should preserve picker-based minimization unless there is a compelling reason and a revised privacy review.

## Network and Third-Party Services

- Supabase: auth, database, realtime, storage, and Edge Functions.
- APNs: push notifications, sent by Edge Functions.
- Resend: email invites from Edge Functions.
- `open.er-api.com`: exchange rates; no user identifier should be sent.
- Apple services: Sign in with Apple, Vision/VisionKit, Core Spotlight, WidgetKit.

Review-sensitive note: every third-party service above must be reflected in the privacy policy and App Store Connect privacy labels where applicable.

## Notifications

Notification categories:

- New group expenses.
- Settlements.
- Comments.
- Friend requests.

The app uses a custom pre-prompt before the OS notification permission dialog. Device tokens are saved only after successful APNs registration. App functionality must remain available when notifications are declined.

## Receipt Scanning

Receipt capture uses VisionKit and PhotosPicker, then on-device OCR/parsing through Vision and FoundationModels when available, with heuristic fallback. The architecture should prefer on-device processing. If receipt image upload is used, uploaded images are linked financial content and must be disclosed accordingly.

## External Links and Payments

- Terms are shown in-app from `TermsOfServiceView`; the public web terms page is also available at `https://xbill.vijaygoyal.org/terms`.
- Privacy policy opens in `SFSafariViewController` from `https://xbill.vijaygoyal.org/privacy`.
- Venmo and PayPal links are settlement conveniences only; xBill does not process payments.
- Invite links must never use placeholder App Store URLs in production.

Review-sensitive note: third-party payment links are currently for person-to-person settlement of real-world expenses, not digital goods or in-app features. Keep Terms, review notes, and UI copy aligned with that distinction.

## Public Web Architecture

- Public web pages are static HTML under `web/`.
- Hosting is Cloudflare Pages project `xbill`.
- Domains are `https://xbill.vijaygoyal.org` and `https://xbill.pages.dev`.
- The Pages project currently has no Git connection; deployments are direct uploads from the Cloudflare dashboard.
- Route mapping:
  - `web/index.html` → `/`
  - `web/invite/index.html` → `/invite`
  - `web/privacy/index.html` → `/privacy`
  - `web/terms/index.html` → `/terms`
- Direct-upload deployments replace the whole deployed asset set. Future changes should upload the full `web/` folder to avoid deleting legal pages.
- App URL constants live in `xBill/Core/Constants/XBillURLs.swift` and should be the only source for public web URLs in Swift code.
- Verified 2026-05-03: `/`, `/invite`, `/privacy`, and `/terms` all resolve publicly and serve raw HTML; `/privacy` and `/terms` redirect to trailing-slash routes before `HTTP 200`.

## App Store Review Gates

Before submission, future work should verify:

- No placeholder URLs or metadata remain.
- Legal URLs are public and stable.
- App Store Connect privacy labels, privacy manifest, and actual data flows match.
- Account deletion behavior matches policy and reviewer expectations.
- Reviewer credentials or approved demo mode are ready.
- Backend migrations/functions/secrets are deployed.
- Production APNs entitlement and Edge Function APNs environment are aligned.
