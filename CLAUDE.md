# xBill — Claude Code Context

> **IMPORTANT FOR CLAUDE:** After every code change to this project, update this file to reflect the change. New file → add to File Map. New pattern → update Key Patterns. This file must always stay current.
> **After every feature implementation, run `xcodegen generate` if new Swift files were added, then build + install on simulator DA97985A-F7CC-44F6-8281-9DD24C22B978.**

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
- Install + launch:
  ```
  xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 <APP_PATH>
  xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.xbill
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
| `expenses` | `id uuid PK`, `group_id uuid`, `title text`, `amount numeric`, `currency text`, `category text`, `notes text`, `paid_by uuid`, `created_at` |
| `splits` | `id uuid PK`, `expense_id uuid`, `user_id uuid`, `amount numeric`, `is_settled bool` |
| `comments` | `id uuid PK`, `expense_id uuid`, `user_id uuid`, `text text`, `created_at` |
| `group_invites` | `token text PK (default: uuid stripped of dashes)`, `group_id uuid`, `created_by uuid`, `expires_at (default: +7 days)` |

### RPC Functions
- `add_expense_with_splits(p_group_id, p_paid_by, p_amount, p_title, p_category, p_currency, p_notes, p_receipt_url, p_splits[])` — atomic expense + splits insert; `p_splits` is an array of `split_input` composite type `{user_id uuid, amount numeric}`

### Migrations (in order)
1. `001_initial_schema.sql` — All tables, RLS, `is_group_member()` + `is_expense_group_member()` helpers
2. `002_rpc_add_expense.sql` — `split_input` composite type + `add_expense_with_splits` RPC
3. `003_profiles_add_email.sql` — `ALTER TABLE profiles ADD COLUMN email text NOT NULL DEFAULT ''`
4. `004_profile_trigger.sql` — `handle_new_user()` trigger: auto-creates profile row on `auth.users` INSERT (runs as `SECURITY DEFINER`, bypasses RLS)
5. `005_backfill_profiles.sql` — Inserts profiles for existing auth users without profile rows
6. `006_groups_currency_member_rls.sql` — Adds `currency` to groups; fixes RLS to allow group creator to insert themselves as first member
7. `007_groups_creator_read.sql` — Fixes groups SELECT policy to allow `created_by = auth.uid()`, so the INSERT RETURNING clause succeeds before the creator is added as a member
11. `011_expense_comments.sql` — `comments` table; RLS (group members can view/insert, author can delete); Realtime enabled
12. `012_group_invites.sql` — `group_invites` table; `join_group_via_invite(p_token)` SECURITY DEFINER RPC (validates expiry, idempotent insert into group_members, returns group_id)

## File Map

### Entry Point
- `xBill/xBillApp.swift` — `@main`, creates `AuthViewModel`, passes to `ContentView`, starts auth listener + loads current user; `.onOpenURL` passes deep links to `supabase.auth.session(from:)` for email confirmation + password reset

### Edge Functions
- `supabase/functions/invite-member/index.ts` — Deno; calls Resend API to send group invite emails; expects `{ groupName, groupEmoji, inviterName, emails[] }`; returns `{ sent, failed[] }`

### Design System
- `xBill/Core/DesignSystem/XBillColors.swift` — `Color` extension with all brand/background/text/money/category/chrome tokens (reference named assets in Assets.xcassets)
- `xBill/Core/DesignSystem/XBillFonts.swift` — `Font` extension with all `xbill*` tokens; amounts use `.monospaced` design
- `xBill/Core/DesignSystem/XBillLayout.swift` — `XBillSpacing`, `XBillRadius`, `XBillIcon` enums with spacing/radius/size constants
- `xBill/Core/Extensions/HapticManager.swift` — `@MainActor enum HapticManager` with `impact(_:)`, `success()`, `error()`, `selection()` helpers

### Color Assets (Assets.xcassets)
31 named color sets with light/dark variants: `BrandPrimary`, `BrandAccent`, `BrandSurface`, `BrandDeep`, `BgPrimary`, `BgSecondary`, `BgTertiary`, `BgCard`, `TextPrimary`, `TextSecondary`, `TextTertiary`, `TextInverse`, `MoneyPositive`, `MoneyNegative`, `MoneySettled`, `MoneyTotal`, `MoneyPositiveBg`, `MoneyNegativeBg`, `MoneySettledBg`, `Separator`, `TabBarBg`, `NavBarBg`, `InputBg`, `InputBorder`, `CatFood`, `CatTravel`, `CatHome`, `CatEntertain`, `CatHealth`, `CatShopping`, `CatOther`

### Core
- `xBill/Core/SupabaseClient.swift` — `SupabaseManager.shared`; reads URL/key from `Bundle.main.infoDictionary`; graceful fallback to placeholder (no crash) when credentials missing
- `xBill/Core/AppError.swift` — `AppError` enum: `.network`, `.auth`, `.database`, `.confirmationRequired`, `.unknown`; `static func from(_ error: Error) -> AppError`
- `xBill/Core/Extensions.swift` — `View.errorAlert(error:)` modifier; `Decimal.formatted(currencyCode:)`; `errorAlert` shows `error.errorDescription` as title (not generic "Something went wrong")
- `xBill/Core/KeychainManager.swift` — Keychain read/write helpers
- `xBill/Core/NetworkMonitor.swift` — `NWPathMonitor` wrapper

### Models
- `xBill/Models/Comment.swift` — `struct Comment: Codable, Identifiable, Sendable` (id, expenseID, userID, text, createdAt)
- `xBill/Models/GroupInvite.swift` — `struct GroupInvite: Codable, Identifiable, Sendable` (token, groupID, createdBy, expiresAt); `inviteURL` computed property → `xbill://join/<token>`
- `xBill/Models/User.swift` — `struct User: Codable, Identifiable` → matches `profiles` table (id, email, displayName, avatarURL, createdAt)
- `xBill/Models/Group.swift` — `struct BillGroup: Codable, Identifiable` (NOT `Group` — would clash with `SwiftUI.Group`); `struct GroupMember`
- `xBill/Models/Expense.swift` — `struct Expense`, `enum Expense.Category` (with `displayName`, `systemImage`, `allCases`)
- `xBill/Models/Split.swift` — `struct Split`
- `xBill/Models/Settlement.swift` — `struct SettlementSuggestion: Identifiable` (fromName, toName, amount, currency)
- `xBill/Models/Receipt.swift` — `struct Receipt` for OCR-scanned receipts
- `xBill/Models/ActivityItem.swift` — `struct ActivityItem: Identifiable, Sendable` (id, expenseTitle, amount, currency, category, payerName, groupName, groupEmoji, createdAt)
- `xBill/Models/ReceiptJSON.swift` — `ParsedReceiptJSON` + `ParsedItemJSON` (Decodable); shared output schema for both FoundationModelService and heuristic parser

