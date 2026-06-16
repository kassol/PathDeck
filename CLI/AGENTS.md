# AGENTS.md — CLI

> `pathdeck` 命令行工具。父级约束见根目录 `AGENTS.md`。

## 职责

从终端一行命令唤起 PathDeck App。解析子命令 + 路径，构造 `pathdeck://` URL，经 `/usr/bin/open` 交给系统路由。

## 目录结构

```
CLI/
  main.swift             入口：CLICommand.parse → Process("/usr/bin/open", url)
  CLICommand.swift       纯函数：参数解析 + 路径解析 + URL 构造（synchronized group 共享编译到 PathDeck app target 供单测）
  AGENTS.md              本文件
```

## 模块规范

- Target：`pathdeck-cli`（command line tool），product name `pathdeck`，`PRODUCT_MODULE_NAME = pathdeck_cli`（避免 case-insensitive FS 与 `PathDeck` 模块碰撞）
- Foundation-only，不 import AppKit / SwiftUI
- `CLICommand.swift` 经 synchronized group 同时编译到 PathDeck app target；`main.swift` 经 `membershipExceptions` 排除
- CLI 二进制经 PathDeck target 的 Copy Files build phase 嵌入 `PathDeck.app/Contents/Resources/pathdeck`
- URL 格式与 `URLSchemeHandler` 保持一致（`pathdeck://{action}?path={percent-encoded}`）；格式变更须同步两处

## 依赖关系

- 上游：无（Foundation-only）
- 下游：PathDeck app 经 URL Scheme 接收路由（`URLSchemeHandler` → `AppRouter`）
- 安装：`CLIInstaller`（`PathDeck/CLIInstaller.swift`）从 app bundle Resources 拷贝到 `/usr/local/bin/pathdeck`

## 变更日志

- 2026-06-16 S22 初始落地：`open/reveal/terminal/help` 四子命令 + 智能路由 + 相对路径/`~` 展开。26 个单测。
