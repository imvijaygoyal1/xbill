# xBill — Claude Code Context

> **IMPORTANT FOR CLAUDE:** After every code change to this project, update this file to reflect the change. New file → add to File Map. New pattern → update Key Patterns. This file must always stay current.
> **After every code change, run `xcodegen generate` if new Swift files were added, build for simulator, install the built `.app` on simulator DA97985A-F7CC-44F6-8281-9DD24C22B978, launch it once, and report the install/launch result.**
> **Native patterns:** Before writing any SwiftUI view, read `NATIVE_PATTERNS.md`. It defines the required conventions for navigation, lists, SF Symbols, typography, colors, controls, sheets, empty states, swipe actions, animations, accessibility, haptics, safe area, and performance. The xBill branded redesign in `DESIGN.md` overrides native defaults only where explicitly documented; keep Apple behavior for navigation, sheets, accessibility, inputs, and data-flow safety.

## App Identity
- **Name:** xBill
- **Bundle ID:** `com.vijaygoyal.xbill`
- **Platform:** iOS 17+, iPhone only
- **Swift:** 6.0, strict concurrency enabled
- **Architecture:** SwiftUI + `@Observable` + Supabase (PostgreSQL + Auth + Realtime)
- **Project path:** `/Users/vijaygoyal/MyiOSApp/xBill`
- **Project generation:** `xcodegen generate` (from `project.yml`)
- **Architecture doc:** `ARCHITECTURE.md`
- **Design system plan:** `DESIGN.md`
- **App Store review plan:** `APPSTORE_REVIEW_PLAN.md`

## Simulator
- **iPhone 17 Pro:** `DA97985A-F7CC-44F6-8281-9DD24C22B978` ← primary test device
- Build command:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build
  ```
- Install + launch (simctl requires DEVELOPER_DIR — xcrun simctl won't resolve in this env):
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 <APP_PATH>
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.xbill
  ```
- If simulator is Shutdown, boot it first:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/simctl boot DA97985A-F7CC-44F6-8281-9DD24C22B978
  ```
- **Always build, install, and launch on simulator after implementing a code change.** Do not stop at build/test success; the current app must be installed on `DA97985A-F7CC-44F6-8281-9DD24C22B978` unless the user explicitly says not to.

## Supabase
- **Project URL:** `https://rhdhazevigbchmwzesok.supabase.co`
- **Anon key:** stored in `Secrets.xcconfig` (gitignored) under `SUPABASE_URL` / `SUPABASE_ANON_KEY` build settings — NOT in `project.yml` (C1 fix)
- **Credentials injection:** `xBill/Info.plist` template uses `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` — do NOT use `GENERATE_INFOPLIST_FILE: YES` (it ignores custom build settings)
- **XcodeGen config:** `project.yml` must keep `configFiles` at the top level with `Debug: Secrets.xcconfig` and `Release: Secrets.xcconfig`. Do not nest it under `settings`; nested config files are ignored by generated Xcode projects.
- **Important xcconfig URL escaping:** In `.xcconfig`, `//` starts a comment, so write Supabase URLs as `https:/$()/rhdhazevigbchmwzesok.supabase.co`, not `https://rhdhazevigbchmwzesok.supabase.co`. If this regresses, the built app receives `SUPABASE_URL = https:` and sign-in fails with "A server with the specified hostname could not be found."
- **Auth:** Email/password + Sign In with Apple; email confirmation is ON in Supabase dashboard
- **Push migrations:** `supabase db push` from `/Users/vijaygoyal/MyiOSApp/xBill`
- **URL scheme:** `xbill://` — registered in `Info.plist` (`CFBundleURLTypes`); Supabase dashboard Site URL + Redirect URL set to `xbill://auth/callback`
- **Resend SMTP:** configured in Supabase dashboard (Auth → SMTP) using `smtp.resend.com:465`, username `resend`, password = Resend API key
- **Edge Functions:** `supabase/functions/invite-member/index.ts` — sends group invite emails via Resend API; secrets: `RESEND_API_KEY`, `INVITE_FROM_EMAIL`

## App Store Review Notes
- Review-sensitive work is tracked in `APPSTORE_REVIEW_PLAN.md`; consult it before any submission-oriented change.
- Current known blockers/risks include account deletion retention/anonymization scope, contact-email discovery disclosures, third-party network disclosures, receipt upload/privacy-label consistency, App Group UserDefaults required-reason review, App Store Connect privacy-label reconciliation, and reviewer demo access.
- Friend invite sharing uses `XBillURLs.appInvite` (`https://xbill.vijaygoyal.org/invite`), not a placeholder App Store URL.
- Public web pages for the app's stable custom domain are hosted on Cloudflare Pages project `xbill` (domains: `xbill.pages.dev`, `xbill.vijaygoyal.org`; production branch label `main`; direct upload/no Git connection). Deploy source lives in this repo under `web/`: `web/index.html`, `web/invite/index.html`, `web/privacy/index.html`, `web/terms/index.html`.
- A separate Git-backed Cloudflare Pages web repo also exists at `/Users/vijaygoyal/Documents/xbill-web`, remote `github.com:imvijaygoyal1/xbill-web`, Pages URL `https://xbill-web.pages.dev`. It contains root-level static files: `index.html`, `invite/index.html`, `privacy/index.html`, `terms/index.html`. Latest verified fixed commit: `4d24915 Fix static pages rendering`.
- Verified 2026-05-03: `/`, `/invite`, `/privacy`, and `/terms` all return valid raw HTML; `/privacy` and `/terms` may redirect to trailing-slash URLs before `HTTP 200`.
- Do not submit until App Store Connect privacy labels, `PrivacyInfo.xcprivacy`, in-app legal links, and backend data flows have been reconciled.

## Public Web / Cloudflare Pages
- **Cloudflare Pages project:** `xbill`
- **Domains:** `https://xbill.vijaygoyal.org`, `https://xbill.pages.dev`
- **Deployment mode:** direct upload / no Git connection. Future agents cannot deploy by pushing this repo unless Cloudflare is reconfigured.
- **Deployable source folder:** `web/`
  - `web/index.html` → `https://xbill.vijaygoyal.org/`
  - `web/invite/index.html` → `https://xbill.vijaygoyal.org/invite`
  - `web/privacy/index.html` → `https://xbill.vijaygoyal.org/privacy`
  - `web/terms/index.html` → `https://xbill.vijaygoyal.org/terms`
- **Important:** Cloudflare direct upload replaces the deployed asset bundle. Upload the whole `web/` folder so `/privacy` and `/terms` are not accidentally removed when changing `/invite`.
- **Post-deploy verification:**
  ```
  curl -L -I https://xbill.vijaygoyal.org
  curl -L -I https://xbill.vijaygoyal.org/invite
  curl -L -I https://xbill.vijaygoyal.org/privacy
  curl -L -I https://xbill.vijaygoyal.org/terms
  curl -L https://xbill.vijaygoyal.org/privacy | head
  ```
- **Expected:** all endpoints end at `HTTP 200` and content starts with `<!DOCTYPE html>`. If output contains `Cocoa HTML Writer`, `<p class="p1">`, or `&lt;!DOCTYPE`, the page was saved as rich text and must be replaced with raw HTML.
- **Redirect rule warning:** do not add `_redirects` with `/* /index.html 200` for this static site. Cloudflare detects it as an infinite loop because `/index.html` can match the same catch-all rule again. These pages use directory `index.html` files, so Cloudflare Pages automatically serves `/invite`, `/privacy`, and `/terms` without a catch-all.
- **Git-backed web repo:** `/Users/vijaygoyal/Documents/xbill-web` is a separate repo for Cloudflare Pages Git deployment experiments. It is not the iOS app repo. Current structure is:
  - `index.html`
  - `invite/index.html`
  - `privacy/index.html`
  - `terms/index.html`
- **Git-backed verification:** `git ls-remote origin main` should show `4d24915...` or newer. `https://xbill-web.pages.dev/privacy` may first return `308 Location: /privacy/`, then `HTTP 200` when followed with `curl -L -I`; that trailing-slash redirect is normal and is not the previous infinite-loop error.
- **Routing rule history:** commit `dda384d` in `xbill-web` added `_redirects` for `/privacy` plus a catch-all rule and caused Cloudflare's "Infinite loop detected" warning/error. Commit `4d24915` removed `_redirects` and replaced Cocoa/Rich Text HTML with raw static HTML files.

## Database Schema

### Tables
| Table | Key columns |
|-------|-------------|
| `profiles` | `id uuid PK (→ auth.users)`, `email text`, `display_name text`, `avatar_url text`, `created_at` |
| `groups` | `id uuid PK`, `name text`, `emoji text`, `currency text DEFAULT 'USD'`, `created_by uuid`, `is_archived bool`, `created_at` |
| `group_members` | `group_id uuid`, `user_id uuid`, `joined_at` |
| `expenses` | `id uuid PK`, `group_id uuid`, `title text`, `amount numeric`, `currency text`, `category text`, `notes text`, `paid_by uuid`, `recurrence text DEFAULT 'none'`, `next_occurrence_date timestamptz`, `created_at` |
| `splits` | `id uuid PK`, `expense_id uuid`, `user_id uuid`, `amount numeric`, `is_settled bool` |
| `comments` | `id uuid PK`, `expense_id uuid`, `user_id uuid`, `text text`, `created_at` |
| `group_invites` | `token text PK (default: uuid stripped of dashes)`, `group_id uuid`, `created_by uuid`, `expires_at (default: +7 days)` |
| `ious` | `id uuid PK`, `created_by uuid`, `lender_id uuid`, `borrower_id uuid`, `amount numeric`, `currency text`, `description text`, `is_settled bool`, `created_at` — CHECK: `created_by = lender_id OR created_by = borrower_id`, `lender_id != borrower_id` |

### RPC Functions
- `add_expense_with_splits(p_group_id, p_paid_by, p_amount, p_title, p_category, p_currency, p_notes, p_receipt_url, p_splits[], p_original_amount, p_original_currency, p_recurrence, p_next_occurrence_date)` — atomic expense + splits insert; `p_splits` is an array of `split_input` composite type `{user_id uuid, amount numeric}`; recurrence/next_occurrence_date are optional (default 'none'/null)

### Migrations (in order)
1. `001_initial_schema.sql` — All tables, RLS, `is_group_member()` + `is_expense_group_member()` helpers
2. `002_rpc_add_expense.sql` — `split_input` composite type + `add_expense_with_splits` RPC
3. `003_profiles_add_email.sql` — `ALTER TABLE profiles ADD COLUMN email text NOT NULL DEFAULT ''`
4. `004_profile_trigger.sql` — `handle_new_user()` trigger: auto-creates profile row on `auth.users` INSERT (runs as `SECURITY DEFINER`, bypasses RLS)
5. `005_backfill_profiles.sql` — Inserts profiles for existing auth users without profile rows
6. `006_groups_currency_member_rls.sql` — Adds `currency` to groups; fixes RLS to allow group creator to insert themselves as first member
7. `007_groups_creator_read.sql` — Fixes groups SELECT policy to allow `created_by = auth.uid()`, so the INSERT RETURNING clause succeeds before the creator is added as a member
13. `013_multi_currency.sql` — Adds `original_amount numeric` + `original_currency text` to expenses; recreates `add_expense_with_splits` RPC with new optional params
14. `014_ious.sql` — `ious` table with RLS; `lender_id`/`borrower_id`/`created_by` constraints
11. `011_expense_comments.sql` — `comments` table; RLS (group members can view/insert, author can delete); Realtime enabled
12. `012_group_invites.sql` — `group_invites` table; `join_group_via_invite(p_token)` SECURITY DEFINER RPC (validates expiry, idempotent insert into group_members, returns group_id)
15. `015_recurring_expenses.sql` — Adds `recurrence text DEFAULT 'none'` + `next_occurrence_date timestamptz` to expenses; recreates RPC with new optional params
16. `016_create_device_tokens_table.sql` — Creates `public.device_tokens (id, user_id → auth.users cascade, token, platform DEFAULT 'apns', created_at)`; RLS enabled; "Users manage own tokens" policy. (Migration 010 only added a `device_token` column to `profiles` — this is the actual table.)
17. `017_fix_user_delete_constraints.sql` — Changes `groups.created_by` and `expenses.paid_by` FK constraints from `ON DELETE RESTRICT` to `ON DELETE SET NULL` (with columns made nullable). Fixes auth user deletion being blocked when the user had created groups or paid for expenses.
18. `018_lookup_profiles_by_email.sql` — `SECURITY DEFINER` RPC `lookup_profiles_by_email`; excludes current user; granted only to `authenticated` role
19. `019_device_tokens_unique.sql` — Adds `UNIQUE (user_id, token)` constraint to `device_tokens` to prevent duplicate rows and enable safe upserts.
20. `020_friends_table.sql` — `friends` table (requester_id, addressee_id, status: pending/accepted/blocked); RLS (both parties select/delete, requester inserts, addressee updates); `send_friend_request(p_addressee_id)` idempotent RPC; `respond_to_friend_request(p_requester_id, p_accept)` RPC; `search_profiles(p_query)` RPC (ilike on email + display_name, max 20 results, excludes self).

