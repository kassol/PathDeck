import SwiftUI

/// Command Palette（命令面板，⌘⇧P）：窗口内命令搜索浮层。
/// 内容完全派生自 ShortcutRegistry 命令表；全量可搜，不可用置灰（↑↓ 跳过、↩ 无效）；
/// 显隐与焦点还原由 WorkspaceController.show/dismissCommandPalette 管理。
struct CommandPaletteView: View {
    let controller: WorkspaceController

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var inputFocused: Bool

    private var results: [ShortcutSpec] {
        CommandPaletteFilter.rank(query: query, specs: ShortcutRegistry.paletteSpecs)
    }

    var body: some View {
        let results = self.results
        VStack(spacing: 0) {
            TextField(String(localized: "Type a command…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .onSubmit { execute(in: results) }
                .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                .onKeyPress(.escape) { controller.dismissCommandPalette(); return .handled }

            Divider()

            if results.isEmpty {
                Text("No matching commands")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, spec in
                                commandRow(spec, isSelected: index == selectedIndex)
                                    .id(spec.id)
                                    .onTapGesture {
                                        selectedIndex = index
                                        execute(in: results)
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, index in
                        if results.indices.contains(index) {
                            proxy.scrollTo(results[index].id)
                        }
                    }
                }
            }
        }
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
        )
        .shadow(color: .black.opacity(0.22), radius: 28, y: 10)
        .onAppear {
            inputFocused = true
            selectedIndex = firstEnabledIndex(in: results, from: 0, step: 1) ?? 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = firstEnabledIndex(in: self.results, from: 0, step: 1) ?? 0
        }
        .accessibilityIdentifier("commandPalette")
    }

    private func commandRow(_ spec: ShortcutSpec, isSelected: Bool) -> some View {
        let enabled = spec.isEnabled(controller)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.title)
                    .font(.system(size: 13))
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
        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }

    /// ↑↓ 移动选中，跳过 disabled 条目；到端循环。
    private func move(_ step: Int, in results: [ShortcutSpec]) {
        guard !results.isEmpty else { return }
        let start = (selectedIndex + step + results.count) % results.count
        if let next = firstEnabledIndex(in: results, from: start, step: step) {
            selectedIndex = next
        }
    }

    private func firstEnabledIndex(in results: [ShortcutSpec], from start: Int, step: Int) -> Int? {
        guard !results.isEmpty else { return nil }
        var index = max(0, min(start, results.count - 1))
        for _ in 0..<results.count {
            if results[index].isEnabled(controller) { return index }
            index = (index + step + results.count) % results.count
        }
        return nil
    }

    private func execute(in results: [ShortcutSpec]) {
        guard results.indices.contains(selectedIndex) else { return }
        let spec = results[selectedIndex]
        guard spec.isEnabled(controller) else { return }
        controller.dismissCommandPalette()
        // 先还焦点再执行：responder-chain 型命令（Copy 等）需命中文件列表而非输入框。
        DispatchQueue.main.async { spec.action?(controller) }
    }
}
