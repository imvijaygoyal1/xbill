# xBill — Claude Code Context

> **IMPORTANT FOR CLAUDE:** After every code change to this project, update this file to reflect the change. New file → add to File Map. New pattern → update Key Patterns. This file must always stay current.
> **After every feature implementation, run `xcodegen generate` if new Swift files were added, then build + install on simulator DA97985A-F7CC-44F6-8281-9DD24C22B978.**
> **Native patterns:** Before writing any SwiftUI view, read `NATIVE_PATTERNS.md`. It defines the required conventions for navigation, lists, SF Symbols, typography, colors, controls, sheets, empty states, swipe actions, animations, accessibility, haptics, safe area, and performance. Every rule in that file is non-negotiable.

## App Identity
- **Name:** xBill
- **Bundle ID:** `com.vijaygoyal.xbill`
- **Platform:** iOS 17+, iPhone only
- **Swift:** 6.0, strict concurrency enabled
- **Architecture:** SwiftUI + `@Observable` + Supabase (PostgreSQL + Auth + Realtime)
- **Project path:** `/Users/vijaygoyal/MyiOSApp/xBill`
- **Project generation:** `xcodegen generate` (from `project.yml`)

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
- **Always build and run on simulator after implementing a feature.**

## Supabase
- **Project URL:** `https://rhdhazevigbchmwzesok.supabase.co`
- **Anon key:** stored in `project.yml` under `SUPABASE_URL` / `SUPABASE_ANON_KEY` build settings
- **Credentials injection:** `xBill/Info.plist` template uses `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` — do NOT use `GENERATE_INFOPLIST_FILE: YES` (it ignores custom build settings)
- **Auth:** Email/password + Sign In with Apple; email confirmation is ON in Supabase dashboard
- **Push migrations:** `supabase db push` from `/Users/vijaygoyal/MyiOSApp/xBill`
- **URL scheme:** `xbill://` — registered in `Info.plist` (`CFBundleURLTypes`); Supabase dashboard Site URL + Redirect URL set to `xbill://auth/callback`
- **Resend SMTP:** configured in Supabase dashboard (Auth → SMTP) using `smtp.resend.com:465`, username `resend`, password = Resend API key
- **Edge Functions:** `supabase/functions/invite-member/index.ts` — sends group invite emails via Resend API; secrets: `RESEND_API_KEY`, `INVITE_FROM_EMAIL`

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

## File Map

### Entry Point
- `xBill/xBillApp.swift` — `@main`, creates `AuthViewModel`, passes to `ContentView`, starts auth listener + loads current user; `.onOpenURL` passes deep links to `supabase.auth.session(from:)` for email confirmation + password reset

### Edge Functions
- `supabase/functions/invite-member/index.ts` — Deno; calls Resend API to send group invite emails; expects `{ groupName, groupEmoji, inviterName, emails[] }`; returns `{ sent, failed[] }`

