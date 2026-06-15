import SwiftUI

struct ChangeListView: View {
    let events: [ChangeEvent]
    var versionedPaths: Set<String> = []
    var hiddenCount: Int = 0
    var onRulesChanged: (() -> Void)?
    var onNavigate: ((ChangeEvent) -> Void)?

    @State private var filter: ChangeEventType?
    @State private var showIgnoreRules = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                FilterBar(filter: $filter)
                Button {
                    showIgnoreRules.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("忽略规则")
                .popover(isPresented: $showIgnoreRules) {
                    IgnoreRulesPopover {
                        onRulesChanged?()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            let filtered = filteredEvents
            let groups = ChangeEvent.grouped(filtered)

            if groups.isEmpty {
                Text("无最近变化")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.group) { section in
                        Section {
                            ForEach(section.events) { event in
                                ChangeRow(event: event, hasVersion: versionedPaths.contains(event.path))
                                    .contentShape(Rectangle())
                                    .onTapGesture { onNavigate?(event) }
                            }
                        } header: {
                            Text("\(section.group.label) (\(section.events.count))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }

            if hiddenCount > 0 {
                Text("已隐藏 \(hiddenCount) 项")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
    }

    private var filteredEvents: [ChangeEvent] {
        guard let filter else { return events }
        return events.filter { $0.eventType == filter }
    }
}

// MARK: - Ignore Rules Popover

private struct IgnoreRulesPopover: View {
    var onRulesChanged: () -> Void

    @State private var userPatterns: [String] = IgnoreRules.userPatterns
    @State private var newPattern: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("忽略规则")
                .font(.system(size: 12, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(IgnoreRules.defaultPatterns, id: \.self) { pattern in
                        Text(pattern)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !userPatterns.isEmpty {
                        Divider().padding(.vertical, 2)
                        ForEach(userPatterns, id: \.self) { pattern in
                            HStack {
                                Text(pattern)
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Button {
                                    removePattern(pattern)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            Divider()

            HStack(spacing: 4) {
                TextField("glob 模式，如 *.log", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { addPattern() }
                Button("添加") { addPattern() }
                    .font(.system(size: 11))
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !userPatterns.contains(trimmed) else { return }
        userPatterns.append(trimmed)
        IgnoreRules.userPatterns = userPatterns
        newPattern = ""
        onRulesChanged()
    }

    private func removePattern(_ pattern: String) {
        userPatterns.removeAll { $0 == pattern }
        IgnoreRules.userPatterns = userPatterns
        onRulesChanged()
    }
}

// MARK: - Filter Bar

private struct FilterBar: View {
    @Binding var filter: ChangeEventType?

    var body: some View {
        HStack(spacing: 4) {
            FilterChip(label: "全部", isSelected: filter == nil) {
                filter = nil
            }
            FilterChip(label: "新增", color: .green, isSelected: filter == .added) {
                filter = .added
            }
            FilterChip(label: "修改", color: .orange, isSelected: filter == .modified) {
                filter = .modified
            }
            FilterChip(label: "删除", color: .red, isSelected: filter == .deleted) {
                filter = .deleted
            }
            Spacer()
        }
    }
}

private struct FilterChip: View {
    let label: String
    var color: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? color.opacity(0.15) : Color.clear)
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Change Row

private struct ChangeRow: View {
    let event: ChangeEvent
    var hasVersion: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.eventType.iconName)
                .foregroundStyle(event.eventType.color)
                .frame(width: 16)
            Text(event.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if hasVersion {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("已保存版本快照")
            }
            if event.terminalSessionID != nil {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("终端活跃期间产生")
            }
            Text(event.timestamp, style: .relative)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .font(.system(size: 12))
    }
}

extension ChangeEventType {
    var iconName: String {
        switch self {
        case .added: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        }
    }
}