## File Map

### Entry Point
- `xBill/xBillApp.swift` — `@main`, creates `AuthViewModel`, passes to `ContentView`, starts auth listener + loads current user; `.onOpenURL` dispatches on `url.host`: `"join"` → sets `authVM.pendingJoinRequest`; `"add"` → sets `AppState.shared.pendingAddFriendUserID` (QR/deep-link add-friend flow); default → passes to `supabase.auth.session(from:)` for auth redirects; `AppDelegate` conforms to `UNUserNotificationCenterDelegate`: `willPresent` returns `.banner + .sound + .badge`, `didReceive` sets `AppState.shared.pendingNotificationTarget`

### Edge Functions
- `supabase/functions/invite-member/index.ts` — Deno; calls Resend API to send group invite emails; expects `{ groupName, groupEmoji, inviterName, emails[] }`; returns `{ sent, failed[] }`
- `supabase/functions/notify-expense/index.ts` — Reads tokens from `device_tokens`; excludes sender (`payerId`); per-recipient badge via `getUnreadCount`; JWT cached 55 min; `apns-expiration: +1h`; stale token cleanup on 410/400; sandbox URL when `isDevelopment: true`; expects `{ expenseId, groupId, payerId, payerName, expenseTitle, amount, currency, isDevelopment }`
- `supabase/functions/notify-settlement/index.ts` — Pushes creditor (toUserID) only; same JWT cache, expiration, stale cleanup, sandbox URL logic; expects `{ settlementId, groupId, groupName, fromUserID, fromName, toUserID, amount, currency, isDevelopment }`
- `supabase/functions/notify-comment/index.ts` — Pushes all expense participants (splits + payer) except commenter; 60-char comment preview; same JWT cache, expiration, stale cleanup, sandbox URL; expects `{ expenseId, expenseTitle, groupId, groupName, commenterID, commenterName, commentText, isDevelopment }`
- `supabase/functions/notify-friend-request/index.ts` — Pushes the addressee when they receive a friend request; same JWT cache, stale-token cleanup, sandbox URL patterns; expects `{ toUserID, fromName, fromUserID, isDevelopment }`; fired fire-and-forget from `FriendService.sendFriendRequest`