### Services
- `xBill/Services/CommentService.swift` — `fetchComments(expenseID:)`, `addComment(expenseID:userID:text:)`, `deleteComment(id:)`, `commentChanges(expenseID:) → AsyncStream<Void>` (Realtime subscription filtered by expense_id)
- `xBill/Services/AuthService.swift` — `signUpWithEmail`, `signInWithEmail`, `signInWithApple` (CryptoKit SHA256 nonce), `signOut`, `fetchProfile`, `currentUser()`; all table refs use `"profiles"` (not `"users"`)
- `xBill/Services/GroupService.swift` — `fetchGroups(for:)`, `fetchMembers(groupID:)`, `createGroup(...)`, `addMember(groupId:userId:)`, `removeMember(groupId:userId:)`, `inviteMembers(emails:groupName:groupEmoji:inviterName:)`, `groupChanges(userID:) → AsyncStream<Void>`, `createInvite(groupID:createdBy:)`, `fetchInvite(token:)`, `joinGroupViaInvite(token:) → UUID`
- `xBill/Services/ExpenseService.swift` — `fetchExpenses(groupID:)`, `fetchExpense(id:)`, `fetchSplits(expenseID:)`, `fetchUnsettledExpenses(groupID:userID:)`, `createExpense(...)` (uses `add_expense_with_splits` RPC — atomic), `updateExpense(_:)`, `settleSplit(id:)`, `deleteExpense(id:)`, `uploadReceiptImage(_:expenseID:)`
- `xBill/Services/SplitCalculator.swift` — `splitEqually`, `splitByPercentage`, `validateExact`, `netBalances(expenses:splits:)`, `minimizeTransactions(balances:names:currency:)`. `netBalances` skips settled splits and payer's own split — only unsettled non-payer splits affect balances. Used by both `GroupViewModel` and `HomeViewModel` for consistent balance computation.
- `xBill/Services/PaymentLinkService.swift` — Venmo deep-link URL generation
- `xBill/Services/VisionService.swift` — Two-tier receipt parsing. Tier 1: `FoundationModelService` (iOS 26+, Apple Intelligence, ~90–95% accuracy). Tier 2: improved heuristics with spatial bounding-box grouping (iOS 17+, ~75–80%). Both return `ScanResult(receipt:confidence:tier:validationWarning:)`. Validates items+tax+tip ≈ total within $0.02.
- `xBill/Services/FoundationModelService.swift` — `@available(iOS 26.0, *)`. Uses `LanguageModelSession(instructions:)` + `session.respond(to: ocrText)` to produce structured JSON. Strips markdown fences from response before decoding. Falls through to heuristics on failure.
- `xBill/Services/ActivityService.swift` — `fetchRecentActivity(userID:limit:)` fetches all groups, then expenses+members per group in parallel, builds `[ActivityItem]` sorted by `createdAt` desc (default limit 50)
- `xBill/Services/NotificationService.swift` — Local push notifications

