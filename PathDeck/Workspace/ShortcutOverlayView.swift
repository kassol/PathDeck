import SwiftUI

/// 长按 ⌘ 呼出的快捷键速查浮窗（Shortcut Overlay）。
/// 内容完全由 ShortcutRegistry 派生；纯展示，不参与命中测试。
struct ShortcutOverlayView: View {
    private static let columnWidth: CGFloat = 204

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(Array(ShortcutRegistry.overlayColumns.enumerated()), id: \.offset) { _, groups in
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.self) { group in
                        groupSection(group)
                    }
                }
                .frame(width: Self.columnWidth, alignment: .topLeading)
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
        )
        .shadow(color: .black.opacity(0.22), radius: 28, y: 10)
        .accessibilityIdentifier("shortcutOverlay")
    }

    @ViewBuilder
    private func groupSection(_ group: ShortcutGroup) -> some View {
        let specs = ShortcutRegistry.overlaySpecs.filter { $0.group == group }
        if !specs.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(group.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.bottom, 2)
                ForEach(specs) { spec in
                    shortcutRow(spec)
                }
            }
        }
    }

    private func shortcutRow(_ spec: ShortcutSpec) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if let badge = spec.context.badge {
                    Text(badge)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 3) {
                ForEach(Array(spec.keys.enumerated()), id: \.offset) { _, token in
                    Text(token)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 12)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
            }
        }
    }
}
