# xBill Design System Redesign Plan

Last updated: 2026-05-04

## Goal

Redesign xBill with a playful premium fintech visual style while applying Manhattan-style product discipline: strict tokens, reusable components, accessibility, consistency, and no one-off screen styling.

xBill helps users split shared expenses with friends, roommates, and groups.

Brand line: **Split expenses, not friendships.**

## Design Principles

- One canonical design system lives under `xBill/DesignSystem`.
- Screens must not define hardcoded colors, font sizes, spacing, radii, shadows, or gradients.
- Repeated UI must be extracted into reusable components before screen migration.
- Components own their visual states: normal, selected, disabled, loading, error, empty, and pressed where applicable.
- Screens own data, navigation, and composition only.
- Light and dark mode are adaptive through tokens and components, not duplicate screens.
- Financial semantics are consistent everywhere: green means the user is owed money, red means the user owes money.
- QR codes are always black on white in both color schemes.
- Tap targets must be at least 44pt.
- Text must remain readable with Dynamic Type and in both color schemes.

## Canonical Structure

```text
xBill/
  DesignSystem/
    Tokens/
      AppColors.swift
      AppTypography.swift
      AppSpacing.swift
      AppRadius.swift
      AppShadow.swift
      AppGradient.swift
    Components/
      XBillScreenBackground.swift
      XBillHeroCard.swift
      XBillBalanceCard.swift
      XBillActionCard.swift
      XBillGroupCard.swift
      XBillExpenseRow.swift
      XBillFriendRow.swift
      XBillProfileCard.swift
      XBillEmptyState.swift
      XBillPrimaryButton.swift
      XBillSecondaryButton.swift
      XBillBlackButton.swift
      XBillTextField.swift
      XBillSearchBar.swift
      XBillSegmentedControl.swift
      XBillTabBar.swift
      XBillFloatingAddButton.swift
      XBillAvatarStack.swift
      XBillIconPickerGrid.swift
      XBillQRCodeCard.swift
      HomeHeader.swift
  Helpers/
    GreetingHelper.swift
    BalanceMessageHelper.swift
  PreviewData/
    PreviewData.swift
```

Existing `xBill/Core/DesignSystem` and `xBill/Views/Components` types should be migrated into, wrapped by, or aliased to the canonical system. Do not create a third styling layer.

## Tokens

### Light Colors

| Role | Hex |
|---|---|
| primary | `#6C35FF` |
| primaryDark | `#4B16D8` |
| primaryLight | `#B79CFF` |
| background | `#F7F3FF` |
| surface | `#FFFFFF` |
| surfaceSoft | `#F1ECFF` |
| textPrimary | `#111111` |
| textSecondary | `#77727F` |
| success | `#2DBE8D` |
| error | `#FF5C5C` |
| warning | `#FF9F43` |
| blackNav | `#111111` |
| border | `#E7E0F7` |

### Dark Colors

| Role | Hex |
|---|---|
| backgroundDark | `#0F0D16` |
| surfaceDark | `#1A1724` |
| surfaceSoftDark | `#242033` |
| textPrimaryDark | `#FFFFFF` |
| textSecondaryDark | `#B9B3C9` |
| borderDark | `#332D45` |
| blackNavDark | `#08070C` |

### Gradients

- Hero gradient light: `#8B5CFF -> #6C35FF -> #4B16D8`
- Hero gradient dark: `#9B6CFF -> #6C35FF -> #3A13B8`
- Gradients must live in `AppGradient.swift`, not in screens.

### Typography

Use SF Pro system fonts through tokenized `Font` values.

| Role | Size | Weight |
|---|---:|---|
| display | 32pt | bold |
| h1 | 28pt | bold |
| h2 | 22pt | semibold |
| title | 17pt | semibold |
| body | 15pt | regular |
| caption | 13pt | regular |

Amounts should use monospaced digits to avoid layout shift.

### Spacing

| Token | Value |
|---|---:|
| xs | 4 |
| sm | 8 |
| md | 16 |
| lg | 24 |
| xl | 32 |
| xxl | 48 |

Add a control-height token for the 44pt minimum tap target.

### Radius

| Token | Value |
|---|---:|
| sm | 8 |
| md | 12 |
| lg | 16 |
| xl | 20 |
| xxl | 24 |
| hero | 28 |
| pill | 999 |

## Component Requirements

- Buttons expose primary, secondary, black, destructive, disabled, and loading states.
- Text fields expose normal, focused, disabled, and error states.
- Search uses `XBillSearchBar`, not ad hoc `HStack` search fields.
- Segmented controls use `XBillSegmentedControl`, not screen-local `Picker` styling.
- Cards use tokenized surfaces, borders, radius, and shadow.
- Empty states are never custom per screen.
- Avatar stacks handle overlap, max visible count, accessibility labels, and empty fallback.
- QR cards force black QR content on a white surface regardless of color scheme.
- Tab bar owns black/near-black styling, selected state, badge support, and 44pt targets.
- Visual assets are SwiftUI-only and reusable. Do not add external PNG/JPG assets for logo marks, receipts, wallet art, split-bill illustrations, avatars, category icons, empty states, or QR frames.
- Page titles use `XBillPageHeader` or `HomeHeader`; do not add custom screen-local title stacks.
- Screen scrolling uses `XBillScreenContainer` / `XBillScrollView` where practical, with content bottom padding for tab bars and sticky CTAs.