### ViewModels
- `xBill/ViewModels/AuthViewModel.swift` — `@Observable @MainActor`; `currentUser: User?`, `confirmationEmailSent: Bool`, `isInPasswordRecovery: Bool`, `isLoading`, `error`, `pendingJoinRequest: InviteJoinRequest?`; `startListeningToAuthChanges()` handles `.passwordRecovery` event; `handlePasswordReset(newPassword:)` calls `supabase.auth.update`. `InviteJoinRequest` is a top-level `Identifiable` struct with `token: String`
- `xBill/ViewModels/HomeViewModel.swift` — loads groups, computes net balance + `recentExpenses: [RecentEntry]` (top 10 across all groups, members co-fetched); `RecentEntry` is `{ expense, members }` identifiable struct; `balancesInGroup` now returns expenses+members alongside balances to avoid duplicate API calls
- `xBill/ViewModels/GroupViewModel.swift` — loads members + expenses, computes balances + settlement suggestions, `recordSettlement()`
- `xBill/ViewModels/AddExpenseViewModel.swift` — split calculation for add-expense form
- `xBill/ViewModels/ProfileViewModel.swift` — profile editing; `loadStats(userID:)` fetches groups + expenses concurrently via `withTaskGroup` to compute `totalGroupsCount`, `totalExpensesCount`, `lifetimePaid`; `saveProfile(avatarImage:)` uploads avatar via `AuthService.uploadAvatar` then calls `updateProfile`
- `xBill/ViewModels/ActivityViewModel.swift` — loads activity feed via `ActivityService`; `load()` gets `currentUserID` from `AuthService` then fetches recent items
- `xBill/ViewModels/ReceiptViewModel.swift` — receipt scan + review flow

### Views — Auth
- `xBill/Views/Auth/AuthView.swift` — `bgSecondary` background; `brandPrimary` wordmark icon; `XBillButton`-style email CTA; Sign In with Apple button
- `xBill/Views/Auth/EmailAuthView.swift` — `XBillTextField` fields; `XBillButton(style:.primary)` submit; `bgSecondary` background
- `xBill/Views/Auth/ResetPasswordView.swift` — shown when app opened from password reset link; new + confirm password fields; calls `authVM.handlePasswordReset(newPassword:)`

### Views — Main
- `xBill/Views/Main/ContentView.swift` — animated transition: `ResetPasswordView` (priority) → `MainTabView` → `AuthView`; `ResetPasswordView` shown when `authVM.isInPasswordRecovery == true`
- `xBill/Views/Main/MainTabView.swift` — 4 tabs: Home / Groups / Activity / Profile; shares `homeVM` between Home and Groups tabs
- `xBill/Views/Main/HomeView.swift` — `BalanceHeroCard` + quick stats row + horizontal `ScrollView` of `GroupChipView` chips + "RECENT EXPENSES" `LazyVStack`; no nav bar `+` button; FAB only; `.inline` title
- `xBill/Views/Main/ActivityView.swift` — sections grouped by date ("TODAY"/"YESTERDAY"/date); `AmountBadge(.total)` trailing; single-line subtitle "Group · Paid by Name"

### Views — Groups
- `xBill/Views/Groups/CreateGroupView.swift` — 4×5 emoji grid picker (20 emojis), currency picker, invite email field
- `xBill/Views/Groups/GroupListView.swift` — groups list tab; shares `HomeViewModel`; navigates to `GroupDetailView`
- `xBill/Views/Groups/GroupDetailView.swift` — segmented Picker (Expenses/Balances/Settle Up) tabs; `AmountBadge` in balances; `AmountBadge(.total)` on expense rows; FAB only on Expenses tab; Settle Up embedded (no separate sheet button); toolbar has "Invite via Email" + "Invite via Link" (QR)
- `xBill/Views/Groups/GroupInviteView.swift` — shows QR code (CoreImage `CIFilter.qrCodeGenerator`) + `ShareLink` for `xbill://join/<token>`; generates a new invite on appear; refresh button in toolbar
- `xBill/Views/Groups/JoinGroupView.swift` — confirms and handles group join via invite token; fetches group name, shows confirmation card, calls `joinGroupViaInvite` RPC on confirm
- `xBill/Views/Groups/SettleUpView.swift` — settlement suggestions with Venmo link + Mark Settled button
- `xBill/Views/Groups/InviteMembersView.swift` — email invite list; calls `GroupService.inviteMembers` → `invite-member` Edge Function

