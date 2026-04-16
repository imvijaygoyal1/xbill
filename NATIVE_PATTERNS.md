# xBill — Apple Native Design Patterns
## Claude Code Instructions

These rules extend the base `CLAUDE.md`. When writing any SwiftUI code for xBill,
follow every convention below without exception. The goal: every screen must feel
like it shipped with iOS, not like a web app wrapped in SwiftUI.

---

## 1. Navigation & Structure

### NavigationStack (one per tab — already in CLAUDE.md)
```swift
// CORRECT — each tab owns its stack
TabView {
    NavigationStack { HomeView() }.tabItem { ... }
    NavigationStack { GroupListView() }.tabItem { ... }
}

// WRONG — never share one stack across tabs
NavigationStack {
    TabView { ... }
}
```

### Toolbar placement follows Apple conventions
```swift
// Primary action → .navigationBarTrailing
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button { viewModel.showAddExpense = true } label: {
            Image(systemName: "plus")
        }
    }
    // Destructive / cancel → .navigationBarLeading or .cancellationAction
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel) { dismiss() }
    }
}
```

### Sheet vs NavigationLink — pick the right one
| Use case | Pattern |
|---|---|
| Creating something new | `.sheet` or `.fullScreenCover` |
| Drilling into detail | `NavigationLink` |
| Confirmation / action | `.confirmationDialog` |
| Destructive confirm | `.alert` |
| Settings-style options | `NavigationLink` → detail view |

Never push a sheet onto a NavigationStack (no `NavigationLink` that opens a modal).

---

## 2. Lists & Tables

### Always use `List`, never `ScrollView + LazyVStack` for data rows
```swift
// CORRECT
List(expenses) { expense in
    ExpenseRowView(expense: expense)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.delete(expense)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
}
.listStyle(.insetGrouped)   // default for content lists
// .listStyle(.plain)        // for flat feeds (ActivityView)
// .listStyle(.sidebar)      // never — iPad sidebar only

// WRONG — loses swipe actions, context menus, and system animations
ScrollView {
    LazyVStack {
        ForEach(expenses) { ExpenseRowView(expense: $0) }
    }
}
```

### Section headers use system style — no custom styling
```swift
Section {
    ForEach(group.expenses) { ExpenseRowView(expense: $0) }
} header: {
    Text(group.name)   // plain Text — system applies uppercase + color automatically
}
```

### `.listRowSeparator` and `.listRowInsets` only when justified
```swift
// Acceptable: hide separator after last row in a section
.listRowSeparator(.hidden, edges: .bottom)

// Acceptable: remove insets for full-bleed cells (e.g., image banners)
.listRowInsets(EdgeInsets())
```

---

## 3. SF Symbols — the only icon system

### Rules
- **Always** use `Image(systemName:)` — never custom icon assets for UI chrome
- Match weight to context: `.regular` for toolbar, `.semibold` for tab bar, `.light` for decorative
- Use hierarchical or palette rendering for color — never flat tint on multicolor symbols

```swift
// Correct — weight matches toolbar context
Image(systemName: "plus")
    .fontWeight(.semibold)

// Correct — hierarchical rendering for balance indicator
Image(systemName: "arrow.up.arrow.down.circle.fill")
    .symbolRenderingMode(.hierarchical)
    .foregroundStyle(Color.brandPrimary)

// Correct — palette for two-tone semantic icons
Image(systemName: "checkmark.circle.fill")
    .symbolRenderingMode(.palette)
    .foregroundStyle(.white, Color.moneyPositive)

// WRONG — never tint a multicolor symbol with a flat color
Image(systemName: "dollarsign.circle.fill")
    .foregroundColor(.purple)  // kills the multicolor intent
```

### Category icons in xBill (CategoryIconView)
Map expense categories to SF Symbols. Use `.symbolVariant(.fill)` on selected state only.

| Category | Symbol |
|---|---|
| Food & Drink | `fork.knife` |
| Transport | `car.fill` |
| Accommodation | `house.fill` |
| Entertainment | `theatermasks.fill` |
| Shopping | `bag.fill` |
| Utilities | `bolt.fill` |
| Healthcare | `cross.fill` |
| Other | `ellipsis.circle.fill` |