### Design System
- **Current redesign direction:** xBill is migrating to a canonical Manhattan-disciplined playful fintech design system under `xBill/DesignSystem`. Before redesign work, read `DESIGN.md` and the Design System Architecture section in `ARCHITECTURE.md`.
- **Canonical target:** `xBill/DesignSystem/Tokens` for all colors, typography, spacing, radius, shadow, and gradient decisions; `xBill/DesignSystem/Components` for repeated UI; `xBill/Helpers` for greeting/balance message logic; `xBill/PreviewData` for realistic previews.
- **Migration rule:** do not add one-off styling in screens. Existing `xBill/Core/DesignSystem` and `xBill/Views/Components` APIs are legacy/compatibility surfaces during migration; wrap or alias them into the canonical system rather than creating another styling layer.
- **Required target components:** `XBillScreenBackground`, `XBillHeroCard`, `XBillBalanceCard`, `XBillActionCard`, `XBillGroupCard`, `XBillExpenseRow`, `XBillFriendRow`, `XBillNotificationRow`, `XBillProfileCard`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, `XBillSettingsRow`, `XBillEmptyState`, `XBillPrimaryButton`, `XBillSecondaryButton`, `XBillBlackButton`, `XBillTextField`, `XBillSearchBar`, `XBillSegmentedControl`, `XBillTabBar`, `XBillFloatingAddButton`, `XBillAvatarStack`, `XBillIconPickerGrid`, `XBillQRCodeCard`, and `HomeHeader`.
- **Audit rule:** after UI migration, search for hardcoded `Color(hex:)`, raw `Color.white`/`Color.black`, screen-local `.font(.system(size:))`, hardcoded numeric padding/radius/shadows, and screen-local gradients.
- `xBill/DesignSystem/Tokens/AppColors.swift` — canonical adaptive light/dark palette for primary purple, soft lavender/dark navy backgrounds, surfaces, text, borders, money colors, and input colors.
- `xBill/DesignSystem/Tokens/AppTypography.swift` — canonical SF Pro font tokens: display, h1, h2, title, body, caption, amount, icon, tab label, and badge styles.
- `xBill/DesignSystem/Tokens/AppSpacing.swift` — canonical spacing scale plus `tapTarget = 44`, `controlHeight = 52`, `tabBarHeight`, and `floatingActionBottomPadding`.
- `xBill/DesignSystem/Tokens/AppRadius.swift` — canonical radius scale.
- `xBill/DesignSystem/Tokens/AppShadow.swift` — canonical adaptive card/hero/FAB shadow values plus legacy shadow compatibility helpers.
- `xBill/DesignSystem/Tokens/AppGradient.swift` — canonical hero and soft primary gradients.
- `xBill/DesignSystem/Components/` — canonical redesign components: screen background, screen headers, hero/balance/action/group/profile cards, rows, empty state, buttons, search bar, segmented control, custom tab bar, floating add button, avatar stack, icon picker, QR card, SwiftUI-only visual assets, and `HomeHeader`.
- `xBill/DesignSystem/Components/XBillIllustrationKit.swift` — large reusable SwiftUI-only illustrations: `XBillSplitBillIllustration`, `XBillWalletIllustration`, `XBillEmptyStateIllustration`, `XBillFriendsIllustration`, `XBillReceiptIllustration`, and `XBillQRCodeIllustration`. Use 180–240pt visual scale for auth/empty/form/QR surfaces; no PNG/JPG assets.
- `xBill/DesignSystem/Components/XBillVisualAssets.swift` — smaller reusable visual primitives: `XBillLogoMark`, `XBillReceiptIcon`, `XBillAvatarPlaceholder`, `XBillCategoryIcon`, and `XBillQRPlaceholderFrame`.
- `xBill/DesignSystem/Components/XBillPageHeader.swift` — canonical page header with large title, optional subtitle, optional trailing action, optional back button, 24pt horizontal padding, 12pt top padding, 16pt bottom padding, and `AppColors.background`.
- `xBill/DesignSystem/Components/XBillDetailHeader.swift` — reusable modal/detail/form header wrapper for Add Friend, Add Expense, Add IOU, New Group, Edit Profile, and QR-style screens; uses `XBillPageHeader` with a 44pt back button and optional trailing action.
- `xBill/DesignSystem/Components/XBillScreenHeader.swift` — reusable main-screen header wrapper for Friends/Groups/Alerts/Profile-style screens; supports title, optional subtitle, and optional 44pt circular trailing icon action.
- `xBill/DesignSystem/Components/XBillScreenContainer.swift` — canonical screen wrapper around `XBillScreenBackground`; supports scroll/fixed modes, consistent horizontal padding, bottom padding, and sticky bottom CTA content.
- `xBill/DesignSystem/Components/XBillScrollView.swift` — canonical vertical scroll wrapper with consistent indicators, `LazyVStack`, `AppSpacing.lg` content spacing, and bottom padding for tab/sticky CTA clearance.
- `xBill/DesignSystem/Components/XBillIllustrationCard.swift` — reusable soft-surface illustration container with tokenized radius, border, background, and adaptive card shadow; used by `XBillEmptyState` and available for future empty/auth/detail art.
- `xBill/DesignSystem/Components/XBillDashboardPrimitives.swift` — reusable dashboard primitives: `XBillSectionHeader`, `XBillMetricCard`, `XBillStatusChip`, and `XBillCircularIconButton`; used by Home/Groups and intended for other metric/action dashboards.
- `xBill/DesignSystem/Components/XBillActionRow.swift` — reusable surface-card action row with leading SF Symbol container, title, optional subtitle, optional chevron, tokenized 44pt+ tap target; use for Import from Contacts, Share QR Link, Scan QR Code, and similar navigation/action rows.
- `xBill/DesignSystem/Components/XBillArchivedRow.swift` — reusable secondary-navigation row for archived groups or similar collapsible sections; icon, title, subtitle, chevron, tokenized soft surface/border, 44pt+ tap target, and VoiceOver state label.
- `xBill/DesignSystem/Components/XBillGroupCard.swift` — canonical group row/card: avatar placeholder, title/subtitle, active/archived status chip, optional avatar stack, optional semantic balance, optional chevron, tokenized surface/radius/border/shadow, and consolidated VoiceOver label.
- `xBill/DesignSystem/Components/XBillSearchBar.swift` — canonical rounded search field with tokenized surface/border/spacing/typography and placeholder accessibility label; use across Groups, Friends, Activity, Add Friend, and Group Details search surfaces.
- `xBill/DesignSystem/Components/XBillNotificationRow.swift` — reusable notification/activity card row with unread indicator, event icon, title/subtitle, timestamp, amount badge, optional chevron, tokenized surface styling, and consolidated VoiceOver label.
- `xBill/DesignSystem/Components/XBillProfilePrimitives.swift` — reusable profile/settings primitives: `XBillInfoRow`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, `XBillSettingsRow`, and `XBillSettingsChevron`; use for Profile, Settings, Edit Profile, and future form/settings surfaces.
- `xBill/DesignSystem/Components/XBillTabBar.swift` — reusable premium custom tab bar component. **Do not use it in `MainTabView` unless the product decision changes; the main app shell currently uses the native SwiftUI/iOS tab bar to avoid duplicate bottom navigation and preserve platform behavior.**
- `xBill/DesignSystem/Components/XBillButtons.swift` — canonical primary/secondary/black buttons plus compact `XBillPillButton` for Add/Pending row actions; all use tokenized colors, typography, radius, and 44pt+ tap targets.
- **Title/scroll pattern:** main tabs use in-content `XBillPageHeader`/`HomeHeader` and hidden navigation chrome; modal/detail/form screens use `XBillPageHeader` with consistent back placement and sticky CTA where forms save. Avoid adding one-off `.navigationTitle` styling to redesigned screens.
- **2026-05-04 UI hardening:** top navigation chrome should use `AppColors.background`; reserve `AppColors.blackNav` for `XBillTabBar`. Sticky save actions are required for Add Expense and Add IOU. Empty Friends state must not show the Add IOU FAB because it overlaps the Add Friend CTA and there is no IOU target yet.
- **2026-05-05 Groups polish validation:** `xcodegen generate`, Debug simulator build, and unit tests passed. `GroupFlowUITests` was updated for the custom SwiftUI header/card architecture and passed with 16 executed tests, 2 expected simulator-dependent skips, and 0 failures. Clean up `com.vijaygoyal.xbill.uitests.xctrunner` after every UI test run.
- **2026-05-05 tab bar correction:** `MainTabView` must render exactly one native SwiftUI/iOS tab bar. Do not add `XBillTabBar` in a bottom `safeAreaInset` while `.tabItem` is present; that creates duplicate bottom navigation.
- **2026-05-06 Friends polish:** Friends tab uses `XBillScrollView`, `XBillScreenHeader`, `XBillEmptyState`, `XBillIllustrationCard`, `XBillSectionHeader`, and enhanced `XBillFriendRow`; pending requests, accepted friends, IOU counterparties, Add Friend sheet, Add IOU FAB, refresh, and friend-detail navigation are preserved. Validation: XcodeGen, Debug simulator build, xBillTests, UI-test-runner cleanup, simulator install, and simulator launch all succeeded.
- **2026-05-06 Add Friend polish:** Add Friend uses `XBillScreenContainer`, `XBillDetailHeader`, one `XBillIllustrationCard`, `XBillSearchBar`, `XBillActionRow`, `XBillFriendRow`, compact no-illustration `XBillEmptyState`, and `XBillPillButton`. Preserved profile search, contact import, app invite, `xbill://add/<userID>` QR-link sharing, preloaded QR deep-link suggestions, Add/Pending request state, and `onAdded`.
- **2026-05-06 Notifications polish:** Activity/Alerts now presents as `Notifications` with `XBillScreenHeader`, `XBillScreenContainer`, `XBillScrollView`, `XBillEmptyState`, `XBillSectionHeader`, and reusable `XBillNotificationRow`; unread grouping, mark-all-read, per-alert detail viewing, context-menu and swipe read/unread/delete actions, refresh/loading, empty state, notification store integration, and native tab bar behavior are preserved. Opening the tab no longer marks every alert read; badges update from per-item read state. Bell illustration appears once through the reusable empty state. Validation: `xBillTests` passed with 96 tests, UI-test-runner cleanup succeeded, and the app installed/launched on the simulator.
- **2026-05-06 Profile polish:** Profile uses a normal `ScrollView` inside `XBillScreenBackground` for stable native-tab scrolling, plus `XBillScreenHeader`, enhanced compact `XBillProfileCard`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, and `XBillSettingsRow`; QR, edit profile, payment handles, notification toggles, app lock, sign out, delete account, legal links, refresh, and native tab bar behavior are preserved. Email is single-line middle-truncated and Edit is a fixed-width non-wrapping pill.
- `xBill/Helpers/GreetingHelper.swift` — time-of-day greeting helper for `HomeHeader`.
- `xBill/Helpers/BalanceMessageHelper.swift` — net-balance message helper for Home; keep output icon-free and let UI components provide SF Symbol status icons.
- `xBill/PreviewData/PreviewData.swift` — shared mock users, groups, and expenses for component previews.
- `xBill/Views/Components/XBillWordmark.swift` — `XBillWordmark` view: "xBill" in `.heavy` 22pt `brandPrimary`, tracking -0.8 + kerning -0.5; used as `.principal` toolbar item in `HomeView`
- `xBill/Core/DesignSystem/XBillTheme.swift` — `XBillTheme` enum (clay-inspired theme): `background` (warm cream `#faf9f7`), `surface` (white), `primaryBrand` (Ube 800), `accentMint` (Matcha 600), `accentCoral` (Pomegranate 400); clay multi-layer shadow; `cardRadius = 24`, `sectionRadius = 40`; `ClayCard` ViewModifier (white, 24pt corners, oat border `#dad4c8`, multi-layer shadow, optional dashed border); `ClayButtonStyle` (press: scaleEffect 0.94 + rotationEffect -3° + hard offset shadow); `SwatchSection` modifier for full-width colored sections; `View.asClayCard()` + `View.asSharpCard()` (alias) + `View.swatchSection(_:radius:)` extensions
- `xBill/Core/DesignSystem/XBillColors.swift` — `Color` extension with asset catalog tokens + clay swatch palette: `clayMatcha` (#078a52), `claySlushie` (#3bd3fd), `clayLemon` (#fbbd41), `clayUbe` (#43089f), `clayPomegranate` (#fc7981), `clayBlueberry` (#01418d), `clayCanvas` (#faf9f7), `clayOatBorder` (#dad4c8), `claySilver` (#9f9b93), plus light/dark swatch variants
- `xBill/Core/DesignSystem/XBillFonts.swift` — `Font` extension; clay weight hierarchy: 600 (headings/`.bold`/`.semibold`) / 500 (UI/`.medium`) / 400 (body/`.regular`); amounts use `.monospaced`; all others `.rounded`; `xbillUpperLabel` for uppercase labels (apply `.tracking(1.08)` at call site); **all tokens use Dynamic Type text styles** — do NOT revert to fixed `size:` integers
- `xBill/Core/DesignSystem/XBillLayout.swift` — `XBillSpacing`, `XBillRadius` (clay scale: `.sharp`=4, `.sm`=8, `.md`=12, `.card`=24, `.section`=40, `.full`=999), `XBillIcon` enums
- `xBill/Core/Extensions/HapticManager.swift` — `@MainActor enum HapticManager` with `impact(_:)`, `success()`, `error()`, `selection()` helpers

### Color Assets (Assets.xcassets)
31 named color sets with light/dark variants: `BrandPrimary`, `BrandAccent`, `BrandSurface`, `BrandDeep`, `BgPrimary`, `BgSecondary`, `BgTertiary`, `BgCard`, `TextPrimary`, `TextSecondary`, `TextTertiary`, `TextInverse`, `MoneyPositive`, `MoneyNegative`, `MoneySettled`, `MoneyTotal`, `MoneyPositiveBg`, `MoneyNegativeBg`, `MoneySettledBg`, `Separator`, `TabBarBg`, `NavBarBg`, `InputBg`, `InputBorder`, `CatFood`, `CatTravel`, `CatHome`, `CatEntertain`, `CatHealth`, `CatShopping`, `CatOther`

### Core
- `xBill/Core/AppState.swift` — `@Observable final class AppState: @unchecked Sendable` singleton (`AppState.shared`); `pendingQuickAction: QuickAction?` (.addExpense/.scanReceipt) set by AppDelegate; `spotlightTarget: SpotlightTarget?` (.group(UUID)) set by Spotlight NSUserActivity handler in xBillApp; `pendingNotificationTarget: NotificationTarget?` (.group(UUID)) set by `UNUserNotificationCenterDelegate.didReceive` on push notification tap; `pendingAddFriendUserID: UUID?` set when `xbill://add/<userID>` deep link is opened; all four consumed by MainTabView via `.task(id:)`
- `xBill/Core/SupabaseClient.swift` — `SupabaseManager.shared`; reads URL/key from `Bundle.main.infoDictionary`; graceful fallback to placeholder (no crash) when credentials missing
- `xBill/Core/AppError.swift` — `AppError` enum: `.network`, `.auth`, `.database`, `.confirmationRequired`, `.unknown`; `static func from(_ error: Error) -> AppError`
- `xBill/Core/Constants/XBillURLs.swift` — `enum XBillURLs` with `privacyPolicy`, `termsOfService`, and `landingPage` static `URL` constants; always reference these instead of hardcoding URL strings
- `xBill/Core/Extensions.swift` — `View.errorAlert(error:)` modifier; `Decimal.formatted(currencyCode:)`; `errorAlert` shows `error.errorDescription` as title (not generic "Something went wrong"); `Color.init(hex:)` initializer for hex strings (e.g. `Color(hex: "#FF6B6B")`)
- `xBill/Core/KeychainManager.swift` — Keychain read/write helpers
- `xBill/Core/NetworkMonitor.swift` — `NWPathMonitor` wrapper

### Models
- `xBill/Models/IOU.swift` — `struct IOU` (id, createdBy, lenderID, borrowerID, amount, currency, description, isSettled, createdAt)
- `xBill/Models/Comment.swift` — `struct Comment: Codable, Identifiable, Sendable` (id, expenseID, userID, text, createdAt)
- `xBill/Models/GroupInvite.swift` — `struct GroupInvite: Codable, Identifiable, Sendable` (token, groupID, createdBy, expiresAt); `inviteURL` computed property → `xbill://join/<token>`
- `xBill/Models/Friend.swift` — `struct Friend: Codable, Identifiable, Sendable` → matches `friends` table (id, requesterID, addresseeID, status: FriendStatus, createdAt); `enum FriendStatus: String, Codable` (.pending/.accepted/.blocked)
- `xBill/Models/User.swift` — `struct User: Codable, Identifiable` → matches `profiles` table (id, email, displayName, avatarURL, createdAt)
- `xBill/Models/Group.swift` — `struct BillGroup: Codable, Identifiable` (NOT `Group` — would clash with `SwiftUI.Group`); `struct GroupMember`
- `xBill/Models/Expense.swift` — `struct Expense`, `enum Expense.Category` (with `displayName`, `systemImage`, `allCases`)
- `xBill/Models/Split.swift` — `struct Split`; `SplitStrategy` has `.equal`, `.percentage`, `.exact`, `.shares`; `SplitInput` has `shares: Int` (default 1) for weighted sharing
- `xBill/Models/Settlement.swift` — `struct SettlementSuggestion: Identifiable` (fromName, toName, amount, currency)
- `xBill/Models/Receipt.swift` — `struct Receipt` for OCR-scanned receipts; `transactionDate: Date?` added (coding key `transaction_date`) — extracted by `NSDataDetector` from OCR text and surfaced in ReceiptReviewView
- `xBill/Models/ActivityItem.swift` — legacy stub; replaced by `NotificationItem`
- `xBill/Models/NotificationItem.swift` — `struct NotificationItem: Identifiable, Sendable, Codable` (id, eventType, title, subtitle, amount, currency, category, createdAt, isRead); `NotificationEventType` enum (.expenseAdded, .settlementMade); static factory methods `.expense(...)` and `.settlement(...)`
- `xBill/Models/ReceiptJSON.swift` — `ParsedReceiptJSON` + `ParsedItemJSON` (Decodable); shared output schema for both FoundationModelService and heuristic parser

### Services
- `xBill/Services/ExchangeRateService.swift` — `actor`; fetches from `open.er-api.com/v6/latest/{base}` (no key needed); 1-hour in-memory cache; `convert(amount:from:to:)` and `rate(from:to:)`; `commonCurrencies` static array of 20 codes
- `xBill/Services/FriendService.swift` — `final class FriendService: Sendable`; `fetchFriends(userID:)`, `fetchPendingReceived(userID:)`, `fetchPendingSent(userID:)`, `sendFriendRequest(to:)` (calls `send_friend_request` RPC + fires `notify-friend-request` push as fire-and-forget), `acceptRequest(from:)`, `declineRequest(from:)`, `removeFriend(id:currentUserID:)`, `searchProfiles(query:)` (partial ilike, uses `search_profiles` RPC from migration 020), `lookupByContactEmails([String])` (reuses migration 018 RPC), `friendshipStatus(currentUserID:otherUserID:)`, `fetchMutualGroupIDs(currentUserID:friendID:)` (parallel fetch of group_members for both users, returns intersection)
- `xBill/Services/IOUService.swift` — `fetchIOUs(userID:)` (two queries: as lender + as borrower, deduplicated), `fetchUserByEmail(_:)`, `createIOU(...)`, `settleIOU(id:)`, `settleAllIOUs(with:currentUserID:)`, `deleteIOU(id:)`
- `xBill/Services/CacheService.swift` — Prefers `UserDefaults(suiteName: "group.com.vijaygoyal.xbill")` (App Group for widget sharing), falls back to `.standard`; `nonisolated(unsafe)` static `defaults`; `saveGroups/loadGroups`, `saveExpenses/loadExpenses(groupID:)`, `saveMembers/loadMembers(groupID:)`; `saveBalance(netBalance:totalOwed:totalOwing:)` + load helpers for BalanceWidget
- `xBill/Services/AppLockService.swift` — `@Observable @MainActor` singleton; `isEnabled` via `UserDefaults`, `isLocked: Bool`, `authenticate()` via `LAContext.deviceOwnerAuthentication`, `lock()` (no-op when not enabled); `biometryType`, `lockIconName`, `unlockLabel` helpers
- `xBill/Services/CommentService.swift` — `fetchComments(expenseID:)`, `addComment(expenseID:userID:text:)`, `deleteComment(id:)`, `commentChanges(expenseID:) → AsyncStream<Void>` (Realtime subscription filtered by expense_id)
- `xBill/Services/AuthService.swift` — `signUpWithEmail`, `signInWithEmail`, `signInWithApple` (CryptoKit SHA256 nonce), `signOut`, `fetchProfile`, `currentUser()`; `sendPasswordReset` includes `redirectTo: URL(string: "xbill://reset")!` so deep link triggers `.passwordRecovery` event; `deleteAccount()` calls `delete-account` Edge Function with JWT header then signs out — throws `AppError.unauthenticated` if no session; all table refs use `"profiles"` (not `"users"`)
- `xBill/Services/GroupService.swift` — `fetchGroups(for:)` / `fetchArchivedGroups(for:)` (both two-step: `memberGroupIDs` → `groups` with server-side `is_archived` filter), `fetchMembers(groupID:)`, `createGroup(...)`, `addMember(groupId:userId:)`, `removeMember(groupId:userId:)`, `inviteMembers(emails:groupName:groupEmoji:inviterName:)`, `groupChanges(userID:) → AsyncStream<Void>` (subscribes to both `group_members` + `groups` tables), `createInvite(groupID:createdBy:)`, `fetchInvite(token:)`, `joinGroupViaInvite(token:) → UUID`
- `xBill/Services/ExpenseService.swift` — `fetchExpenses(groupID:)`, `fetchExpense(id:)`, `fetchSplits(expenseID:)`, `fetchUnsettledExpenses(groupID:userID:)`, `createExpense(...)` (uses `add_expense_with_splits` RPC — atomic), `updateExpense(_:)`, `settleSplit(id:)`, `deleteExpense(id:)`, `uploadReceiptImage(_:expenseID:)`
- `xBill/Services/SplitCalculator.swift` — `splitEqually`, `splitByPercentage`, `splitByShares`, `validateExact`, `netBalances(expenses:splits:)`, `minimizeTransactions(balances:names:currency:)`. `splitByShares` distributes proportionally to each `SplitInput.shares` value with rounding absorbed by first participant. `netBalances` skips settled splits and payer's own split — only unsettled non-payer splits affect balances. Used by both `GroupViewModel` and `HomeViewModel` for consistent balance computation.
- `xBill/Services/SpotlightService.swift` — `enum SpotlightService`; `indexGroups(_:)` / `removeGroup(id:)` and `indexExpenses(_:groupName:groupEmoji:)` / `removeExpense(id:)` — fire-and-forget CSSearchableIndex operations; identifiers use `"group:<uuid>"` / `"expense:<uuid>"` prefixes
- `xBill/Services/PaymentLinkService.swift` — Venmo deep-link URL generation
- `xBill/Services/VisionService.swift` — Two-tier receipt parsing + 7 quality improvements (Gaps 1–6 + 7). Public API: `scanReceipt(from:)` and `scanMultiPage(from:[UIImage])`. Returns `ScanResult(receipt:confidence:tier:validationWarning:suggestedCategory:)`. **Gap 1 — Pre-Processing**: `preprocessForOCR` pipeline: resize to 1200px → `CIPhotoEffectNoir` grayscale → `CIColorControls` contrast 1.4×/brightness +0.05 → `CISharpenLuminance` 0.4; called in `recognizeText` before OCR; each step has graceful fallback. **Gap 2 — Quality Gate**: `checkImageQuality` throws for too-dark, too-blurry, or no-text images. **Gap 3 — OCR Config**: `customWords` (27 terms), `minimumTextHeight=0.015`, device `recognitionLanguages`, `topCandidates(3)` — alternates stored in `OCRLine.alternates: [String]` for Gap 7. **Gap 4 — Date**: `NSDataDetector` → `Receipt.transactionDate`. **Gap 5 — NL**: `detectLanguage` + `suggestCategory`. **Gap 6 — Multi-Page**: Y-offset stacking, proportional threshold. **Gap 7 — Constraint-Solving**: `private struct ParsedItem` tracks alternate prices per item; `parseWithHeuristics` returns `(receipt:Receipt, candidates:[ParsedItem])`; `reconcile(candidates:total:tax:tip:)` tries alternate OCR prices when |delta| ≤ $2.00; on success updates items and clears validation warning; only attempted on Tier 2 (Tier 1 handles this via LLM).
- `xBill/Services/FoundationModelService.swift` — `@available(iOS 26.0, *)`. `parseReceipt(ocrText:language:)` — `language` is BCP-47 tag from `NLLanguageRecognizer` (e.g. "fr", "de"), injected into the system prompt for non-English receipt accuracy. `@Generable` schema adds `transactionDate: String?` ("YYYY-MM-DD" format); re-parsed by `VisionService.extractTransactionDate`. Minimum quality check: rejects OCR text with < 3 lines. Returns `ParsedReceiptJSON` (now includes `transactionDate: String?`). Falls through to heuristics on failure.
- `xBill/Services/NotificationStore.swift` — local-first notification persistence; `merge([NotificationItem])` deduplicates by id, caps at 100 items, and preserves existing read state; per-item APIs: `markRead(id:)`, `markUnread(id:)`, `delete(id:)`; `markAllRead()` marks stored items read and updates `lastViewedAt()` for backward compatibility; `unreadCount()` returns unread stored items; uses `CacheService.defaults` (App Group UserDefaults); `clearAll()` for test teardown
- `xBill/Services/ActivityService.swift` — returns `[NotificationItem]`; fetches expenses per group in parallel, merges into `NotificationStore`, returns combined list sorted newest-first
- `xBill/Services/NotificationService.swift` — Local push notifications; settlement reminders only (`scheduleExpenseAddedNotification` removed — was firing locally for the person who added the expense, which is useless)
- `xBill/Services/ExpenseService.swift` — `notifyExpenseAdded(...)` and `notifySettlementRecorded(...)` both invoke Edge Functions as fire-and-forget `Task`s; both gated on `UserDefaults prefPush*` prefs
- `xBill/Services/CommentService.swift` — `addComment(expenseID:userID:text:expenseTitle:groupID:groupName:commenterName:)` fires `notify-comment` Edge Function after insert; gated on `prefPushComment`
- `xBill/Views/Main/NotificationPermissionView.swift` — Pre-prompt sheet explaining push value before triggering OS dialog; "Allow Notifications" / "Not Now"; shown once via `@AppStorage("hasPromptedNotificationPermission")`
- `xBill/Services/ExportService.swift` — `@MainActor`; `generateCSV(group:expenses:memberNames:) -> Data`; `generatePDF(group:expenses:memberNames:balances:) -> Data` (PDFKit A4 report with summary, balances, expense table); `writeTemp(data:filename:) throws -> URL` for share sheet

### ViewModels
- `xBill/ViewModels/AuthViewModel.swift` — `@Observable @MainActor`; `currentUser: User?`, `confirmationEmailSent: Bool`, `isInPasswordRecovery: Bool`, `isLoading`, `error`, `pendingJoinRequest: InviteJoinRequest?`; `startListeningToAuthChanges()` handles `.passwordRecovery` event; `handlePasswordReset(newPassword:)` calls `supabase.auth.update`. `InviteJoinRequest` is a top-level `Identifiable` struct with `token: String`
- `xBill/ViewModels/HomeViewModel.swift` — loads groups, computes net balance + `recentExpenses: [RecentEntry]` (top 10 across all groups, members co-fetched); `RecentEntry` is `{ expense, members }` identifiable struct; `archivedGroups: [BillGroup]`; `crossGroupSuggestions: [SettlementSuggestion]` (cross-group debt, filtered to current user); `unarchiveGroup(_:)` unarchives and refreshes both lists; `groupsNavigationPath: NavigationPath`; `createSampleData(userID:)` creates demo group + 3 expenses; `fullBalancesInGroup` returns `GroupBalanceData` (owed, owing, entries, currency, rawBalances, names); `computeBalances` merges per-currency balance maps, calls `minimizeTransactions`, saves to CacheService, calls `WidgetCenter.shared.reloadAllTimelines()`
- `xBill/ViewModels/GroupViewModel.swift` — loads members + expenses, computes balances + settlement suggestions, `recordSettlement()`; `archiveGroup()` / `unarchiveGroup()` set `isArchived` via `GroupService.updateGroup` and update `CacheService` immediately (remove/append to active-groups cache); `createDueRecurringInstances(currentUserID:)` fetches due recurring expenses, creates new instances, clears old `next_occurrence_date`
- `xBill/ViewModels/AddExpenseViewModel.swift` — split calculation; `expenseCurrency` (defaults to group currency); `convertedAmount`/`exchangeRate` computed via `ExchangeRateService.shared`; `updateConversion()` called on currency/amount change; `finalAmount` = converted or raw; `save()` passes `originalAmount`/`originalCurrency` when foreign currency used
- `xBill/ViewModels/ProfileViewModel.swift` — profile editing; `loadStats(userID:)` fetches groups + expenses concurrently via `withTaskGroup` to compute `totalGroupsCount`, `totalExpensesCount`, `lifetimePaid`; `saveProfile(avatarImage:)` uploads avatar via `AuthService.uploadAvatar` then calls `updateProfile`
- `xBill/ViewModels/ActivityViewModel.swift` — `items: [NotificationItem]`; `unreadCount: Int` synced from `NotificationStore`; `markRead(_:)`, `markUnread(_:)`, `delete(_:)`, `markAllRead()`, `refreshUnreadCount()` keep row state and badge count aligned; `hasUnread: Bool` computed
- `xBill/ViewModels/ReceiptViewModel.swift` — receipt scan + review flow; `capturedPages: [UIImage]` (all scanned pages); `capturedImage: UIImage?` computed from `capturedPages.first`; `suggestedCategory: Expense.Category?` set from `ScanResult`; `scan(pages:)` calls `vision.scanMultiPage(from:)` (multi-page aware); `merchantName`, `totalAmount`, `tipAmount: String` mutable vars; `toggleAssignAll(to:)`, `updateUnitPrice`, `hasUnassignedItems`, `total(for:)`; **`startManually(members:)`** — creates blank Receipt, clears scan state + suggestedCategory, sets members

### Widget Extension
- `xBillWidget/xBillWidgetBundle.swift` — `@main WidgetBundle` containing `xBillBalanceWidget`
- `xBillWidget/xBillBalanceWidget.swift` — `StaticConfiguration` widget; `BalanceProvider` reads from shared `UserDefaults` (App Group); `BalanceEntry` has date/netBalance/totalOwed/totalOwing; `BalanceWidgetView` shows owed/owing in a simple layout; `.systemSmall`+`.systemMedium` families; refreshes every 30 minutes
- `xBillWidget/Info.plist` — explicit plist with `NSExtensionPointIdentifier = com.apple.widgetkit-extension` (required for WidgetKit app extensions)
- `xBillWidget/xBillWidget.entitlements` — App Group entitlement `group.com.vijaygoyal.xbill`

### Views — App Lock
- `xBill/Views/AppLockView.swift` — full-screen overlay shown when `AppLockService.shared.isLocked`; brandPrimary background; biometry icon + wordmark + unlock button; `task` auto-triggers authentication on appear; uses `ClayButtonStyle`

### Views — Auth
- `xBill/Views/Auth/AuthView.swift` — adaptive `AppColors.background`; compact `XBillHeroCard` brand header; rounded auth card with Sign In with Apple and `XBillPrimaryButton` email continuation; legal links are split into accessible controls so they do not overflow on small widths; Terms presents `TermsOfServiceView()` sheet and Privacy opens `.safariSheet` to `XBillURLs.privacyPolicy`.
- `xBill/Views/Auth/EmailAuthView.swift` — rounded email/password card with explanatory heading, `XBillTextField` fields, `XBillPrimaryButton` submit with loading/disabled state, create-account/sign-in toggle, and "Forgot password?" sheet with `prefillEmail: vm.email`.
- `xBill/Views/Auth/ForgotPasswordView.swift` — two-step sheet (form → success); calls `AuthService.shared.sendPasswordReset`; inline error display; 30s resend cooldown via `Task`-based sleep loop (no `Timer`); shows success state even for "user not found" errors (account enumeration prevention); `HapticManager.success()/error()` feedback; private `HintRow` and `ResendButtonView` subviews
- `xBill/Views/Auth/ResetPasswordView.swift` — shown when app opened from password reset link; new + confirm password fields; calls `authVM.handlePasswordReset(newPassword:)`

### Views — Legal
- `xBill/Views/Legal/TermsOfServiceView.swift` — in-app ToS screen; native `NavigationStack` + `ScrollView`; header card with `brandPrimary` background; 10 `TOSSection` cards (numbered circle + title + body text); `XBillWordmark` in `.principal` toolbar; "Done" dismiss button; presented as `.sheet` (`.large` detent, drag indicator) from `AuthView` and `ProfileView`; file-private `TOSSection` struct takes `number`, `title`, `content: String` directly

### Views — Onboarding
- `xBill/Views/Onboarding/OnboardingView.swift` — 4-page swipeable onboarding (TabView .page style); shown once after first sign-in via `@AppStorage("hasCompletedOnboarding")` flag in `ContentView`; pages: Welcome, Groups, Receipts, Balances; "Skip" on pages 1–3, "Get Started" on page 4 — both set `hasCompletedOnboarding = true`

### Views — Main
- `xBill/Views/Main/ContentView.swift` — animated transition priority: `ResetPasswordView` → (logged in) `OnboardingView` (first launch only) or `MainTabView` → `AuthView`; `@AppStorage("hasCompletedOnboarding")` controls onboarding gate
- `xBill/Views/Main/NotificationPermissionView.swift` — Pre-prompt sheet (see Services section above)
- `xBill/Views/Main/MainTabView.swift` — 5 tabs: Home / Groups / Friends / Activity / Profile; Friends tab passes `homeVM.currentUser?.id` + `homeVM.groups`; four `.task(id:)` handlers: pendingQuickAction (groups tab + QuickAddExpenseSheet), spotlightTarget (group navigation), pendingNotificationTarget (group navigation), pendingAddFriendUserID (Friends tab + AddFriendView with preloaded user from `FriendService.searchProfiles`); `addFriendPreloadedUser: User?` + `showAddFriendFromQR: Bool` state for QR deep-link sheet
- `xBill/Views/Main/HomeView.swift` — dashboard screen rendered after sign-in; uses `HomeHeader`, calmer `BalanceHeroCard`, reusable `XBillMetricCard` summary cards, `XBillActionCard` invite row, `XBillSectionHeader`, horizontal `GroupChipView` cards, and Recent Expenses/Cross-Group sections. Create-group action is preserved via Invite row and the My Groups section add button; no standalone replacement screen.
- `xBill/Views/Main/ActivityView.swift` — Alerts tab content presented as "Notifications"; uses reusable `XBillScreenHeader`, `XBillScreenContainer`, `XBillScrollView`, `XBillEmptyState`, `XBillSectionHeader`, and `XBillNotificationRow`; sections grouped by date; unread indicator per row; row tap marks that item read and opens `NotificationDetailSheet`; context menu and leading swipe toggle read/unread; context menu and trailing swipe delete; "Mark All Read" header action when `vm.hasUnread`; `onAppear` refreshes badge count without marking all alerts read; preserves amount badges, event icons, notification store integration, and full accessibility labels.

### Views — Groups
- `xBill/Views/Groups/CreateGroupView.swift` — 4×5 emoji grid picker (20 emojis), currency picker (uses `ExchangeRateService.commonCurrencies`), invite email field (wired: sends invite via `GroupService.inviteMembers` after group creation if non-empty, non-fatal error)
- `xBill/Views/Groups/GroupListView.swift` — groups list tab; shares `HomeViewModel`; tokenized Groups header with `XBillCircularIconButton`, `XBillSearchBar`, `XBillSectionHeader`, `XBillGroupCard`, and collapsible `XBillArchivedRow`; active groups section + archived section; archived rows expose context-menu "Unarchive"; navigates to `GroupDetailView` (guarded: only navigates when `vm.currentUser?.id` is non-nil; passes `onGroupStatusChanged` callback that calls `vm.refresh()` + `vm.loadArchivedGroups()`); `onCreated` callback appends new group directly to `vm.groups` and calls `SpotlightService.indexGroups` (no full network refresh); loads archived groups on `.task`
- `xBill/Views/Groups/GroupDetailView.swift` — takes `onGroupStatusChanged: (() async -> Void)?` callback (called after archive or unarchive, triggers `HomeViewModel` refresh before dismiss); segmented Picker (Expenses/Balances/Settle Up) tabs; `AmountBadge` in balances; `AmountBadge(.total)` on expense rows; FAB only on Expenses tab; Settle Up embedded; toolbar menu has: Add Expense, Stats, Export (CSV/PDF via `ExportService`+`ShareSheetView`), Invite via Email, Invite via Link (QR), **Archive Group** (shown only when `!vm.group.isArchived`) or **Unarchive Group** (shown when `vm.group.isArchived`); archive confirmation shows unsettled-balance count if `!vm.settlementSuggestions.isEmpty`; `.task` also calls `vm.createDueRecurringInstances(currentUserID:)`; `.searchable` on Group to add search bar; horizontal `ExpenseFilterChip` strip for category filter on Expenses tab; `filteredExpenses` computed property filters `vm.sortedExpenses` by `searchText` and `filterCategory`
- `xBill/Views/Groups/QuickAddExpenseSheet.swift` — sheet for "Add Expense"/"Scan Receipt" quick actions; shows list of active groups; fetches members on group selection; presents `AddExpenseView` with optional `startWithScan: true`
- `xBill/Views/Groups/GroupInviteView.swift` — shows QR code (CoreImage `CIFilter.qrCodeGenerator`) + `ShareLink` for `xbill://join/<token>`; generates a new invite on appear; refresh button in toolbar
- `xBill/Views/Groups/JoinGroupView.swift` — confirms and handles group join via invite token; fetches group name, shows confirmation card, calls `joinGroupViaInvite` RPC on confirm
- `xBill/Views/Groups/SettleUpView.swift` — settlement suggestions with Venmo link + Mark Settled button
- `xBill/Views/Groups/InviteMembersView.swift` — email invite list; "Import from Contacts" button opens `CNContactPickerViewController` (no upfront permission needed); selected emails added to pending list; `lookupXBillUsers` checks DB via `GroupService.lookupProfilesByEmail`; "On xBill" badge on matching emails; calls `GroupService.inviteMembers` → `invite-member` Edge Function

### Views — Friends
- `xBill/Views/Friends/FriendsView.swift` — Friends tab; accepts `currentUserID` + `allGroups: [BillGroup]` (from `homeVM.groups`); loads accepted friends from `FriendService` + IOUs from `IOUService` in parallel; tokenized `XBillScrollView` layout with `XBillScreenHeader`; sections: Requests (inbound pending, inline accept/decline), Outstanding (friends with unsettled IOUs), All Clear (settled/no-IOU friends); header `person.badge.plus` button → `AddFriendView`; FAB → `AddIOUView`; empty state uses `XBillEmptyState` and one illustration card; contact suggestions use reusable friend rows; `FriendDetailView` receives `allGroups` for mutual-group display
- `xBill/Views/Friends/FriendDetailView.swift` — (defined in FriendsView.swift) outstanding + settled IOU sections; "Settle All" button; "Shared Groups" section showing mutual groups (loaded via `FriendService.fetchMutualGroupIDs` on `.task`); accepts `allGroups: [BillGroup]` default-empty parameter
- `xBill/Views/Friends/AddFriendView.swift` — discovery-only sheet; tokenized `XBillScreenContainer` layout with `XBillDetailHeader`, one friends illustration card, `XBillSearchBar(accessibilityLabel: "Search friends")`, `XBillActionRow` actions for Import from Contacts and Share QR Link (`xbill://add/<currentUserID>`), partial search → debounced 350ms → `FriendService.searchProfiles`, compact no-results state plus app invite `ShareLink`, contact suggestions from `lookupByContactEmails`, and `XBillFriendRow` rows with `XBillPillButton` Add/Pending controls; accepts optional `preloadedUser` for QR deep-link pre-population
- `xBill/Views/Friends/AddIOUView.swift` — now shows friend picker from `FriendService.fetchFriends()` as primary selection; "Add by email" is secondary fallback; keeps email search for non-friends; `preselectedFriend` and `preselectedFriendID` params unchanged
- `xBill/Views/Expenses/AddExpenseView.swift` — `bgSecondary` sheet; hero amount `TextField`; currency picker `Menu` next to currency symbol; conversion preview when foreign currency; "Repeat" section with `Expense.Recurrence` picker (Does not repeat / Weekly / Monthly / Yearly); `ExchangeRateService.commonCurrencies` populates the currency picker
- `xBill/Views/Expenses/ExpenseDetailView.swift` — expense detail with split breakdown + Comments section (realtime); `currentUserID: UUID` required; comment input bar via `safeAreaInset(edge: .bottom)`
- `xBill/Views/Expenses/ReceiptScanView.swift` — accepts `members: [User]` + `onConfirmed: ([SplitInput]) -> Void`; `DocumentCameraView` now binds to `$vm.capturedPages: [UIImage]` and captures ALL pages (`0..<scan.pageCount`) for multi-page receipt support; photo library sets `vm.capturedPages = [image]`; `onChange(of: vm.capturedPages)` triggers `vm.scan(pages:)`; "Scan Again" clears `vm.capturedPages`; multi-page badge shown when `capturedPages.count > 1`; quality errors (Gap 2) surface via existing `.errorAlert(item:)` binding
- `xBill/Views/Expenses/ReceiptReviewView.swift` — item review, member chip assignment, per-person totals; confidence header now includes suggested category chip (Gap 5) from `vm.suggestedCategory`; Extras section shows "Receipt Date" row (Gap 4) from `vm.scannedReceipt?.transactionDate` formatted with `.date` style; merchant name editable via `XBillTextField`; tip and total editable; tax read-only; "Use These Splits" calls `onConfirmed`; file-private `ItemRow` with inline price + stepper + member chips

### Views — Profile
- `xBill/Views/Profile/ProfileView.swift` — Profile tab; tokenized `XBillScreenContainer` layout with `XBillScreenHeader`, enhanced `XBillProfileCard`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, and `XBillSettingsRow`; preserves `showMyQR` sheet presenting `MyQRCodeView`, edit profile sheet/avatar picker, payment handle text fields, notification toggles, app lock toggle, sign out, delete account, ToS/Privacy links, refresh, and profile stats.
- `xBill/Views/Profile/MyQRCodeView.swift` — displays QR code for `xbill://add/<userID>` deep link using `CIFilter.qrCodeGenerator` (same pattern as `GroupInviteView`); `ShareLink` for the URL; `.interpolation(.none)` on the QR image to prevent blurring

### Views — Components
- **Migration note:** these components are the current reusable surface, but the redesign target is `xBill/DesignSystem/Components`. When touching these files for redesign work, either move the component, create a canonical wrapper, or document a temporary compatibility alias.
- `xBill/Views/Components/AvatarView.swift` — circular avatar; remote images via `AsyncImage`; fallback delegates to `XBillAvatarPlaceholder` for tokenized gradient avatar visuals.
- `xBill/Views/Components/BalanceBadge.swift` — green (owed to you) / red (you owe) badge (legacy; prefer `AmountBadge` for new screens)
- `xBill/Views/Components/AmountBadge.swift` — colored pill badge with `AmountDirection` (.positive/.negative/.settled/.total); uses design system money tokens
- `xBill/Views/Components/BalanceHeroCard.swift` — tokenized gradient hero card for balance display at top of screens; includes `XBillWalletIllustration`; `.xbillHeroAmount` monospaced number
- `xBill/Views/Components/XBillCard.swift` — generic card wrapper; delegates to `SharpCard` modifier (18pt corners, hairline border, drop shadow)
- `xBill/Views/Components/XBillButton.swift` — design-system button with `.primary/.secondary/.ghost/.destructive` styles; fires `HapticManager.impact` on tap
- `xBill/Views/Components/XBillTextField.swift` — `inputBg`/`inputBorder` styled text field; focus-animated border turns `brandPrimary`
- `xBill/Views/Components/CategoryIconView.swift` — compatibility wrapper around `XBillCategoryIcon`; `Expense.Category` still exposes `.emoji` and `.categoryBackground` for legacy labels.
- `xBill/Views/Components/OfflineBanner.swift` — orange banner shown via `safeAreaInset(edge:.top)` in HomeView and GroupDetailView when `NetworkMonitor.shared.isConnected == false`
- `xBill/Views/Components/ContactPickerView.swift` — `ContactPickerRepresentable: UIViewControllerRepresentable` wrapping `CNContactPickerViewController`; shared component used by both `InviteMembersView` and `AddFriendView`; `onPickedEmails: ([String]) -> Void` callback; handles both single and multi-contact selection
- `xBill/Views/Components/FABButton.swift` — 56pt `brandPrimary` circle FAB with shadow and haptic
- `xBill/Views/Components/GroupChipView.swift` — Home dashboard group card for horizontal group scroll; shows avatar placeholder, currency chip, active/archived status, and created date with tokenized surfaces/borders.
- `xBill/Views/Components/ExpenseRowView.swift` — expense list row; `showAmountBadge: Bool = false` — when true shows `AmountBadge(.total)` instead of plain amount text
- `xBill/Views/Components/EmptyStateView.swift` — wraps `ContentUnavailableView` (iOS 17+); `(icon:title:message:actionLabel?:action?)` API unchanged; action button uses `.borderedProminent` style; two variants compiled at runtime: with/without action
- `xBill/Views/Components/LoadingOverlay.swift` — centered spinner with message
- `xBill/Views/Components/SplitSlider.swift` — percentage split slider
- `xBill/Views/Components/SafariView.swift` — `UIViewControllerRepresentable` wrapping `SFSafariViewController`; branded with `UIColor(Color.brandPrimary)` bar tint + white controls; `View.safariSheet(isPresented:url:)` extension for presenting in-app; used for privacy policy links — do NOT use `openURL` env action for policy links
- `xBill/Views/Components/ShareSheetView.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController`; accepts a `URL` to share; used by `GroupDetailView` for CSV/PDF export

### Tests
- `xBillTests/SplitCalculatorTests.swift` — 17 tests: equal split (even/rounding/excluded/single), percentage (proportional/rounding), exact validation (pass/fail), net balances, single payer, circular debt, partially settled, two people, floating point precision (÷3), minimize transactions (basic/all-settled). Fixed 2026-04-29: added `recurrence: .none` to all `Expense` inits; removed stale `updatedAt:` arg; fixed `\.amount` key-path inference in `#expect`.
- `xBillTests/P2FeatureTests.swift` — 18 tests across 5 suites: CrossGroupDebt (balance merging, currency separation, minimisation), AppLock (lock/no-op state transitions, MainActor), ManualReceipt (startManually creates blank receipt, assigns members, clears previous scan), CacheServiceBalance (.serialized, round-trip and zero-default), ContactDiscovery (email validation, dedup, lowercasing).
- `xBillTests/P1NotificationTests.swift` — 17 tests across 4 suites: NotificationStore (.serialized, merge dedup, read-state preservation, sort order, unread count, markAllRead, markRead/markUnread, delete, 100-item cap), NotificationItemFactory (expense + settlement factory field mapping), ActivityViewModelUnread (hasUnread flag, markAllRead zeros VM, per-item read/delete VM state), NotificationItemCodable (expense + settlement JSON round-trip).
- `xBillTests/GroupFlowTests.swift` — 27 tests across 6 suites: GroupFlowCachePattern (archive/unarchive array-manipulation logic, idempotency), BillGroupModel (Codable roundtrip, snake_case CodingKeys, Equatable, value-type semantics), GroupCreationLogic (onCreated append, canCreate guard, invite email trim), GroupArchiveLogic (balance-warning conditions, plural/singular, toolbar action context), CurrencyList (count=20, original 8 + 12 new, no duplicates), RealtimeContract (topic scoping). All tests are parallel-safe (no shared UserDefaults state).
- `xBillUITests/OnboardingUITests.swift` — 6 focused login/onboarding XCUITests for the redesigned pre-auth entry screen, SwiftUI illustration identifiers, canonical `XBillPageHeader` title identifiers, accessible legal links, email sign-up form content, sign-in validation, sign-in/sign-up toggling, and forgot-password visibility. Launches with `--uitesting --reset-state`; DEBUG app launch handling clears UserDefaults and Keychain session data so each test starts unauthenticated.
- `xBillUITests/GroupFlowUITests.swift` — 14 XCUITests for group creation (form validation, Create button enable/disable, cancel, new group appears in list immediately), archive flow (toolbar menu, confirmation dialog, group moves to archived section on confirm), and unarchive flow (archived section expand/collapse, swipe-right Unarchive action, Unarchive from detail-view toolbar). All tests skip gracefully with `XCTSkip` when not signed in or when prerequisite data (groups, archived groups) is absent.

## Key Patterns

### State Management
- `@Observable @MainActor final class SomeViewModel` for all VMs
- `@Bindable var vm: SomeViewModel` in views needing two-way binding
- `@State private var vm = SomeViewModel(...)` for locally owned VMs
- One `AuthViewModel` created at app root (`xBillApp`), passed down — never create a second instance

### Auth Flow
1. `xBillApp` creates `AuthViewModel`, starts `loadCurrentUser()` + `startListeningToAuthChanges()`
2. `ContentView` priority: `ResetPasswordView` (if `isInPasswordRecovery`) → `MainTabView` (if `currentUser != nil`) → `AuthView`
3. Sign-up with email → Supabase sends confirmation email → `response.session` is nil → `confirmationEmailSent = true` → show banner
4. DB trigger `handle_new_user()` auto-creates `profiles` row (SECURITY DEFINER, bypasses RLS)
5. Auth state listener: guards `session?.user.emailConfirmedAt != nil` before calling `loadCurrentUser()`; `.passwordRecovery` event sets `isInPasswordRecovery = true`
6. Password reset: user taps email link → `xbill://auth/callback` opens app → `.onOpenURL` calls `supabase.auth.session(from:)` → listener fires `.passwordRecovery` → `ResetPasswordView` shown
7. Sign-out: `AuthService.signOut()` → Supabase `.signedOut` event → listener clears `currentUser` + `isInPasswordRecovery` → `ContentView` transitions back to `AuthView`

### UI Test Auth State
- UI tests should launch with `--uitesting --reset-state` when they need an unauthenticated app. In DEBUG builds, `xBillApp.AppDelegate` responds by clearing the app's UserDefaults domain and deleting xBill Keychain generic-password entries through `KeychainManager.deleteAllForUITesting()`.
- Current focused login validation command:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -only-testing:xBillUITests/OnboardingUITests
  ```
- Verified 2026-05-04: `OnboardingUITests` executed 6 tests with 0 failures on simulator `DA97985A-F7CC-44F6-8281-9DD24C22B978`, including assertions for the onboarding split-bill illustration, sign-in wallet illustration, and canonical auth page header identifiers.

### Auth Configuration Troubleshooting
- If email/password or Apple sign-in reports "A server with the specified hostname could not be found," first inspect the compiled app Info.plist, not the source plist:
  ```
  plutil -extract SUPABASE_URL raw ~/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Build/Products/Debug-iphonesimulator/xBill.app/Info.plist
  plutil -extract SUPABASE_ANON_KEY raw ~/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Build/Products/Debug-iphonesimulator/xBill.app/Info.plist | wc -c
  ```
- Expected result: the URL is the full Supabase hostname and the anon key length is non-zero. If the URL prints only `https:`, fix `Secrets.xcconfig` to use `https:/$()/...`, regenerate with `xcodegen generate`, rebuild, reinstall, and relaunch.
- Keep `Secrets.xcconfig.example` synchronized with the escaping rule whenever credential setup docs change.

### Deep Link URL Scheme
- Scheme: `xbill://`; registered in `Info.plist` under `CFBundleURLTypes`
- All Supabase auth links (confirmation, password reset) redirect to `xbill://auth/callback`
- Group invite links: `xbill://join/<token>` — parsed in `xBillApp.onOpenURL`; sets `authVM.pendingJoinRequest`; `MainTabView` shows `JoinGroupView` sheet via `sheet(item: $authVM.pendingJoinRequest)`
- Add-friend links: `xbill://add/<userID>` — parsed in `xBillApp.onOpenURL`; sets `AppState.shared.pendingAddFriendUserID`; `MainTabView` resolves user via `FriendService.searchProfiles`, switches to Friends tab, shows `AddFriendView` with `preloadedUser`; QR code generated in `MyQRCodeView` (ProfileView)
- Set in Supabase dashboard: **Authentication → URL Configuration → Site URL + Redirect URLs**

### Sign In with Apple
- Raw nonce generated with `CryptoKit`, SHA256 hash sent to Apple, raw nonce sent to Supabase
- Entitlement: `com.apple.developer.applesignin: [Default]` in `xBill.entitlements`

**Supabase Apple provider — required dashboard setup (one-time):**
1. Apple Developer Portal → Certificates, IDs & Profiles → Keys → create a new key with "Sign in with Apple" enabled → download `.p8` file (note Key ID)
2. Apple Developer Portal → Identifiers → App ID `com.vijaygoyal.xbill` → ensure "Sign in with Apple" capability is enabled
3. Supabase dashboard → Authentication → Providers → Apple → enable and fill in:
   - **Services ID** (client_id): `com.vijaygoyal.xbill` (use the App ID for native flows)
   - **Team ID**: your 10-char Apple Team ID (e.g. `ABCDE12345`)
   - **Key ID**: from the `.p8` key you generated
   - **Private key**: paste full contents of the `.p8` file
4. Save and verify in Supabase Auth → Providers that Apple shows "Enabled"

**Known bugs (all fixed 2026-04-28/30):**
- ~~`AuthViewModel.swift:58` — `emailConfirmedAt` guard blocks Apple users on cold relaunch.~~ ✅ Fixed 2026-04-28
- ~~`xBill.entitlements` — `aps-environment: production` conflicts with debug provisioning.~~ ✅ Fixed 2026-04-28
- ~~**Thin profile for Apple users** — `fullName` from Apple credential was discarded; DB trigger created profile with `display_name = "User"` or relay-email local part.~~ ✅ Fixed 2026-04-30 — `AuthView` extracts `credential.fullName`, passes to `AuthViewModel.signInWithApple(displayName:)`, `AuthService` upserts into `profiles` before `fetchProfile`. `DisplayNamePayload` private struct added to `AuthService.swift`. Subsequent sign-ins send `nil` displayName so existing name is never overwritten.

### Supabase Insert/Update — Always Chain .select()
In Supabase Swift SDK v2, `.insert()` / `.update()` without `.select()` sends `Prefer: return=minimal` → empty response body → decoding to a model fails. Always chain `.select()` before `.single()`. This applies to ALL update calls — `AuthService.updateProfile` and `ExpenseService.updateExpense` both have this correctly:
```swift
let group: BillGroup = try await supabase.table("groups")
    .insert(payload)
    .select()   // ← required to get the row back
    .single()
    .execute()
    .value
```

### Supabase Join Queries
```swift
// Fetching groups a user belongs to — group is optional so compactMap filters nulls:
struct Row: Decodable { let group: BillGroup? }
let rows: [Row] = try await supabase.table("group_members")
    .select("group:groups(*)")
    .eq("user_id", value: userID)
    .execute().value
return rows.compactMap(\.group)
```

### Realtime Subscriptions
- `GroupService.groupChanges(userID:)` → creates Supabase Realtime channel → returns `AsyncStream<Void>`
- `HomeViewModel.startRealtimeUpdates()` iterates stream, calls `loadAll()` on each yield

### Naming — BillGroup vs Group
- The model is `BillGroup` (not `Group`) to avoid collision with `SwiftUI.Group`
- All previews and call sites use `BillGroup(...)`

### Liquid Glass (iOS 26+)
Three modifiers in `Extensions.swift` wrap the `#available(iOS 26, *)` check:
- `.liquidGlass(in: some Shape)` — non-interactive glass; falls back to `.regularMaterial`
- `.liquidGlass(fallback: some ShapeStyle, in: some Shape)` — non-interactive glass; falls back to the provided style (use when `.regularMaterial` would be wrong, e.g. tinted circles)
- `.liquidGlassButton(fallback: some ShapeStyle, in: some Shape)` — interactive glass; falls back to the tinted flat fill

Tab bar, navigation bars, and sheets get Liquid Glass automatically on iOS 26 — no manual work needed.

Applied surfaces:
- **FAB** (`HomeView`) — glass circle; accent fill on iOS 17. `fabForeground` computed property adapts icon color.
- **Group emoji circles** (`GroupRowView`) — `.liquidGlass(in: .circle)`; falls back to `.regularMaterial`
- **Avatar initials circle** (`AvatarView`) — `.liquidGlass(fallback: Color.accentColor.opacity(0.2), in: Circle())`
- **Emoji picker cells** (`CreateGroupView`) — `.liquidGlass(fallback: selected ? accentColor.opacity(0.18) : systemGray6, in: RoundedRectangle)`; accent border retained for selected cell on both OS versions
- **BalanceBadge** — glass capsule with colored text on iOS 26; colored fill with white text on iOS 17. `badgeForeground` computed property handles the difference.
- **EmptyStateView action button** — `.liquidGlassButton(fallback: Color.accentColor, in: Capsule())`; `emptyButtonForeground` adapts text color.
- **Venmo + Mark Settled buttons** (`SettleUpView`) — `.liquidGlassButton(fallback:in: .capsule)`

### Accessibility
- All font tokens use Dynamic Type text styles (`.largeTitle`, `.title`, `.subheadline`, etc.) — do NOT use fixed `size:` integers, which break Dynamic Type scaling
- Key display components expose `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)` so VoiceOver reads a single coherent description:
  - `BalanceHeroCard` — "\(label): \(amount), \(subtitle)"
  - `GroupChipView` — "\(group.name) group, \(group.currency)"
  - `ExpenseRowView` — "\(title), paid by \(name), \(amount)"
  - `AmountBadge` — "owed to you / you owe / settled / total: \(amount)"
- Use `.accessibilityHidden(true)` only on purely decorative icons. Major auth/empty-state illustrations are visible content and should expose stable accessibility labels/identifiers for UI tests.

### Error Display
- `errorAlert` modifier shows `error.errorDescription` as the alert title (not a generic string) — useful for debugging
- `error = nil` is only cleared on success, not at the start of an action (prevents alert dismissal)

### RLS Chicken-and-Egg for Group Creation
- Creator can't satisfy `is_group_member(group_id)` for a brand-new group
- Policy (migration 006) adds OR clause: `auth.uid() = user_id AND group.created_by = auth.uid()`

## Error Handling Pattern

All ViewModels use `var errorAlert: ErrorAlert?` (defined in `AppError.swift`) instead of `var error: AppError?`. The `ErrorAlert` struct is `Identifiable` so alerts persist until user dismisses — they are NOT cleared at the start of async operations. Views bind with `.errorAlert(item: $vm.errorAlert)` (defined in `Extensions.swift`). The old `errorAlert(error: Binding<AppError?>)` modifier is kept for local `@State` vars in non-ViewModel views (JoinGroupView, CreateGroupView, etc.).

## Delete Account

`AuthService.deleteAccount()` reads the session JWT and calls the `delete-account` Edge Function with `Authorization: Bearer <token>`, then signs out locally. `ProfileViewModel.deleteAccount()` delegates entirely to `auth.deleteAccount()` and only manages `isLoading`/`errorAlert` state.

**Edge Function deletion order** (device_tokens → profiles → auth user): device_tokens and profile failures are logged but non-fatal; auth user deletion is fatal (returns 500 on failure). **Never pass `user_id` in the request body** — identity is derived from the verified JWT via `adminClient.auth.getUser(jwt)`, then service role is used only for privileged deletion.

**`device_tokens` table** (`016_create_device_tokens_table.sql`): standalone table with `user_id uuid → auth.users(id) on delete cascade`, RLS enabled, single "Users manage own tokens" policy. Migration `010` only added a column to `profiles` — `016` creates the actual table.

**FK constraints** (`017_fix_user_delete_constraints.sql`): `groups.created_by` and `expenses.paid_by` were `ON DELETE RESTRICT` which blocked auth user deletion. Changed to `ON DELETE SET NULL` with nullable columns so groups and expenses persist after the creator/payer is deleted.

Deploy: `supabase db push && supabase functions deploy delete-account --project-ref <ref>`. Secrets required: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (auto-injected; add manually via `supabase secrets set` if missing).

## P1 Features (implemented 2026-04-30)

### In-App Notification Center
- **`NotificationItem`** (`Models/NotificationItem.swift`) — `Codable, Sendable` model replacing `ActivityItem`; `NotificationEventType` enum: `.expenseAdded` and `.settlementMade`; static factories `NotificationItem.expense(...)` and `NotificationItem.settlement(...)`
- **`NotificationStore`** (`Services/NotificationStore.swift`) — local-first persistence via App Group UserDefaults; `merge(_:)` deduplicates by id, caps at 100 items, and preserves existing read state; per-item `markRead(id:)`, `markUnread(id:)`, and `delete(id:)`; `markAllRead()` marks every stored item read and updates `lastViewedAt()` for backward compatibility; `unreadCount()` = unread stored items; `clearAll()` for test teardown
- **`ActivityService`** — now returns `[NotificationItem]`; merges DB-fetched expense items into store on each fetch (preserving read state for existing items)
- **`ActivityViewModel`** — `unreadCount: Int`, per-item `markRead(_:)`, `markUnread(_:)`, `delete(_:)`, `markAllRead()`, `refreshUnreadCount()`, and `hasUnread: Bool` computed
- **`ActivityView`** — title changed to "Notifications", `bell.fill` tab icon; unread blue dot per row; row tap opens alert details and marks that item read; context-menu and swipe actions support read/unread and delete; "Mark All Read" toolbar button; opening the tab does not clear unread count automatically
- **`MainTabView`** — `.badge(activityVM.unreadCount > 0 ? activityVM.unreadCount : 0)` on Activity tab; activity data refreshes at launch and when the app becomes active so badge count does not remain static
- **`GroupViewModel.recordSettlement()`** — writes `NotificationItem.settlement(...)` to `NotificationStore` after each successful settle-up
- **Settlement events** are write-side local notifications — generated when the current user records a settlement; persist across app restarts

## P2 Features (implemented 2026-04-29)

### Cross-Group Debt Simplification
- `HomeViewModel` now accumulates raw `[UUID: Decimal]` balance maps from all groups via `fullBalancesInGroup(_:userID:)` (returning `GroupBalanceData` struct)
- Merges per-currency balance maps and calls `SplitCalculator.minimizeTransactions` on each
- Filters results to only the current user (`crossGroupSuggestions: [SettlementSuggestion]`)
- `HomeView` shows "SIMPLIFY DEBTS" section when `crossGroupSuggestions` is non-empty

### Face ID / Passcode Lock
- `xBill/Services/AppLockService.swift` — `@Observable @MainActor` singleton; `isEnabled` (UserDefaults), `isLocked`, `authenticate()` via `LAContext.deviceOwnerAuthentication`, `lock()`
- `xBill/Views/AppLockView.swift` — full-screen lock overlay; shows biometry icon + "Unlock" button; auto-triggers Face ID on appear
- `ContentView` — `@State private var lockService = AppLockService.shared`; overlays `AppLockView` inside the `authVM.currentUser != nil` branch; `onChange(of: scenePhase)` calls `lockService.lock()` on `.background`
- `ProfileView` — "SECURITY" section with Toggle for Face ID/Passcode
- `Info.plist` — added `NSFaceIDUsageDescription`

### Manual Line-Item Receipt Entry
- `ReceiptViewModel.startManually(members:)` — creates a blank Receipt, clears items/scan state, assigns members
- `ReceiptScanView` — "Enter Manually" button (pencil icon) in the no-image state; sets `showReview = true` after calling `startManually(members:)`

### Onboarding Sample Data
- `HomeViewModel.createSampleData(userID:)` — creates "Sample Trip 🏖️" group + 3 sample expenses (Airfare $240, Hotel $180, Dinner $65) paid by the current user; appends to groups and updates cache
- `OnboardingView` — `onTrySampleData: (() async -> Void)? = nil` parameter; last page shows "Try with sample data" secondary button when callback is set; `isCreatingSample` state shows ProgressView
- `ContentView` — passes `onTrySampleData` closure that calls `HomeViewModel().createSampleData(userID:)` with the current user's ID

### Contact Discovery
- `InviteMembersView` — `CNContactPickerViewController` wrapped as `ContactPickerRepresentable`; "Import from Contacts" button opens picker; selected contacts' emails are added to pending list and looked up in the DB; "On xBill" badge on matching emails
- `GroupService.lookupProfilesByEmail([String]) async throws -> [User]` — calls `lookup_profiles_by_email` RPC
- `supabase/migrations/018_lookup_profiles_by_email.sql` — `SECURITY DEFINER` RPC; excludes current user from results; granted only to `authenticated` role
- `Info.plist` — added `NSContactsUsageDescription`

### WidgetKit Balance Widget
- `xBillWidget/xBillBalanceWidget.swift` — `StaticConfiguration` widget; `BalanceProvider` reads net/owed/owing from shared UserDefaults; refreshes every 30 min; `.systemSmall` + `.systemMedium` families
- `xBillWidget/xBillWidgetBundle.swift` — `@main WidgetBundle`
- `xBillWidget/Info.plist` — explicit plist with `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`
- `xBillWidget/xBillWidget.entitlements` — App Group `group.com.vijaygoyal.xbill`
- `project.yml` — `xBillWidget` target added (`app-extension`); embedded in xBill app; added to build scheme
- `CacheService` — now uses `UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard`; `nonisolated(unsafe)` for Swift 6 Sendable; `saveBalance(netBalance:totalOwed:totalOwing:)` + load helpers for widget consumption
- Both entitlements files — `com.apple.security.application-groups: [group.com.vijaygoyal.xbill]`
- `HomeViewModel` — calls `WidgetCenter.shared.reloadAllTimelines()` after computing balances
- **⚠️ REQUIRES**: Register App Group `group.com.vijaygoyal.xbill` in Apple Developer Portal → Identifiers before the widget can share data with the main app

## Known TODOs
- **App Group registration** (for widget data sharing): register `group.com.vijaygoyal.xbill` in Apple Developer Portal → Certificates, IDs & Profiles → Identifiers → App Groups
- Deploy `invite-member` Edge Function: `supabase functions deploy invite-member` (after setting secrets `RESEND_API_KEY` + `INVITE_FROM_EMAIL`)
- Deploy `notify-friend-request` Edge Function: `supabase functions deploy notify-friend-request`
- App Store Assets: screenshots, preview video, keyword strategy (only remaining P0 blocker)

## App Store Compliance
- `PrivacyInfo.xcprivacy` added to both `xBill/` and `xBillWidget/` targets (required since May 2024). Declares: `NSPrivacyTracking: false`, collected data types (email, name, financial info, photos/videos, contacts, device ID), `UserDefaults` required-reason `CA92.1`. **Contacts added 2026-05-02** (automated scanner blocker).
- `ITSAppUsesNonExemptEncryption: false` added to `Info.plist` (app uses only standard OS TLS — no custom crypto).
- `delete-account` Edge Function: **ACTIVE (v6)** — deployed 2026-04-16. Not a pending TODO.

## Security — Additional Fixes (2026-05-02)

### C1 — Supabase credentials moved out of project.yml ✅
- Created `Secrets.xcconfig` (gitignored) — holds `SUPABASE_URL` + `SUPABASE_ANON_KEY`.
- Created `Secrets.xcconfig.example` (committed) — template with placeholder values.
- Created `.gitignore` — excludes `Secrets.xcconfig` from git.
- Updated `project.yml`: removed credentials from `settings.base`; added `settings.configFiles` pointing to `Secrets.xcconfig` for both debug and release configurations.
- Info.plist continues to reference `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` build settings — no Swift changes needed.

### H1 — JWT auth guard on 4 notification Edge Functions ✅
- All four functions (`notify-expense`, `notify-settlement`, `notify-comment`, `notify-friend-request`) now call `requireAuth(req)` before processing. `requireAuth` extracts `Authorization: Bearer <jwt>`, calls `adminClient.auth.getUser(jwt)`, returns 401 on failure. No iOS client changes needed — `supabase.functions.invoke()` automatically sends the user JWT when authenticated.

### H4 — JWT auth guard on invite-member Edge Function ✅
- `invite-member/index.ts` now calls `requireAuth(req)` at the top of the handler, returning 401 for unauthenticated requests. Prevents unauthenticated email spam via xBill's Resend account.

### M1 — search_profiles no longer returns email column ✅
- **`supabase/migrations/021_fix_search_profiles_no_email.sql`** — `CREATE OR REPLACE FUNCTION search_profiles` removes `email` from RETURNS TABLE and SELECT list. Email is still used in the `WHERE` clause so searching by email address still works; the address is just never sent back.
- **`xBill/Services/FriendService.swift`** — `searchProfiles` `Row` struct drops the `email` field; User constructed with `email: ""` (display-only, never shown from search results).

### M4 — CORS wildcard replaced on all Edge Functions ✅
- All 5 Edge Functions: `corsHeaders['Access-Control-Allow-Origin']` changed from `'*'` to `SUPABASE_URL` (the project's own domain). Mobile app calls are unaffected (iOS does not send Origin headers).

### L1 — appLockEnabled moved from UserDefaults to Keychain ✅
- **`xBill/Services/AppLockService.swift`** — `isEnabled` getter/setter now reads/writes `KeychainManager.Keys.appLockEnabled` via `KeychainManager.shared`. Key uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — backup-excluded, device-bound.
- **Migration path**: `migrateFromUserDefaultsIfNeeded()` (called from `init()`) reads the old `appLockEnabled` UserDefaults key, writes it to Keychain, then removes the UserDefaults key. Silent no-op on fresh installs.
- **`xBill/Core/KeychainManager.swift`** — Added `Keys.appLockEnabled = "app_lock_enabled"`.
- **`xBillTests/SecurityFixTests.swift`** (new) — 14 new tests: `AppLockKeychainTests` (5, `.serialized`), `SearchProfilesEmailTests` (3), `KeychainManagerBoolTests` (4). All pass.

## Security — Hard Blockers Fixed (2026-05-02)

### M5 — Privacy manifest Contacts gap ✅
- Added `NSPrivacyCollectedDataTypeContacts` to `xBill/PrivacyInfo.xcprivacy`. App uses `CNContactPickerViewController`; omission would cause automated scanner rejection at upload time.

### M3 — App Lock silent bypass ✅
- **`xBill/Services/AppLockService.swift`** — `authenticate()` now sets `isEnabled = false` (in addition to `isLocked = false`) when `canEvaluatePolicy` fails. Devices with no passcode auto-disable App Lock rather than appearing protected while unlocking silently.

### M2 — Spotlight exposes financial data ✅
- **`xBill/Services/SpotlightService.swift`** — Removed `indexExpenses` and `removeExpense`; replaced with `removeAllExpenses()` (deletes by domain). Expense titles contain amounts and categories visible from lock screen.
- **`xBill/ViewModels/GroupViewModel.swift`** — Removed `SpotlightService.indexExpenses(...)` call.
- **`xBill/xBillApp.swift`** — One-time startup migration: calls `SpotlightService.removeAllExpenses()` guarded by `spotlightExpensesCleared_v1` UserDefaults flag.

### H2 — Session tokens in device-only Keychain ✅
- **`xBill/Core/KeychainSessionStorage.swift`** (new) — Implements `AuthLocalStorage` using `KeychainManager`. `KeychainManager.save` now sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — sessions are never in backups and cannot be migrated to another device.
- **`xBill/Core/SupabaseClient.swift`** — `SupabaseClientOptions.AuthOptions(storage: KeychainSessionStorage(), ...)`. Replaces SDK default which used `kSecAttrAccessibleAfterFirstUnlock` (backup-eligible).

### H3 — Financial data encrypted in App Group UserDefaults ✅
- **`xBill/Core/KeychainManager.swift`** — Added `cacheEncryptionKey()`: generates/persists a `SymmetricKey(size: .bits256)` in Keychain with `ThisDeviceOnly` access.
- **`xBill/Services/CacheService.swift`** — Added `static encrypt/decrypt` (AES-GCM via CryptoKit). Private `save<T>` and `load<T>` helpers now encrypt before write and decrypt after read. Balance keys (`xbill_net_balance/owed/owing`) intentionally left unencrypted — widget-readable summary data.
- **`xBill/Services/NotificationStore.swift`** — `loadAll` and `merge` updated to call `CacheService.decrypt/encrypt`. Smooth migration: `decrypt` falls back to raw data if stored value was written unencrypted (first launch after update).
- **All 74 existing tests pass** after these changes.

## Security — Low Findings Fixed (2026-05-02)

### C2 — Apple developer credentials removed from generate_apple_secret.js ✅
- `generate_apple_secret.js` — `TEAM_ID`, `KEY_ID`, `CLIENT_ID`, `KEY_FILE` replaced with placeholder strings; the existing guard at line 16 will reject placeholders and prompt the user to fill them in before running.

### L2 — PayPal username alphanumeric validation ✅
- **`xBill/Services/PaymentLinkService.swift`** — `paypalLink(to:amount:currency:)` now guards with a regex `^[a-zA-Z0-9._-]+$` before building the URL; returns `nil` for usernames containing spaces, `@`, `%`, path characters, or empty strings.
- **`xBillTests/SecurityFixTests.swift`** — 7 new tests in `L2 — PayPal username validation` suite covering valid/invalid username cases.

### L3 — Deno std pinned version upgraded ✅
- All 5 Edge Functions (`notify-expense`, `notify-settlement`, `notify-comment`, `notify-friend-request`, `invite-member`) updated from `std@0.168.0` to `std@0.224.0`.

### L4 — GCC_GENERATE_DEBUGGING_SYMBOLS made per-config ✅
- **`project.yml`** — Removed `GCC_GENERATE_DEBUGGING_SYMBOLS: YES` from global `settings.base`. Added explicit `GCC_GENERATE_DEBUGGING_SYMBOLS: YES` to the `debug` config and `GCC_GENERATE_DEBUGGING_SYMBOLS: NO` to the `release` config. Any future config added requires an explicit opt-in.

### L5 — APNs userInfo trimmed to routing-only IDs ✅
- **`notify-expense/index.ts`** — Removed `expenseId` from the APNs payload `userInfo`; `groupId` retained for notification-tap navigation.
- **`notify-settlement/index.ts`** — Removed `settlementId` from the APNs payload `userInfo`; `groupId` retained.
- **`notify-comment/index.ts`** — Removed `expenseId` from the APNs payload `userInfo`; `groupId` retained.
- **`notify-friend-request/index.ts`** — `fromUserID` retained (needed to preload `AddFriendView` on notification tap); no other IDs removed.

## Expense Model Notes
- `Expense.payerID` CodingKey maps to `"paid_by"` (DB column name, not `"payer_id"`)
- `Expense` does NOT have an `updatedAt` field — DB column does not exist; do not add it to previews or tests
- `ExpenseService.createExpense` uses `add_expense_with_splits` RPC (atomic); splits are encoded as `[RPCSplitParam]` with CodingKeys `p_*` prefix

## Group Flow — Fixed Issues (audited 2026-04-28, all fixed same day)

### Group Creation (all fixed)
- **Dead invite-email UI** — Fixed: `create()` now calls `GroupService.inviteMembers` after group creation if the field is non-empty. Invite errors are non-fatal (`try?`) so they don't block group creation.
- **`onCreated` ignores the returned group** — Fixed: `GroupListView` now appends `newGroup` to `vm.groups` directly and calls `SpotlightService.indexGroups` — no extra network round-trip.
- **Currency picker hard-coded subset** — Fixed: `CreateGroupView.currencies` now uses `ExchangeRateService.commonCurrencies` (20 currencies).
- **`currentUserID` placeholder** — Fixed: `GroupListView.navigationDestination` now guards `if let userID = vm.currentUser?.id` and only renders `GroupDetailView` when the user is confirmed loaded.

### Archive Flow (all fixed)
- **Stale active list + archived list after archiving (P0)** — Fixed: `GroupDetailView` takes `onGroupStatusChanged: (() async -> Void)?`. After a successful archive or unarchive, the callback is awaited before `dismiss()`, triggering `vm.refresh()` + `vm.loadArchivedGroups()` in `HomeViewModel`.
- **"Archive Group" shown for already-archived groups** — Fixed: Toolbar now checks `vm.group.isArchived` and shows "Unarchive Group" / "Archive Group" accordingly.
- **No unsettled-balance warning before archiving** — Fixed: Archive confirmation dialog message now includes unsettled-balance count when `!vm.settlementSuggestions.isEmpty`.
- **Cache not invalidated on archive** — Fixed: `GroupViewModel.archiveGroup()` removes the group from `CacheService` after a successful DB update; `unarchiveGroup()` appends it back.

### De-Archive Flow (all fixed)
- **`GroupViewModel.unarchiveGroup()` was dead code** — Fixed: Wired to "Unarchive Group" button in `GroupDetailView` toolbar (shown only when `vm.group.isArchived`), with its own confirmation dialog. `onGroupStatusChanged` callback triggers `HomeViewModel` refresh on success.
- **Realtime misses archive-only changes** — Fixed: `GroupService.groupChanges` now subscribes to both `group_members` and `groups` tables on the same channel using two concurrent `Task` loops. Either table change triggers a yield to the caller.

### Service Layer (fixed)
- **Client-side archived filter** — Fixed: `fetchGroups` and `fetchArchivedGroups` now use a two-step approach (`memberGroupIDs` → `groups` with `is_archived` filter) matching the existing `fetchMembers` pattern. Filtering now happens server-side via `.eq("is_archived", value: false/true)` on the `groups` table.
