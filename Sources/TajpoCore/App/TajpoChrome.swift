import SwiftUI

public enum TajpoTheme {
    public static let copper = Color(red: 0.773, green: 0.416, blue: 0.227)
    public static let copperSoft = Color(red: 0.878, green: 0.541, blue: 0.333)
    public static let paper = Color(red: 0.953, green: 0.922, blue: 0.882)
    public static let ink = Color(red: 0.078, green: 0.067, blue: 0.055)
    public static let sage = Color(red: 0.490, green: 0.604, blue: 0.455)
    public static let terracotta = Color(red: 0.769, green: 0.361, blue: 0.290)
}

struct StatusPill: View {
    let text: String
    var isError = false
    var isWorking = false

    var body: some View {
        HStack(spacing: 6) {
            if isWorking {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(isError ? TajpoTheme.terracotta : TajpoTheme.sage)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(isError ? TajpoTheme.terracotta : .secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.35), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

struct ActionChip: View {
    let action: RewriteAction
    let selected: Bool
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.caption.weight(.semibold))
                Text(action.shortcutDigit)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selected ? TajpoTheme.copper.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? TajpoTheme.copper.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(action.subtitle)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