---

## 4. Typography — system fonts only

```swift
// Navigation titles set by SwiftUI — never override
.navigationTitle("Groups")
.navigationBarTitleDisplayMode(.large)   // .inline for detail views

// Body content — always .body, .subheadline, .caption etc.
Text(expense.description)
    .font(.body)

Text(expense.category)
    .font(.subheadline)
    .foregroundStyle(.secondary)

// Monetary amounts — MUST use .monospacedDigit() to prevent layout shift
Text(expense.amount.formatted(.currency(code: group.currency)))
    .font(.title2.monospacedDigit())
    .foregroundStyle(Color.moneyPositive)

// NEVER hardcode point sizes except in DesignSystem files
// NEVER use UIFont directly in SwiftUI views
```

---

## 5. Colors & Materials

### Semantic colors — always prefer over hardcoded
```swift
// System semantics (auto dark/light)
.foregroundStyle(.primary)
.foregroundStyle(.secondary)
.foregroundStyle(.tertiary)
.background(.background)
.background(.secondarySystemBackground)  // via UIColor bridge if needed

// xBill brand (defined in XBillColors.swift)
Color.brandPrimary
Color.brandAccent
Color.moneyPositive
Color.moneyNegative
```

### Materials for floating UI elements
```swift
// Correct — use materials for overlays, not opaque fills
.background(.regularMaterial)    // cards, sheets, popovers
.background(.thinMaterial)       // subtle overlays
.background(.ultraThinMaterial)  // minimal blur (use sparingly)

// WRONG — hardcoded colors break dark mode
.background(Color.white)
.background(Color(hex: "#FFFFFF"))
```

### Tint propagation — set once at root
```swift
// xBillApp.swift — already established
ContentView()
    .tint(Color.brandPrimary)
// All buttons, toggles, progress views inherit this automatically
// Never override .tint locally unless semantically required (e.g., destructive red)
```

---

## 6. Controls — use system controls, never custom reimplementations

### Buttons
```swift
// Standard action
Button("Save") { viewModel.save() }
    .buttonStyle(.borderedProminent)  // primary CTA

Button("Cancel", role: .cancel) { dismiss() }
    .buttonStyle(.bordered)           // secondary

Button("Delete", role: .destructive) { viewModel.delete() }
// role: .destructive auto-applies red tint

// WRONG — custom button shapes/colors instead of system styles
Button("Save") { ... }
    .background(Color.brandPrimary)
    .foregroundColor(.white)
    .clipShape(RoundedRectangle(cornerRadius: 12))
// Exception: XBillButton in Components/ for branded full-width CTAs only
```

### Toggles, Steppers, Pickers
```swift
// Always use system controls — they animate and respect accessibility
Toggle("Recurring expense", isOn: $viewModel.isRecurring)

Picker("Split type", selection: $viewModel.splitType) {
    Text("Equal").tag(SplitType.equal)
    Text("Custom").tag(SplitType.custom)
    Text("Percentage").tag(SplitType.percentage)
}
.pickerStyle(.segmented)   // for ≤4 options
// .pickerStyle(.menu)      // for longer lists
// .pickerStyle(.wheel)     // for date/time only

Stepper("Members: \(count)", value: $count, in: 1...20)
```

### Text fields
```swift
// Use system TextField with appropriate keyboard/content type
TextField("Amount", value: $viewModel.amount, format: .number)
    .keyboardType(.decimalPad)
    .textContentType(.none)

TextField("Email", text: $viewModel.email)
    .keyboardType(.emailAddress)
    .textContentType(.emailAddress)
    .autocorrectionDisabled()
    .textInputAutocapitalization(.never)

// XBillTextField wraps these — use it for consistency, but it must
// pass through all the above modifiers, not suppress them
```

---

## 7. Sheets & Presentations

