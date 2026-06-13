//
//  TerminalSmokeView.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import SwiftUI

/// SwiftUI 包装 `GhosttySurfaceView`，供独立终端冒烟窗口承载（S2）。
struct TerminalSmokeView: NSViewRepresentable {
    func makeNSView(context: Context) -> GhosttySurfaceView {
        GhosttySurfaceView(frame: .zero)
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {}
}