## Implementation Update — 2026-05-04 UI Hardening

Completed fixes:

- `AppSpacing` includes `tabBarHeight` and `floatingActionBottomPadding` so screens do not rely on one-off bottom padding.
- `AppTypography` includes icon, tab label, and badge tokens for tab/FAB chrome.
- Canonical buttons expose disabled and loading behavior.
- Home density was tightened: smaller personalized header, reduced balance hero padding, smaller group chips, and tokenized FAB/content bottom spacing.
- Home dashboard was sharpened in place: calmer surface-based balance card, reusable metric cards, tokenized section headers/status chips, more complete group cards, icon-led settled messaging, and polished surface-based bottom tabs.
- Groups was sharpened in place: custom one-off title/button/section/card styling was replaced with `XBillPageHeader`, `XBillCircularIconButton`, `XBillSearchBar`, `XBillSectionHeader`, `XBillGroupCard`, and `XBillArchivedRow`; archived content now uses a clear reusable row. Main app navigation uses the native iOS tab bar, not the custom `XBillTabBar`, to avoid duplicate bottom navigation and preserve platform behavior.
- Friends was sharpened in place: duplicated empty-state art was replaced with one `XBillEmptyState` using `XBillIllustrationCard`; the screen now uses `XBillScreenHeader`, `XBillScrollView`, `XBillSectionHeader`, and enhanced `XBillFriendRow` cards while preserving Add Friend, Add IOU, pending requests, refresh, and friend-detail navigation.
- Top navigation chrome now uses adaptive `AppColors.background`; near-black styling is reserved for the custom bottom tab bar.
- Group Details uses `XBillSegmentedControl` for Expenses/Balances/Settle Up.
- Add Expense uses a sticky full-width `Save Expense` action and 44pt+ category/share controls.
- Add IOU was migrated from default `Form` styling to xBill screen background, amount hero, canonical cards, `XBillSegmentedControl`, and sticky `Save IOU`.
- Add Friend request controls now meet 44pt tap target requirements.
- Friends empty state no longer shows the Add IOU FAB over the Add Friend CTA.
- Added SwiftUI-only reusable visuals: logo mark, receipt icon, split-bill illustration, empty-state illustration, wallet illustration, avatar placeholder, category icon, and QR placeholder frame.
- Applied visuals across onboarding, Home hero cards, Groups cards/chips, Friends and Notifications empty states, Profile avatar fallback, New Group icon picker, Group Details avatar stack/category filters, Add Expense category chips, Add Friend contact rows, Add IOU amount card, and QR code card frame.
- Added `XBillIllustrationKit`, `XBillPageHeader`, `XBillScreenContainer`, and `XBillScrollView` to standardize visible illustration scale, screen titles, scroll spacing, and sticky bottom CTA clearance.
- Normalized main-tab title behavior for Home, Groups, Friends, Notifications, and Profile; modal/detail/form screens now use consistent custom headers/back placement where migrated.

Validation performed:

- `xcodegen generate`
- Debug simulator build with `xcodebuild` on simulator `DA97985A-F7CC-44F6-8281-9DD24C22B978`
- Installed and launched the app on the simulator
- Light-mode screenshot spot check: Groups tab
- Dark-mode screenshot spot checks: Friends empty state, Notifications empty state
- Final full build after documentation updates: succeeded
- Login UI regression validation: `xcodebuild test -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -only-testing:xBillUITests/OnboardingUITests` passed 6 tests on 2026-05-04, including auth header identifiers and visible illustration accessibility identifiers
- Visual asset system validation: `xcodegen generate`; Debug simulator build succeeded; installed and launched on simulator `DA97985A-F7CC-44F6-8281-9DD24C22B978`
- Header/scroll consistency validation: `xcodegen generate`; Debug simulator build succeeded; installed and launched on simulator `DA97985A-F7CC-44F6-8281-9DD24C22B978`
- Home dashboard validation: `xcodegen generate`; Debug simulator build succeeded; `xcodebuild test -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -only-testing:xBillTests` passed on 2026-05-04; installed/launched on simulator and screenshot-checked Home for text overlap and add-button placement. `swiftformat` and `swiftlint` were not installed in the environment.
- Groups screen validation: `xcodegen generate`; Debug simulator build succeeded; `xcodebuild test -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -only-testing:xBillTests` passed on 2026-05-05; `xcodebuild test -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -only-testing:xBillUITests/GroupFlowUITests` passed on 2026-05-05 with 16 executed tests, 2 expected simulator-dependent skips for SwiftUI context-menu/detail presentation exposure, and 0 failures. UI test runner cleanup was performed after test execution. `swiftformat` and `swiftlint` were not installed in the environment.

Remaining visual debt:

- Legacy `Color.*`, `XBillSpacing`, and `.xbill*` typography usages still exist during compatibility migration.
- Onboarding remains post-sign-in feature education; a true pre-auth onboarding/sign-in landing sequence needs a product-flow decision before implementation.
- Receipt scan/review and stats screens still need the same hardcoded-style audit pass as the main app shell.

## Helper Behavior

`GreetingHelper`:

- 5-11: `Good morning`
- 12-16: `Good afternoon`
- 17-21: `Good evening`
- Else: `Welcome back`

`BalanceMessageHelper`:

- balance > 0: `You're owed money`
- balance < 0: `You've got balances to settle`
- balance == 0: `All settled. Nice!`

Helpers should keep pure, icon-free text; visual status icons belong in reusable UI components.

`HomeHeader`:

- Shows `Hi, {firstName}` from profile data.
- Shows the dynamic greeting.
- Optionally shows the balance message.
- Must not use a static hardcoded name.

## Screen Migration Scope

### Onboarding

Use xBill logo, tagline, illustration area, `Get Started`, `Sign In`, and legal text. Keep onboarding completion logic intact.

### Sign In

Use compact branded header, rounded auth card, Apple sign-in black button, email continuation, rounded email/password form, primary sign-in button, create-account link, forgot-password link, and accessible legal links. Preserve email confirmation and password reset behavior.

### Home

Use `HomeHeader`, purple balance hero card, quick action card, group list, invite card, floating add button, and tab bar. Preserve realtime refresh, archived group data, quick actions, and navigation.

### Groups

Use search bar, active groups section, archived groups section, rounded group cards, and consistent bottom navigation. Preserve delete, archive, unarchive, and Spotlight indexing behavior.

### Friends

Use reusable screen header and tokenized friend rows when available. Empty state uses `XBillEmptyState` with a single `XBillIllustrationCard` and Add Friend button. Preserve pending requests, IOUs, contact import, QR deep-link preloading, and friend detail navigation.

### Notifications

Use `XBillEmptyState` when empty. Preserve unread state, grouped dates, badges, mark-all-read behavior, and notification store integration.

### Profile

Use top profile card with avatar, name, email, edit button, QR button, stats cards, payment handles, settings rows, and bottom nav. Preserve sign out, account deletion, notification toggles, app lock, legal links, and profile stats.

### New Group

Use rounded form cards, group name field, icon picker, currency selector, invite-by-email field, and create button. Preserve optional invite email behavior.

### Group Details

Use title, avatar stack, balance hero card, segmented control for Expenses/Balances/Activity, search bar, expense list or empty state, and Add Expense button. Preserve export, invite, archive/unarchive, stats, recurring expense creation, settlements, filters, and search.

### Add Expense

Use prominent amount field, paid-by selector, split-between selector, category chips, notes field, recurrence, currency conversion, receipt scan, validation, and sticky Save Expense button.

### Add Friend

Use search field, Import from Contacts, suggested friends list, Add/Pending buttons, invite non-users, and empty state if no results.

### Add IOU

Use prominent amount field, segmented control for `They owe me` and `I owe them`, person selector, reason field, note field, and sticky Save IOU button. Preserve friend picker and email fallback.

### Edit Profile

Use avatar card, display name field, email display if available, and Save button. Prefer extracting the existing internal edit sheet into a dedicated view.

### QR Code

Use centered QR card, explanatory text, and share button. QR image must remain black on white in light and dark mode.

## Suggested Rollout

1. **Stabilize the design-system foundation.** Add/adapt tokens, dark-mode behavior, gradients, control heights, avatar sizes, and temporary compatibility aliases.
2. **Build components with previews.** Create canonical components and light/dark previews using `PreviewData`.
3. **Migrate shared chrome.** Update app background, nav/tint conventions, tab bar, floating add button, buttons, fields, cards, empty states, rows, and avatar components.
4. **Migrate auth/onboarding.** These validate visual identity without touching complex financial flows.
5. **Migrate main tabs.** Home, Groups, Friends, Notifications, and Profile.
6. **Migrate creation/detail flows.** New Group, Group Details, Add Expense, Add Friend, Add IOU, Edit Profile, QR Code.
7. **Audit and clean up.** Remove legacy styling aliases where possible, search for hardcoded styling, verify light/dark, Dynamic Type, tap targets, and compile.

## Audit Checklist

- No `Color(hex:)`, raw `Color.white`, raw `Color.black`, direct color literals, or hardcoded gradients in screens.
- No screen-local font sizes, spacing values, radius values, or shadow definitions.
- Repeated UI uses design-system components.
- Light and dark mode are supported by tokens/components.
- All primary tap targets are at least 44pt.
- QR code is black on white.
- Empty states exist for empty Home, Groups, Friends, Notifications, Group Details, Add Friend results, and IOU-related flows.
- App compiles and existing navigation/data flows are preserved.

Suggested search:

```bash
rg "Color\\(hex|Color\\.white|Color\\.black|Color\\.red|Color\\.green|\\.font\\(\\.system|cornerRadius: [0-9]|\\.padding\\([0-9]|\\.shadow\\(" xBill/Views xBill/DesignSystem
```
