//
//  PostgresClientApp.swift
//  postgresql-adamui
//
//  Точка входа приложения.
//

import SwiftUI

@main
struct PostgresClientApp: App {

    @StateObject private var connectionViewModel = ConnectionViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(connectionViewModel: connectionViewModel)
                .frame(
                    minWidth: AppConstants.Layout.windowMinWidth,
                    minHeight: AppConstants.Layout.windowMinHeight
                )
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новое подключение") {
                    connectionViewModel.disconnect()
                    connectionViewModel.beginNewConnection()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("База данных") {
                Button("Отключиться") {
                    connectionViewModel.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(connectionViewModel.activeConnection == nil)
            }
        }
    }
}
