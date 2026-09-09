//
//  XBillGroupGlyph.swift
//  xBill
//
//  ICON-07. A group's emoji was rendered six different ways:
//
//    XBillGroupCard, GroupDetailView, GroupChipView   → XBillAvatarPlaceholder(name: group.emoji)
//    GroupInviteView, QuickAddExpenseSheet, FriendsView → bare Text(group.emoji)
//
//  Neither was right. `XBillAvatarPlaceholder` exists to compute **initials** — it splits on spaces,
//  takes the first character of each of the first two words, uppercases, and falls back to "?". It
//  then applies `.foregroundStyle`, which a colour emoji glyph ignores outright. Feeding it an emoji
//  worked only because `first` of "🍕" happens to be "🍕" and `uppercased()` is a no-op on it —
//  coincidence, not design. The bare `Text` sites had no container at all, so the same value
//  rendered as a gradient circle on three screens and as loose text on three others.
//
//  This is the one place a group's emoji is drawn. `XBillAvatarPlaceholder` goes back to initials.
//

import SwiftUI

struct XBillGroupGlyph: View {
    let emoji: String
    var size: CGFloat = AppSpacing.xxl

    /// Groups created before the picker existed, or with the field cleared, can carry an empty
    /// string. A blank circle reads as a rendering failure, so fall back to a neutral mark.
    private var glyph: String {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "💠" : String(trimmed.prefix(1))
    }

    var body: some View {
        ZStack {
            Circle().fill(AppGradient.softPrimary)
            Circle()
                .fill(AppColors.textInverse.opacity(0.15))
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(x: size * 0.18, y: -size * 0.18)
            // No `.foregroundStyle` — a colour emoji ignores it, and setting one implies otherwise.
            Text(glyph)
                .font(.system(size: size * 0.46))
        }
        .frame(width: size, height: size)
        // Decorative: every call site places this beside the group's name.
        .accessibilityHidden(true)
    }
}

#Preview("Group glyphs") {
    HStack(spacing: AppSpacing.md) {
        XBillGroupGlyph(emoji: "🏖️")
        XBillGroupGlyph(emoji: "🍕", size: 56)
        XBillGroupGlyph(emoji: "", size: 40)      // empty → neutral fallback
        XBillGroupGlyph(emoji: "👨‍👩‍👧", size: 40)   // ZWJ sequence stays one grapheme
    }
    .padding()
}
