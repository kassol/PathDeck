import Testing
import Foundation
@testable import PathDeck

struct TerminalAttributionTests {
    private func snap(_ id: UUID, cwd: String?, lastActive: TimeInterval) -> TerminalActivitySnapshot {
        TerminalActivitySnapshot(
            id: id,
            cwd: cwd.map { URL(fileURLWithPath: $0) },
            lastActive: Date(timeIntervalSince1970: lastActive)
        )
    }

    @Test func attributeMatchesSingleSessionUnderCwd() {
        let id = UUID()
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj/a.txt",
            snapshots: [snap(id, cwd: "/work/proj", lastActive: 100)]
        )
        #expect(result == id)
    }

    @Test func attributeMultiSessionPicksMostRecentlyActive() {
        let early = UUID(), late = UUID()
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj/a.txt",
            snapshots: [
                snap(early, cwd: "/work/proj", lastActive: 100),
                snap(late, cwd: "/work/proj", lastActive: 200),
            ]
        )
        #expect(result == late)
    }

    @Test func attributeNestedCwdPrefersDeepest() {
        // 决策点 1：parent cwd 更浅但更晚活跃，child cwd 更深但更早 → 取最深 child。
        let parent = UUID(), child = UUID()
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj/a.txt",
            snapshots: [
                snap(parent, cwd: "/work", lastActive: 200),
                snap(child, cwd: "/work/proj", lastActive: 100),
            ]
        )
        #expect(result == child)
    }

    @Test func attributeNoSessionUnderCwdReturnsNil() {
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj/a.txt",
            snapshots: [snap(UUID(), cwd: "/other", lastActive: 100)]
        )
        #expect(result == nil)
    }

    @Test func attributeNilCwdReturnsNil() {
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj/a.txt",
            snapshots: [snap(UUID(), cwd: nil, lastActive: 100)]
        )
        #expect(result == nil)
    }

    @Test func attributeEmptySnapshotsReturnsNil() {
        let result = TerminalAttribution.attribute(eventPath: "/work/proj/a.txt", snapshots: [])
        #expect(result == nil)
    }

    @Test func attributePrefixBoundaryNotFooledBySiblingDir() {
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj-backup/a.txt",
            snapshots: [snap(UUID(), cwd: "/work/proj", lastActive: 100)]
        )
        #expect(result == nil)
    }

    @Test func attributeEventEqualsCwdItself() {
        let id = UUID()
        let result = TerminalAttribution.attribute(
            eventPath: "/work/proj",
            snapshots: [snap(id, cwd: "/work/proj", lastActive: 100)]
        )
        #expect(result == id)
    }
}