```swift
// Standard sheet
.sheet(isPresented: $showAddExpense) {
    AddExpenseView()
        .presentationDetents([.medium, .large])   // allow resize when appropriate
        .presentationDragIndicator(.visible)
}

// Full-screen for camera/scanner
.fullScreenCover(isPresented: $showReceiptScan) {
    ReceiptScanView()
}

// Confirmation dialog (NOT alert) for multi-option destructive actions
.confirmationDialog("Delete expense?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
    Button("Delete", role: .destructive) { viewModel.delete() }
    Button("Cancel", role: .cancel) {}
}

// Alert for single-action confirmations and errors (ErrorAlert pattern)
.alert(item: $viewModel.errorAlert) { error in
    Alert(title: Text(error.title), message: Text(error.message),
          dismissButton: .default(Text("OK")))
}
```

### Sheet navigation — never push inside a sheet
```swift
// CORRECT — NavigationStack inside the sheet
.sheet(isPresented: $show) {
    NavigationStack {
        AddExpenseView()
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { show = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { viewModel.save() }
                }
            }
    }
}
```

---

## 8. Loading & Empty States

### Loading — ProgressView, never custom spinners
```swift
// Inline loading
if viewModel.isLoading {
    ProgressView()           // system spinner
} else {
    ContentView()
}

// Over content (LoadingOverlay component)
.overlay {
    if viewModel.isLoading {
        LoadingOverlay()     // xBill component wrapping ProgressView + .regularMaterial
    }
}
```

### Empty states — ContentUnavailableView (iOS 17+)
```swift
// CORRECT — use system ContentUnavailableView
ContentUnavailableView {
    Label("No Expenses", systemImage: "creditcard")
} description: {
    Text("Add your first expense to get started.")
} actions: {
    Button("Add Expense") { viewModel.showAddExpense = true }
        .buttonStyle(.borderedProminent)
}

// EmptyStateView in Components/ must wrap ContentUnavailableView internally
// WRONG — custom empty state with hand-drawn layout
VStack {
    Image(systemName: "creditcard").font(.system(size: 60))
    Text("No Expenses").font(.title)
    Text("Add your first...").foregroundColor(.gray)
}
```

---

## 9. Swipe Actions & Context Menus

```swift
// Swipe actions — primary destructive action on trailing edge
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button(role: .destructive) {
        viewModel.deleteExpense(expense)
        HapticManager.error()   // error haptic for destructive
    } label: {
        Label("Delete", systemImage: "trash")
    }
}

// Non-destructive on leading
.swipeActions(edge: .leading) {
    Button {
        viewModel.toggleSettled(expense)
        HapticManager.success()
    } label: {
        Label("Settled", systemImage: "checkmark.circle")
    }
    .tint(Color.moneyPositive)
}

// Context menus for power users (long-press)
.contextMenu {
    Button { viewModel.edit(expense) } label: {
        Label("Edit", systemImage: "pencil")
    }
    Button { viewModel.share(expense) } label: {
        Label("Share", systemImage: "square.and.arrow.up")
    }
    Divider()
    Button(role: .destructive) { viewModel.delete(expense) } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

---

## 10. Animations

### Use system animations — never custom spring math
```swift
// CORRECT
withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
    viewModel.showDetail = true
}

withAnimation(.easeInOut(duration: 0.2)) {
    isExpanded.toggle()
}

// Matched geometry for shared-element transitions
.matchedGeometryEffect(id: expense.id, in: namespace)

// WRONG — explicit duration/curve on UI state changes
withAnimation(Animation.linear(duration: 0.5)) { ... }

// NEVER animate layout constraints — use transition modifiers
.transition(.move(edge: .bottom).combined(with: .opacity))
```

### `symbolEffect` for SF Symbols (iOS 17+)
```swift
Image(systemName: isSettled ? "checkmark.circle.fill" : "circle")
    .symbolEffect(.bounce, value: isSettled)
    .contentTransition(.symbolEffect(.replace))
```

---

## 11. Accessibility (non-negotiable)

```swift
// Every interactive element needs a label
Image(systemName: "plus")
    .accessibilityLabel("Add expense")

