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
        Window("PathDeck", id: "main") {
            ContentView()
        }
        .commands {
            CLICommands()
            TabCommands()
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

/// App 委托：URL Scheme 在 Apple Event 层拦截（Window scene 不触发 .onOpenURL），
/// Open With 走 `application(_:open:)`，Finder Services 走 `ServicesProvider`。
/// 所有入口经 `AppRouter` 投递路由，由 `ContentView` 消费。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Window scene 不触发 .onOpenURL，需在 Apple Event 层拦截 kAEGetURL。
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicesProvider
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                     withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              let route = URLSchemeHandler.route(for: url) else { return }
        AppRouter.shared.request(route)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Open With（CFBundleDocumentTypes）投递的文件夹 file URL。
    /// URL Scheme 已由 `handleGetURL` 在 Apple Event 层处理，不会到达此方法。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false), isDirectory: &isDir
            ), isDir.boolValue else { continue }
            AppRouter.shared.request(.open(url.standardizedFileURL))
        }
    }
}

/// CLI 工具安装菜单。
private struct CLICommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Install Command Line Tool…") {
                CLIInstaller.install()
            }
        }
    }
}

/// 文件 Tab 管理菜单命令。
private struct TabCommands: Commands {
    @FocusedValue(\.tabManager) private var tabManager

    var body: some Commands {
        CommandMenu("标签页") {
            Button("新建标签页") {
                guard let tm = tabManager, let model = tm.activeModel else { return }
                tm.createTab(at: model.currentURL)
            }
            .keyboardShortcut("t")

            Divider()

            Button("下一个标签页") {
                tabManager?.switchToNextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)

            Button("上一个标签页") {
                tabManager?.switchToPreviousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Divider()

            ForEach(1...9, id: \.self) { n in
                Button("标签页 \(n)") {
                    tabManager?.switchToTabByIndex(n - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
    }
}

/// 终端菜单命令。
private struct TerminalCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.sendPathAction) private var sendPathAction
    @FocusedValue(\.createTerminalAction) private var createTerminal

    var body: some Commands {
        CommandMenu("终端") {
            Button("切换终端") {
                tabManager?.toggleTerminalVisibility()
            }
            .keyboardShortcut("`", modifiers: .control)

            Button("新建终端") {
                createTerminal?()
            }
            .keyboardShortcut("n", modifiers: [.control, .shift])

            Button("发送路径到终端") {
                guard let urls = tabManager?.activeModel?.selectedURLs, !urls.isEmpty else { return }
                sendPathAction?(urls)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(tabManager?.activeModel?.selectedURLs.isEmpty ?? true)

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
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.togglePreviewPaneAction) private var togglePreviewPane

    var body: some Commands {
        CommandMenu("显示") {
            Button("切换预览面板") {
                togglePreviewPane?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(tabManager?.showHidden == true ? "隐藏隐藏文件" : "显示隐藏文件") {
                tabManager?.toggleHidden()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("查找…") {
                tabManager?.activeModel?.isSearching = true
            }
            .keyboardShortcut("f")
        }
        CommandGroup(after: .pasteboard) {
            Button("复制当前路径") {
                tabManager?.activeModel?.copyCurrentPath()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
