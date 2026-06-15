import SwiftUI
import AppKit

@main
struct PathDeckApp: App {
    static let terminalWindowID = "terminal-smoke"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        ShellIntegration.prepare()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TerminalCommands()
            FileCommands()
            ViewCommands()
        }

        Settings {
            SettingsView()
        }

        // S2 冒烟：独立终端窗口，与文件列表主窗口隔离。
        Window("Terminal (Smoke)", id: Self.terminalWindowID) {
            TerminalSmokeView()
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 800, height: 500)
    }
}

/// App 委托：统一 URL Scheme 与 Open With 的入口（`application(_:open:)`），并注册 Finder Services。
///
/// URL 一律走 `application(_:open:)`，不挂 `.onOpenURL`——规避 `WindowGroup` 复制窗口 quirk 与双触发。
/// 所有入口经 `AppRouter` 投递路由，由 `ContentView` 消费。`LSMultipleInstancesProhibited` 保证唤起复用本进程。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicesProvider
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                // CFBundleDocumentTypes「打开方式」投递的文件夹 file URL → .open
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(
                    atPath: url.path(percentEncoded: false), isDirectory: &isDir
                ), isDir.boolValue else { continue }
                AppRouter.shared.request(.open(url.standardizedFileURL))
            } else if let route = URLSchemeHandler.route(for: url) {
                AppRouter.shared.request(route)
            }
        }
    }
}

/// 终端菜单命令。
private struct TerminalCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceModel) private var model
    @FocusedValue(\.sendPathAction) private var sendPathAction

    var body: some Commands {
        CommandMenu("终端") {
            Button("切换底部面板") {
                model?.isBottomPanelVisible.toggle()
            }
            .keyboardShortcut("`", modifiers: .control)

            Button("发送路径到终端") {
                guard let urls = model?.selectedURLs, !urls.isEmpty else { return }
                sendPathAction?(urls)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(model?.selectedURLs.isEmpty ?? true)

            Divider()

            Button("打开终端（冒烟）") {
                openWindow(id: PathDeckApp.terminalWindowID)
            }
            .keyboardShortcut("t", modifiers: [.control, .option, .command])
        }
    }
}

/// 文件操作菜单命令：打开文件夹 + 最近打开 + 新建文件夹 + 废纸篓。
private struct FileCommands: Commands {
    @FocusedValue(\.workspaceModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开文件夹…") {
                model?.openFolder()
            }
            .keyboardShortcut("o")

            Menu("打开最近文件夹") {
                let recent = RecentFolders.shared.items
                if recent.isEmpty {
                    Text("无最近记录")
                } else {
                    ForEach(recent, id: \.self) { url in
                        Button(abbreviatedPath(url)) {
                            model?.navigate(to: url)
                        }
                    }
                    Divider()
                    Button("清除菜单") {
                        RecentFolders.shared.clear()
                    }
                }
            }

            Divider()

            Button("新建文件夹") {
                model?.newFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("文件操作") {
            Button("移到废纸篓") {
                model?.trashItems()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model?.selectedURLs.isEmpty ?? true)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

/// 显示菜单命令：隐藏文件切换 + 复制路径。
private struct ViewCommands: Commands {
    @FocusedValue(\.workspaceModel) private var model
    @FocusedValue(\.togglePreviewPaneAction) private var togglePreviewPane

    var body: some Commands {
        CommandMenu("显示") {
            Button("切换预览面板") {
                togglePreviewPane?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(model?.showHidden == true ? "隐藏隐藏文件" : "显示隐藏文件") {
                model?.toggleHidden()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("查找…") {
                model?.isSearching = true
            }
            .keyboardShortcut("f")
        }
        CommandGroup(after: .pasteboard) {
            Button("复制当前路径") {
                model?.copyCurrentPath()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
