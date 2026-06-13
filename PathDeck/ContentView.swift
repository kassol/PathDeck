//
//  ContentView.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import SwiftUI

struct ContentView: View {
    @State private var model = WorkspaceModel()

    var body: some View {
        FileTableView(items: model.items, onOpen: { model.enter($0) })
            .frame(minWidth: 720, minHeight: 480)
            .navigationTitle(model.currentURL.lastPathComponent)
            .navigationSubtitle((model.currentURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { model.goUp() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("返回上级")
                }
            }
    }
}