// Group related elements
VStack { ... }
    .accessibilityElement(children: .combine)

// Custom actions for swipe-only features
.accessibilityAction(named: "Delete") {
    viewModel.delete(expense)
}

// Dynamic Type — never clamp text sizes
// CORRECT — let the system scale
Text(title).font(.headline)

// WRONG — prevents accessibility text size from working
Text(title).font(.system(size: 17))  // hardcoded sizes don't scale
```

---

## 12. Haptics (from base CLAUDE.md — reinforced here)

Always use `HapticManager` — never call `UIFeedbackGenerator` directly in views.

| Trigger | Haptic |
|---|---|
| Expense saved, group created, settlement marked paid | `HapticManager.success()` |
| Category selected, sheet triggered | `HapticManager.selection()` |
| Form validation error, failed network call | `HapticManager.error()` |
| Tab bar tap (system handles) | none needed |
| Toggle, stepper (system handles) | none needed |

---

## 13. Safe Area & Layout

```swift
// NEVER ignore safe areas for content
// CORRECT — content respects safe area by default
ScrollView { ... }

// Only ignore safe area for backgrounds/decorative elements
Color.brandSurface
    .ignoresSafeArea()   // background extends edge-to-edge

// Bottom sheet / FAB — always account for home indicator
VStack {
    Spacer()
    FABButton { viewModel.showAddExpense = true }
        .padding(.bottom, 16)   // system adds safe area on top of this
}

// Keyboard avoidance — automatic in SwiftUI, don't fight it
// If a form is clipped by keyboard, wrap in ScrollView, not custom offset
```

---

## 14. Performance Patterns

```swift
// Use `task` for async work tied to view lifetime — not onAppear + Task { }
.task {
    await viewModel.loadExpenses()
}

// Use `task(id:)` to re-run when a dependency changes
.task(id: selectedGroup.id) {
    await viewModel.loadExpenses(for: selectedGroup)
}

// LazyVStack only inside ScrollView, only for truly unbounded lists
// (List handles this automatically — prefer List)

// Images — always use AsyncImage with a placeholder
AsyncImage(url: avatarURL) { image in
    image.resizable().scaledToFill()
} placeholder: {
    Color.brandSurface   // not ProgressView — prevents layout jump
}
.frame(width: 40, height: 40)
.clipShape(Circle())
```

---

## 15. What NOT to do (anti-patterns)

| Anti-pattern | Apple-native replacement |
|---|---|
| Custom `UIViewRepresentable` alert | `.alert(item:)` modifier |
| `GeometryReader` for responsive sizing | `Layout` protocol or `ViewThatFits` |
| `ZStack` for overlays on lists | `.overlay {}` modifier |
| `UINavigationController` push in SwiftUI | `NavigationStack` with `NavigationLink` |
| `DispatchQueue.main.async` in ViewModels | `@MainActor` on ViewModel class |
| `ObservableObject` + `@Published` | `@Observable` macro (already in CLAUDE.md) |
| Custom tab bar | Native `TabView` |
| Hardcoded corner radius numbers in views | `XBillLayout.radius.*` tokens |
| `Color(red:green:blue:)` in views | `XBillColors` tokens |
| `UIScreen.main.bounds` for sizing | `GeometryReader` or layout modifiers |

---

## Quick checklist before committing any SwiftUI view

- [ ] Uses `List` not `ScrollView+LazyVStack` for data rows
- [ ] All icons are SF Symbols
- [ ] Monetary `Decimal` values use `.monospacedDigit()`
- [ ] No hardcoded colors — only `XBillColors` tokens or semantic system colors
- [ ] Sheets contain a `NavigationStack` with `.cancellationAction` / `.confirmationAction` toolbar
- [ ] Empty states use `ContentUnavailableView`
- [ ] Async work uses `.task` modifier, not `onAppear + Task {}`
- [ ] `@MainActor` on every ViewModel — no `DispatchQueue.main.async`
- [ ] Haptics called via `HapticManager` at correct trigger points
- [ ] Accessibility labels on all icon-only buttons