### Design System
- `xBill/Views/Components/XBillWordmark.swift` — `XBillWordmark` view: "xBill" in `.heavy` 22pt `brandPrimary`, tracking -0.8 + kerning -0.5; used as `.principal` toolbar item in `HomeView`
- `xBill/Core/DesignSystem/XBillTheme.swift` — `XBillTheme` enum (clay-inspired theme): `background` (warm cream `#faf9f7`), `surface` (white), `primaryBrand` (Ube 800), `accentMint` (Matcha 600), `accentCoral` (Pomegranate 400); clay multi-layer shadow; `cardRadius = 24`, `sectionRadius = 40`; `ClayCard` ViewModifier (white, 24pt corners, oat border `#dad4c8`, multi-layer shadow, optional dashed border); `ClayButtonStyle` (press: scaleEffect 0.94 + rotationEffect -3° + hard offset shadow); `SwatchSection` modifier for full-width colored sections; `View.asClayCard()` + `View.asSharpCard()` (alias) + `View.swatchSection(_:radius:)` extensions
- `xBill/Core/DesignSystem/XBillColors.swift` — `Color` extension with asset catalog tokens + clay swatch palette: `clayMatcha` (#078a52), `claySlushie` (#3bd3fd), `clayLemon` (#fbbd41), `clayUbe` (#43089f), `clayPomegranate` (#fc7981), `clayBlueberry` (#01418d), `clayCanvas` (#faf9f7), `clayOatBorder` (#dad4c8), `claySilver` (#9f9b93), plus light/dark swatch variants
- `xBill/Core/DesignSystem/XBillFonts.swift` — `Font` extension; clay weight hierarchy: 600 (headings/`.bold`/`.semibold`) / 500 (UI/`.medium`) / 400 (body/`.regular`); amounts use `.monospaced`; all others `.rounded`; `xbillUpperLabel` for uppercase labels (apply `.tracking(1.08)` at call site); **all tokens use Dynamic Type text styles** — do NOT revert to fixed `size:` integers
- `xBill/Core/DesignSystem/XBillLayout.swift` — `XBillSpacing`, `XBillRadius` (clay scale: `.sharp`=4, `.sm`=8, `.md`=12, `.card`=24, `.section`=40, `.full`=999), `XBillIcon` enums
- `xBill/Core/Extensions/HapticManager.swift` — `@MainActor enum HapticManager` with `impact(_:)`, `success()`, `error()`, `selection()` helpers

### Color Assets (Assets.xcassets)
31 named color sets with light/dark variants: `BrandPrimary`, `BrandAccent`, `BrandSurface`, `BrandDeep`, `BgPrimary`, `BgSecondary`, `BgTertiary`, `BgCard`, `TextPrimary`, `TextSecondary`, `TextTertiary`, `TextInverse`, `MoneyPositive`, `MoneyNegative`, `MoneySettled`, `MoneyTotal`, `MoneyPositiveBg`, `MoneyNegativeBg`, `MoneySettledBg`, `Separator`, `TabBarBg`, `NavBarBg`, `InputBg`, `InputBorder`, `CatFood`, `CatTravel`, `CatHome`, `CatEntertain`, `CatHealth`, `CatShopping`, `CatOther`

### Core
- `xBill/Core/AppState.swift` — `@Observable final class AppState: @unchecked Sendable` singleton (`AppState.shared`); `pendingQuickAction: QuickAction?` (.addExpense/.scanReceipt) set by AppDelegate; `spotlightTarget: SpotlightTarget?` (.group(UUID)) set by Spotlight NSUserActivity handler in xBillApp; consumed by MainTabView via `.task(id:)`
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
- `xBill/Models/User.swift` — `struct User: Codable, Identifiable` → matches `profiles` table (id, email, displayName, avatarURL, createdAt)
- `xBill/Models/Group.swift` — `struct BillGroup: Codable, Identifiable` (NOT `Group` — would clash with `SwiftUI.Group`); `struct GroupMember`
- `xBill/Models/Expense.swift` — `struct Expense`, `enum Expense.Category` (with `displayName`, `systemImage`, `allCases`)
- `xBill/Models/Split.swift` — `struct Split`; `SplitStrategy` has `.equal`, `.percentage`, `.exact`, `.shares`; `SplitInput` has `shares: Int` (default 1) for weighted sharing
- `xBill/Models/Settlement.swift` — `struct SettlementSuggestion: Identifiable` (fromName, toName, amount, currency)
- `xBill/Models/Receipt.swift` — `struct Receipt` for OCR-scanned receipts
- `xBill/Models/ActivityItem.swift` — legacy stub; replaced by `NotificationItem`
- `xBill/Models/NotificationItem.swift` — `struct NotificationItem: Identifiable, Sendable, Codable` (id, eventType, title, subtitle, amount, currency, category, createdAt, isRead); `NotificationEventType` enum (.expenseAdded, .settlementMade); static factory methods `.expense(...)` and `.settlement(...)`
- `xBill/Models/ReceiptJSON.swift` — `ParsedReceiptJSON` + `ParsedItemJSON` (Decodable); shared output schema for both FoundationModelService and heuristic parser

### Services
- `xBill/Services/ExchangeRateService.swift` — `actor`; fetches from `open.er-api.com/v6/latest/{base}` (no key needed); 1-hour in-memory cache; `convert(amount:from:to:)` and `rate(from:to:)`; `commonCurrencies` static array of 20 codes
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
- `xBill/Services/VisionService.swift` — Two-tier receipt parsing. Tier 1: `FoundationModelService` (iOS 26+, Apple Intelligence, ~90–95% accuracy). Tier 2: improved heuristics with spatial bounding-box grouping (iOS 17+, ~75–80%). Both return `ScanResult(receipt:confidence:tier:validationWarning:)`. Validates items+tax+tip ≈ total within $0.02, including delta amount in the warning (e.g. "$0.30 unaccounted for"). Key internals: CoreImage preprocessing (resize to 1200px + CIPhotoEffectNoir grayscale + CIColorControls contrast 1.4/brightness 0.05); `usesLanguageCorrection = false`; adaptive row threshold (60% of median Y gap, clamped 0.012…0.045); `extractAmount` handles European format (1.234,56), comma-decimal (12,50), skips parenthetical/negative amounts; `detectCurrency` covers £/€/₹/¥/₩; `isMetadata` check runs BEFORE price extraction with expanded keyword list; priority-based total detection (grandTotalCandidate from ["grand total","total due","amount due","balance due","total amount"] wins over regularTotalCandidate from plain "total", filters "savings"/"card"); merchant = first non-metadata, non-price row (len≥3).
- `xBill/Services/FoundationModelService.swift` — `@available(iOS 26.0, *)`. Uses `LanguageModelSession(instructions:)` + `session.respond(to: ocrText, generating: ReceiptGenerable.self)` for structured output via `@Generable` types (`ReceiptGenerable` + `ItemGenerable`). Minimum quality check: rejects OCR text with < 3 lines before hitting the model. Returns `ParsedReceiptJSON`. Falls through to heuristics on failure. If `@Generable` macro unavailable at compile time, falls back to JSON-based approach.
- `xBill/Services/NotificationStore.swift` — local-first notification persistence; `merge([NotificationItem])` deduplicates by id, caps at 100 items; `lastViewedAt()` / `markAllRead()` for unread tracking; `unreadCount()` returns items newer than lastViewedAt; uses `CacheService.defaults` (App Group UserDefaults); `clearAll()` for test teardown
- `xBill/Services/ActivityService.swift` — returns `[NotificationItem]`; fetches expenses per group in parallel, merges into `NotificationStore`, returns combined list sorted newest-first
- `xBill/Services/NotificationService.swift` — Local push notifications
- `xBill/Services/ExportService.swift` — `@MainActor`; `generateCSV(group:expenses:memberNames:) -> Data`; `generatePDF(group:expenses:memberNames:balances:) -> Data` (PDFKit A4 report with summary, balances, expense table); `writeTemp(data:filename:) throws -> URL` for share sheet

### ViewModels
- `xBill/ViewModels/AuthViewModel.swift` — `@Observable @MainActor`; `currentUser: User?`, `confirmationEmailSent: Bool`, `isInPasswordRecovery: Bool`, `isLoading`, `error`, `pendingJoinRequest: InviteJoinRequest?`; `startListeningToAuthChanges()` handles `.passwordRecovery` event; `handlePasswordReset(newPassword:)` calls `supabase.auth.update`. `InviteJoinRequest` is a top-level `Identifiable` struct with `token: String`
- `xBill/ViewModels/HomeViewModel.swift` — loads groups, computes net balance + `recentExpenses: [RecentEntry]` (top 10 across all groups, members co-fetched); `RecentEntry` is `{ expense, members }` identifiable struct; `archivedGroups: [BillGroup]`; `crossGroupSuggestions: [SettlementSuggestion]` (cross-group debt, filtered to current user); `unarchiveGroup(_:)` unarchives and refreshes both lists; `groupsNavigationPath: NavigationPath`; `createSampleData(userID:)` creates demo group + 3 expenses; `fullBalancesInGroup` returns `GroupBalanceData` (owed, owing, entries, currency, rawBalances, names); `computeBalances` merges per-currency balance maps, calls `minimizeTransactions`, saves to CacheService, calls `WidgetCenter.shared.reloadAllTimelines()`
- `xBill/ViewModels/GroupViewModel.swift` — loads members + expenses, computes balances + settlement suggestions, `recordSettlement()`; `archiveGroup()` / `unarchiveGroup()` set `isArchived` via `GroupService.updateGroup` and update `CacheService` immediately (remove/append to active-groups cache); `createDueRecurringInstances(currentUserID:)` fetches due recurring expenses, creates new instances, clears old `next_occurrence_date`
- `xBill/ViewModels/AddExpenseViewModel.swift` — split calculation; `expenseCurrency` (defaults to group currency); `convertedAmount`/`exchangeRate` computed via `ExchangeRateService.shared`; `updateConversion()` called on currency/amount change; `finalAmount` = converted or raw; `save()` passes `originalAmount`/`originalCurrency` when foreign currency used
- `xBill/ViewModels/ProfileViewModel.swift` — profile editing; `loadStats(userID:)` fetches groups + expenses concurrently via `withTaskGroup` to compute `totalGroupsCount`, `totalExpensesCount`, `lifetimePaid`; `saveProfile(avatarImage:)` uploads avatar via `AuthService.uploadAvatar` then calls `updateProfile`
- `xBill/ViewModels/ActivityViewModel.swift` — `items: [NotificationItem]`; `unreadCount: Int` synced from `NotificationStore`; `markAllRead()` clears badge; `hasUnread: Bool` computed
- `xBill/ViewModels/ReceiptViewModel.swift` — receipt scan + review flow; `merchantName`, `totalAmount`, `tipAmount: String` mutable vars; `toggleAssignAll(to:)`, `updateUnitPrice`, `hasUnassignedItems`, `total(for:)`; **`startManually(members:)`** — creates blank Receipt, clears scan state, sets members; allows bypassing camera for manual line-item entry

### Widget Extension
- `xBillWidget/xBillWidgetBundle.swift` — `@main WidgetBundle` containing `xBillBalanceWidget`
- `xBillWidget/xBillBalanceWidget.swift` — `StaticConfiguration` widget; `BalanceProvider` reads from shared `UserDefaults` (App Group); `BalanceEntry` has date/netBalance/totalOwed/totalOwing; `BalanceWidgetView` shows owed/owing in a simple layout; `.systemSmall`+`.systemMedium` families; refreshes every 30 minutes
- `xBillWidget/Info.plist` — explicit plist with `NSExtensionPointIdentifier = com.apple.widgetkit-extension` (required for WidgetKit app extensions)
- `xBillWidget/xBillWidget.entitlements` — App Group entitlement `group.com.vijaygoyal.xbill`

### Views — App Lock
- `xBill/Views/AppLockView.swift` — full-screen overlay shown when `AppLockService.shared.isLocked`; brandPrimary background; biometry icon + wordmark + unlock button; `task` auto-triggers authentication on appear; uses `ClayButtonStyle`

### Views — Auth
- `xBill/Views/Auth/AuthView.swift` — `bgSecondary` background; `brandPrimary` wordmark icon; Sign In with Apple button; "Continue with Email" NavigationLink; fine print with two distinct `Button` links: "Terms of Service" presents `TermsOfServiceView()` sheet (`.large` detent, drag indicator visible), "Privacy Policy" opens `.safariSheet` to `XBillURLs.privacyPolicy`; both fire `HapticManager.selection()`
- `xBill/Views/Auth/EmailAuthView.swift` — `XBillTextField` fields; `XBillButton(style:.primary)` submit; `bgSecondary` background; "Forgot password?" button (sign-in mode only) presents `ForgotPasswordView` sheet with `prefillEmail: vm.email`
- `xBill/Views/Auth/ForgotPasswordView.swift` — two-step sheet (form → success); calls `AuthService.shared.sendPasswordReset`; inline error display; 30s resend cooldown via `Task`-based sleep loop (no `Timer`); shows success state even for "user not found" errors (account enumeration prevention); `HapticManager.success()/error()` feedback; private `HintRow` and `ResendButtonView` subviews
- `xBill/Views/Auth/ResetPasswordView.swift` — shown when app opened from password reset link; new + confirm password fields; calls `authVM.handlePasswordReset(newPassword:)`

### Views — Legal
- `xBill/Views/Legal/TermsOfServiceView.swift` — in-app ToS screen; native `NavigationStack` + `ScrollView`; header card with `brandPrimary` background; 10 `TOSSection` cards (numbered circle + title + body text); `XBillWordmark` in `.principal` toolbar; "Done" dismiss button; presented as `.sheet` (`.large` detent, drag indicator) from `AuthView` and `ProfileView`; file-private `TOSSection` struct takes `number`, `title`, `content: String` directly

### Views — Onboarding
- `xBill/Views/Onboarding/OnboardingView.swift` — 4-page swipeable onboarding (TabView .page style); shown once after first sign-in via `@AppStorage("hasCompletedOnboarding")` flag in `ContentView`; pages: Welcome, Groups, Receipts, Balances; "Skip" on pages 1–3, "Get Started" on page 4 — both set `hasCompletedOnboarding = true`

### Views — Main
- `xBill/Views/Main/ContentView.swift` — animated transition priority: `ResetPasswordView` → (logged in) `OnboardingView` (first launch only) or `MainTabView` → `AuthView`; `@AppStorage("hasCompletedOnboarding")` controls onboarding gate
- `xBill/Views/Main/MainTabView.swift` — 5 tabs: Home / Groups / Friends / Activity / Profile; Activity tab uses `bell.fill` icon + `.badge(activityVM.unreadCount > 0 ? activityVM.unreadCount : 0)` for unread notification count; shares `homeVM` between Home and Groups tabs; Friends tab passes `homeVM.currentUser?.id`; tab bar uses `.ultraThinMaterial` glassmorphic background; handles `AppState.shared.pendingQuickAction` via `.task(id:)` → switches to Groups tab + shows `QuickAddExpenseSheet`; handles `AppState.shared.spotlightTarget` via `.task(id:)` → navigates to group via `homeVM.groupsNavigationPath`
- `xBill/Views/Main/HomeView.swift` — `BalanceHeroCard` + quick stats row + horizontal `ScrollView` of `GroupChipView` chips + "RECENT EXPENSES" `LazyVStack`; no nav bar `+` button; FAB only; `.inline` title
- `xBill/Views/Main/ActivityView.swift` — renamed to "Notifications" in nav title; `bell.fill` icon; sections grouped by date; unread blue dot per row; "Mark All Read" toolbar button when `vm.hasUnread`; `onAppear` auto-marks read; `NotificationRowView` shows different icon per eventType (CategoryIconView for expenses, checkmark for settlements); `AmountBadge(.total/.settled)` per type; full a11y label

### Views — Groups
- `xBill/Views/Groups/CreateGroupView.swift` — 4×5 emoji grid picker (20 emojis), currency picker (uses `ExchangeRateService.commonCurrencies`), invite email field (wired: sends invite via `GroupService.inviteMembers` after group creation if non-empty, non-fatal error)
- `xBill/Views/Groups/GroupListView.swift` — groups list tab; shares `HomeViewModel`; active groups section + collapsible "Archived (N)" section (tap header to expand); swipe-left on archived row → "Unarchive" button; navigates to `GroupDetailView` (guarded: only navigates when `vm.currentUser?.id` is non-nil; passes `onGroupStatusChanged` callback that calls `vm.refresh()` + `vm.loadArchivedGroups()`); `onCreated` callback appends new group directly to `vm.groups` and calls `SpotlightService.indexGroups` (no full network refresh); loads archived groups on `.task`
- `xBill/Views/Groups/GroupDetailView.swift` — takes `onGroupStatusChanged: (() async -> Void)?` callback (called after archive or unarchive, triggers `HomeViewModel` refresh before dismiss); segmented Picker (Expenses/Balances/Settle Up) tabs; `AmountBadge` in balances; `AmountBadge(.total)` on expense rows; FAB only on Expenses tab; Settle Up embedded; toolbar menu has: Add Expense, Stats, Export (CSV/PDF via `ExportService`+`ShareSheetView`), Invite via Email, Invite via Link (QR), **Archive Group** (shown only when `!vm.group.isArchived`) or **Unarchive Group** (shown when `vm.group.isArchived`); archive confirmation shows unsettled-balance count if `!vm.settlementSuggestions.isEmpty`; `.task` also calls `vm.createDueRecurringInstances(currentUserID:)`; `.searchable` on Group to add search bar; horizontal `ExpenseFilterChip` strip for category filter on Expenses tab; `filteredExpenses` computed property filters `vm.sortedExpenses` by `searchText` and `filterCategory`
- `xBill/Views/Groups/QuickAddExpenseSheet.swift` — sheet for "Add Expense"/"Scan Receipt" quick actions; shows list of active groups; fetches members on group selection; presents `AddExpenseView` with optional `startWithScan: true`
- `xBill/Views/Groups/GroupInviteView.swift` — shows QR code (CoreImage `CIFilter.qrCodeGenerator`) + `ShareLink` for `xbill://join/<token>`; generates a new invite on appear; refresh button in toolbar
- `xBill/Views/Groups/JoinGroupView.swift` — confirms and handles group join via invite token; fetches group name, shows confirmation card, calls `joinGroupViaInvite` RPC on confirm
- `xBill/Views/Groups/SettleUpView.swift` — settlement suggestions with Venmo link + Mark Settled button
- `xBill/Views/Groups/InviteMembersView.swift` — email invite list; "Import from Contacts" button opens `CNContactPickerViewController` (no upfront permission needed); selected emails added to pending list; `lookupXBillUsers` checks DB via `GroupService.lookupProfilesByEmail`; "On xBill" badge on matching emails; calls `GroupService.inviteMembers` → `invite-member` Edge Function

### Views — Expenses
- `xBill/Views/Friends/FriendsView.swift` — Friends tab; groups IOUs by other person; net balance per currency per friend; FAB to AddIOUView; navigates to `FriendDetailView`
- `xBill/Views/Friends/FriendDetailView.swift` — (defined in FriendsView.swift) outstanding + settled IOU sections; "Settle All" button
- `xBill/Views/Friends/AddIOUView.swift` — email search to find user; amount + currency picker; "I owe / they owe" toggle; calls `IOUService.createIOU`
- `xBill/Views/Expenses/AddExpenseView.swift` — `bgSecondary` sheet; hero amount `TextField`; currency picker `Menu` next to currency symbol; conversion preview when foreign currency; "Repeat" section with `Expense.Recurrence` picker (Does not repeat / Weekly / Monthly / Yearly); `ExchangeRateService.commonCurrencies` populates the currency picker
- `xBill/Views/Expenses/ExpenseDetailView.swift` — expense detail with split breakdown + Comments section (realtime); `currentUserID: UUID` required; comment input bar via `safeAreaInset(edge: .bottom)`
- `xBill/Views/Expenses/ReceiptScanView.swift` — accepts `members: [User]` + `onConfirmed: ([SplitInput]) -> Void`; camera via `VNDocumentCameraViewController` (`DocumentCameraView: UIViewControllerRepresentable`) for automatic perspective correction — presented as `fullScreenCover`; photo library via `PhotosPicker` (modern, non-deprecated); shows "Review Receipt" button after scan completes; pushes `ReceiptReviewView` via `navigationDestination`; "Scan Again" resets state; camera button disabled when `VNDocumentCameraViewController.isSupported == false`
- `xBill/Views/Expenses/ReceiptReviewView.swift` — item review, member chip assignment, per-person totals; merchant name editable via `XBillTextField` bound to `$vm.merchantName`; tip and total amount editable via `XBillTextField` (`.decimalPad`) bound to `$vm.tipAmount` and `$vm.totalAmount`; tax remains read-only; "Use These Splits" calls `onConfirmed` then dismisses back to `AddExpenseView`; currency from `vm.scannedReceipt?.currency ?? "USD"`; file-private `ItemRow` subview with inline price `TextField` + quantity stepper + member assignment chips; "All" chip calls `vm.toggleAssignAll(to:)`; unassigned-items warning banner; delta-containing validation warning from VisionService

### Views — Profile
- `xBill/Views/Profile/ProfileView.swift` — `bgSecondary` page; Payment Handles section (`venmoHandle`/`paypalEmail` in `ProfileViewModel`, not persisted to DB); `xbillSmallAmount` for Total Paid; `XBillButton(.ghost)` sign out with `moneyNegative` foreground; footer section with "Terms of Service" + "Privacy Policy" links (`.safariSheet` to `XBillURLs.termsOfService`/`privacyPolicy`) + app version string

### Views — Components
- `xBill/Views/Components/AvatarView.swift` — circular avatar; deterministic bg color from name hash (brandPrimary first); `XBillIcon.avatarMd` default; `textInverse` initials
- `xBill/Views/Components/BalanceBadge.swift` — green (owed to you) / red (you owe) badge (legacy; prefer `AmountBadge` for new screens)
- `xBill/Views/Components/AmountBadge.swift` — colored pill badge with `AmountDirection` (.positive/.negative/.settled/.total); uses design system money tokens
- `xBill/Views/Components/BalanceHeroCard.swift` — `Color.brandPrimary` hero card for balance display at top of screens; `.xbillHeroAmount` monospaced number
- `xBill/Views/Components/XBillCard.swift` — generic card wrapper; delegates to `SharpCard` modifier (18pt corners, hairline border, drop shadow)
- `xBill/Views/Components/XBillButton.swift` — design-system button with `.primary/.secondary/.ghost/.destructive` styles; fires `HapticManager.impact` on tap
- `xBill/Views/Components/XBillTextField.swift` — `inputBg`/`inputBorder` styled text field; focus-animated border turns `brandPrimary`
- `xBill/Views/Components/CategoryIconView.swift` — emoji icon in category-colored rounded square; extends `Expense.Category` with `.emoji` and `.categoryBackground`
- `xBill/Views/Components/OfflineBanner.swift` — orange banner shown via `safeAreaInset(edge:.top)` in HomeView and GroupDetailView when `NetworkMonitor.shared.isConnected == false`
- `xBill/Views/Components/FABButton.swift` — 56pt `brandPrimary` circle FAB with shadow and haptic
- `xBill/Views/Components/GroupChipView.swift` — compact 110pt card for horizontal group scroll in HomeView
- `xBill/Views/Components/ExpenseRowView.swift` — expense list row; `showAmountBadge: Bool = false` — when true shows `AmountBadge(.total)` instead of plain amount text
- `xBill/Views/Components/EmptyStateView.swift` — wraps `ContentUnavailableView` (iOS 17+); `(icon:title:message:actionLabel?:action?)` API unchanged; action button uses `.borderedProminent` style; two variants compiled at runtime: with/without action
- `xBill/Views/Components/LoadingOverlay.swift` — centered spinner with message
- `xBill/Views/Components/SplitSlider.swift` — percentage split slider
- `xBill/Views/Components/SafariView.swift` — `UIViewControllerRepresentable` wrapping `SFSafariViewController`; branded with `UIColor(Color.brandPrimary)` bar tint + white controls; `View.safariSheet(isPresented:url:)` extension for presenting in-app; used for privacy policy links — do NOT use `openURL` env action for policy links
- `xBill/Views/Components/ShareSheetView.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController`; accepts a `URL` to share; used by `GroupDetailView` for CSV/PDF export

### Tests
- `xBillTests/SplitCalculatorTests.swift` — 17 tests: equal split (even/rounding/excluded/single), percentage (proportional/rounding), exact validation (pass/fail), net balances, single payer, circular debt, partially settled, two people, floating point precision (÷3), minimize transactions (basic/all-settled). Fixed 2026-04-29: added `recurrence: .none` to all `Expense` inits; removed stale `updatedAt:` arg; fixed `\.amount` key-path inference in `#expect`.
- `xBillTests/P2FeatureTests.swift` — 18 tests across 5 suites: CrossGroupDebt (balance merging, currency separation, minimisation), AppLock (lock/no-op state transitions, MainActor), ManualReceipt (startManually creates blank receipt, assigns members, clears previous scan), CacheServiceBalance (.serialized, round-trip and zero-default), ContactDiscovery (email validation, dedup, lowercasing).
- `xBillTests/P1NotificationTests.swift` — 16 tests across 4 suites: NotificationStore (.serialized, merge dedup, read-state preservation, sort order, unread count, markAllRead, 100-item cap), NotificationItemFactory (expense + settlement factory field mapping), ActivityViewModelUnread (hasUnread flag, markAllRead zeros VM), NotificationItemCodable (expense + settlement JSON round-trip).
- `xBillTests/GroupFlowTests.swift` — 27 tests across 6 suites: GroupFlowCachePattern (archive/unarchive array-manipulation logic, idempotency), BillGroupModel (Codable roundtrip, snake_case CodingKeys, Equatable, value-type semantics), GroupCreationLogic (onCreated append, canCreate guard, invite email trim), GroupArchiveLogic (balance-warning conditions, plural/singular, toolbar action context), CurrencyList (count=20, original 8 + 12 new, no duplicates), RealtimeContract (topic scoping). All tests are parallel-safe (no shared UserDefaults state).
- `xBillUITests/OnboardingUITests.swift`
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

### Deep Link URL Scheme
- Scheme: `xbill://`; registered in `Info.plist` under `CFBundleURLTypes`
- All Supabase auth links (confirmation, password reset) redirect to `xbill://auth/callback`
- Group invite links: `xbill://join/<token>` — parsed in `xBillApp.onOpenURL`; sets `authVM.pendingJoinRequest`; `MainTabView` shows `JoinGroupView` sheet via `sheet(item: $authVM.pendingJoinRequest)`
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

**Known bugs (diagnosed 2026-04-28):**
- `AuthViewModel.swift:58` — `emailConfirmedAt` guard blocks Apple users on cold relaunch (Apple Sign In users have `nil` emailConfirmedAt). Fix: add `|| credential.provider == "apple"` check or separate the guard into email-only path.
- `xBill.entitlements` — `aps-environment: production` conflicts with debug provisioning profiles. Should be `development` for debug builds.

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
- Use `.accessibilityHidden(true)` on purely decorative icons (e.g. onboarding illustrations)

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
- **`NotificationStore`** (`Services/NotificationStore.swift`) — local-first persistence via App Group UserDefaults; `merge(_:)` deduplicates by id and caps at 100 items; `lastViewedAt()` / `markAllRead()` timestamp-based read tracking; `unreadCount()` = items newer than lastViewedAt; `clearAll()` for test teardown
- **`ActivityService`** — now returns `[NotificationItem]`; merges DB-fetched expense items into store on each fetch (preserving read state for existing items)
- **`ActivityViewModel`** — `unreadCount: Int`, `markAllRead()`, `hasUnread: Bool` computed
- **`ActivityView`** — title changed to "Notifications", `bell.fill` tab icon; unread blue dot per row; "Mark All Read" toolbar button; auto-marks read on appear
- **`MainTabView`** — `.badge(activityVM.unreadCount > 0 ? activityVM.unreadCount : 0)` on Activity tab
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
- Deploy `delete-account` Edge Function: `supabase functions deploy delete-account`
- Deploy migration 018: `supabase db push` (adds `lookup_profiles_by_email` RPC)
- App Store Assets: screenshots, preview video, keyword strategy (only remaining P0 blocker)

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
