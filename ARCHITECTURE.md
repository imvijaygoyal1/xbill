# xBill Architecture

Last updated: 2026-05-04

## Overview

xBill is an iPhone-only SwiftUI app for shared expense tracking. The client is built with SwiftUI, Swift 6 strict concurrency, `@Observable` view models, Supabase Auth/Postgres/Realtime/Storage, APNs through Supabase Edge Functions, and a WidgetKit balance widget.

This document focuses on architectural surfaces that matter for App Store review, privacy, and future implementation decisions.

## Design System Architecture

The xBill redesign should be implemented as a design-system consolidation before screen-by-screen migration. The canonical design system is `xBill/DesignSystem`; future UI work should not add a parallel styling layer.

Current architecture risk: styling is split between `xBill/DesignSystem/Tokens`, `xBill/Core/DesignSystem`, and `xBill/Views/Components`. The redesign should migrate, wrap, or temporarily alias older `XBill*` and `Color.*` design APIs into the canonical `App*` token/component system, then remove compatibility aliases during the final audit where practical.

Canonical target structure:

- `xBill/DesignSystem/Tokens/AppColors.swift`
- `xBill/DesignSystem/Tokens/AppTypography.swift`
- `xBill/DesignSystem/Tokens/AppSpacing.swift`
- `xBill/DesignSystem/Tokens/AppRadius.swift`
- `xBill/DesignSystem/Tokens/AppShadow.swift`
- `xBill/DesignSystem/Tokens/AppGradient.swift`
- `xBill/DesignSystem/Components/*`
- `xBill/Helpers/GreetingHelper.swift`
- `xBill/Helpers/BalanceMessageHelper.swift`
- `xBill/PreviewData/PreviewData.swift`

Design-system rules:

- Screens own data, navigation, and composition only.
- Tokens own colors, typography, spacing, radius, shadows, gradients, sizes, and state values.
- Components own repeated UI and visual states.
- Reusable visual assets own app illustrations and icon containers using SwiftUI shapes, SF Symbols, gradients, avatar circles, receipt/bill shapes, and tokenized surfaces. Do not introduce external PNG/JPG assets for these visuals.
- `XBillPageHeader`, `XBillScreenContainer`, and `XBillScrollView` own page title, safe-area, scroll spacing, and sticky CTA behavior for redesigned screens. Main tabs should use in-content headers; modal/detail/form screens should use consistent custom headers/back placement or a deliberate navigation-bar pattern.
- No hardcoded colors, font sizes, spacing values, radii, shadows, or gradients should remain inside screen files after migration.
- Light and dark mode should be adaptive through tokens/components; do not create duplicate dark-mode screens.
- QR code components must force black QR content on a white surface in every color scheme.
- All interactive components must maintain at least 44pt tap targets.
- Top navigation uses adaptive screen background; near-black navigation styling belongs to the custom bottom tab bar.
- Creation flows that can scroll behind the keyboard or bottom chrome should use sticky full-width primary actions instead of toolbar-only save buttons.

Suggested rollout:

1. Stabilize adaptive tokens and compatibility aliases.
2. Build canonical components with light/dark previews and mock data.
3. Migrate shared chrome: background, buttons, cards, fields, rows, empty states, floating add button, and tab bar.
4. Migrate Auth and Onboarding.
5. Migrate main tabs: Home, Groups, Friends, Notifications, Profile.
6. Migrate creation/detail flows: New Group, Group Details, Add Expense, Add Friend, Add IOU, Edit Profile, QR Code.
7. Run a hardcoded-style audit, compile, and verify light/dark, Dynamic Type, QR scannability, and navigation preservation.

Detailed visual tokens, component requirements, screen requirements, and audit commands live in `DESIGN.md`.

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
- DEBUG UI test reset: launching with `--reset-state` clears the app UserDefaults domain and deletes xBill Keychain generic-password entries, keeping unauthenticated login UI tests isolated from prior simulator sessions.

Review-sensitive note: deletion currently needs a documented retention/anonymization policy for shared records such as expenses, splits, comments, group memberships, invites, avatars, and receipt images. Shared financial history may be retained for other group members only if the product and privacy policy explain it clearly.

## Build-Time Supabase Configuration

Supabase credentials are injected through build settings, not hardcoded Swift. `xBill/Info.plist` contains `$(SUPABASE_URL)` and `$(SUPABASE_ANON_KEY)`, and `SupabaseManager` reads those expanded values from `Bundle.main.infoDictionary`.

The source of truth for local secrets is `Secrets.xcconfig`, which is gitignored. `project.yml` must attach it through top-level XcodeGen `configFiles` entries for both Debug and Release. If `configFiles` is nested under `settings`, XcodeGen will generate a project that does not load the secrets.

Xcode `.xcconfig` files treat `//` as the start of a comment. Supabase URLs must therefore be escaped as:

```xcconfig
SUPABASE_URL = https:/$()/rhdhazevigbchmwzesok.supabase.co
```

Do not write the raw `https://...` form in `.xcconfig`. That compiles into `SUPABASE_URL = https:` and causes sign-in to fail with "A server with the specified hostname could not be found." After changing credentials or regenerating the Xcode project, verify the built app bundle's Info.plist contains the full Supabase URL before debugging Swift auth code.

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
- The `xbill` Pages project currently has no Git connection; deployments are direct uploads from the Cloudflare dashboard.
- Route mapping:
  - `web/index.html` → `/`
  - `web/invite/index.html` → `/invite`
  - `web/privacy/index.html` → `/privacy`
  - `web/terms/index.html` → `/terms`
- Direct-upload deployments replace the whole deployed asset set. Future changes should upload the full `web/` folder to avoid deleting legal pages.
- App URL constants live in `xBill/Core/Constants/XBillURLs.swift` and should be the only source for public web URLs in Swift code.
- Verified 2026-05-03: `/`, `/invite`, `/privacy`, and `/terms` all resolve publicly and serve raw HTML; `/privacy` and `/terms` redirect to trailing-slash routes before `HTTP 200`.
- Separate Git-backed web repo: `/Users/vijaygoyal/Documents/xbill-web`, remote `github.com:imvijaygoyal1/xbill-web`, Cloudflare Pages URL `https://xbill-web.pages.dev`. It uses root-level static files instead of a `web/` subdirectory: `index.html`, `invite/index.html`, `privacy/index.html`, `terms/index.html`.
- Routing decision: do not use a catch-all `_redirects` rule such as `/* /index.html 200` for these static pages. Cloudflare Pages can detect it as an infinite loop because the destination `/index.html` can be matched by the same catch-all. Directory `index.html` routing is sufficient for all current public pages.
- Deployment history: `xbill-web` commit `dda384d` introduced `_redirects` and triggered Cloudflare's "Infinite loop detected" warning/error. Commit `4d24915 Fix static pages rendering` removed `_redirects` and replaced Rich Text/Cocoa HTML output with raw HTML pages. `https://xbill-web.pages.dev/privacy` returning `308` to `/privacy/` before `HTTP 200` is normal Cloudflare Pages trailing-slash behavior.

## App Store Review Gates

Before submission, future work should verify:

- No placeholder URLs or metadata remain.
- Legal URLs are public and stable.
- App Store Connect privacy labels, privacy manifest, and actual data flows match.
- Account deletion behavior matches policy and reviewer expectations.
- Reviewer credentials or approved demo mode are ready.
- Backend migrations/functions/secrets are deployed.
- Production APNs entitlement and Edge Function APNs environment are aligned.