### Views — Expenses
- `xBill/Views/Expenses/AddExpenseView.swift` — `bgSecondary` sheet; hero amount `TextField` centered with bottom border; horizontal category chip `ScrollView` (private `CategoryChipView`); `XBillCard` wrappers for Paid By/Notes/Split sections; `XBillTextField` for title; `xbillSectionTitle` uppercase section labels; standard Cancel/Save toolbar; receipt scan preserved
- `xBill/Views/Expenses/ExpenseDetailView.swift` — expense detail with split breakdown + Comments section (realtime); `currentUserID: UUID` required; comment input bar via `safeAreaInset(edge: .bottom)`
- `xBill/Views/Expenses/ReceiptScanView.swift` — accepts `members: [User]` + `onConfirmed: ([SplitInput]) -> Void`; camera/photo-library picker via `UIImagePickerController` (`ImagePickerController: UIViewControllerRepresentable`); shows "Review Receipt" button after scan completes; pushes `ReceiptReviewView` via `navigationDestination`; "Scan Again" resets state
- `xBill/Views/Expenses/ReceiptReviewView.swift` — item review, member chip assignment, tax/tip display, per-person totals; "Use These Splits" calls `onConfirmed` then dismisses back to `AddExpenseView`

### Views — Profile
- `xBill/Views/Profile/ProfileView.swift` — `bgSecondary` page; Payment Handles section (`venmoHandle`/`paypalEmail` in `ProfileViewModel`, not persisted to DB); `xbillSmallAmount` for Total Paid; `XBillButton(.ghost)` sign out with `moneyNegative` foreground

### Views — Components
- `xBill/Views/Components/AvatarView.swift` — circular avatar; deterministic bg color from name hash (brandPrimary first); `XBillIcon.avatarMd` default; `textInverse` initials
- `xBill/Views/Components/BalanceBadge.swift` — green (owed to you) / red (you owe) badge (legacy; prefer `AmountBadge` for new screens)
- `xBill/Views/Components/AmountBadge.swift` — colored pill badge with `AmountDirection` (.positive/.negative/.settled/.total); uses design system money tokens
- `xBill/Views/Components/BalanceHeroCard.swift` — `Color.brandPrimary` hero card for balance display at top of screens; `.xbillHeroAmount` monospaced number
- `xBill/Views/Components/XBillCard.swift` — generic `bgCard` card wrapper with separator border
- `xBill/Views/Components/XBillButton.swift` — design-system button with `.primary/.secondary/.ghost/.destructive` styles; fires `HapticManager.impact` on tap
- `xBill/Views/Components/XBillTextField.swift` — `inputBg`/`inputBorder` styled text field; focus-animated border turns `brandPrimary`
- `xBill/Views/Components/CategoryIconView.swift` — emoji icon in category-colored rounded square; extends `Expense.Category` with `.emoji` and `.categoryBackground`
- `xBill/Views/Components/FABButton.swift` — 56pt `brandPrimary` circle FAB with shadow and haptic
- `xBill/Views/Components/GroupChipView.swift` — compact 110pt card for horizontal group scroll in HomeView
- `xBill/Views/Components/ExpenseRowView.swift` — expense list row; `showAmountBadge: Bool = false` — when true shows `AmountBadge(.total)` instead of plain amount text
- `xBill/Views/Components/EmptyStateView.swift` — icon + title + message + optional action button
- `xBill/Views/Components/LoadingOverlay.swift` — centered spinner with message
- `xBill/Views/Components/SplitSlider.swift` — percentage split slider

### Tests
- `xBillTests/SplitCalculatorTests.swift` — 17 tests: equal split (even/rounding/excluded/single), percentage (proportional/rounding), exact validation (pass/fail), net balances, single payer, circular debt, partially settled, two people, floating point precision (÷3), minimize transactions (basic/all-settled)
- `xBillUITests/OnboardingUITests.swift`

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

### Error Display
- `errorAlert` modifier shows `error.errorDescription` as the alert title (not a generic string) — useful for debugging
- `error = nil` is only cleared on success, not at the start of an action (prevents alert dismissal)

### RLS Chicken-and-Egg for Group Creation
- Creator can't satisfy `is_group_member(group_id)` for a brand-new group
- Policy (migration 006) adds OR clause: `auth.uid() = user_id AND group.created_by = auth.uid()`

## Known TODOs
- Deploy `invite-member` Edge Function: `supabase functions deploy invite-member` (after setting secrets `RESEND_API_KEY` + `INVITE_FROM_EMAIL`)

## Expense Model Notes
- `Expense.payerID` CodingKey maps to `"paid_by"` (DB column name, not `"payer_id"`)
- `Expense` does NOT have an `updatedAt` field — DB column does not exist; do not add it to previews or tests
- `ExpenseService.createExpense` uses `add_expense_with_splits` RPC (atomic); splits are encoded as `[RPCSplitParam]` with CodingKeys `p_*` prefix
