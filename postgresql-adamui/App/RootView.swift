//
//  RootView.swift
//  postgresql-adamui
//
//  Переключает экран подключений и рабочую область.
//

import SwiftUI

struct RootView: View {

    @ObservedObject var connectionViewModel: ConnectionViewModel

    var body: some View {
        Group {
            if let connection = connectionViewModel.activeConnection {
                MainView(connection: connection) {
                    connectionViewModel.disconnect()
                }
                .transition(.opacity)
            } else {
                ConnectionView(viewModel: connectionViewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: connectionViewModel.activeConnection?.id)
    }
}

#Preview {
    RootView(connectionViewModel: ConnectionViewModel())
        .frame(width: 1100, height: 700)
}
