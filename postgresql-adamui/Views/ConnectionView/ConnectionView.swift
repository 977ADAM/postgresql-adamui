//
//  ConnectionView.swift
//  postgresql-adamui
//
//  Экран управления подключениями: список сохранённых подключений и форма.
//

import SwiftUI

struct ConnectionView: View {

    @ObservedObject var viewModel: ConnectionViewModel

    var body: some View {
        HSplitView {
            ConnectionListView(
                connections: viewModel.connections,
                selectedConnection: viewModel.selectedConnection,
                onSelect: viewModel.selectConnection,
                onDelete: viewModel.deleteConnection,
                onAdd: viewModel.beginNewConnection
            )
            .frame(
                minWidth: AppConstants.Layout.sidebarMinWidth,
                idealWidth: AppConstants.Layout.sidebarIdealWidth,
                maxWidth: 360
            )

            ConnectionFormView(
                viewModel: viewModel,
                onConnect: { Task { await viewModel.connect() } },
                onTest: { Task { await viewModel.testConnection() } },
                onCancel: viewModel.beginNewConnection
            )
            .frame(minWidth: AppConstants.Layout.formMinWidth)
        }
        .frame(minWidth: AppConstants.Layout.windowMinWidth,
               minHeight: AppConstants.Layout.windowMinHeight)
        .overlay(alignment: .bottom) {
            if viewModel.isConnecting {
                connectingOverlay
            }
        }
        .errorAlert(
            message: $viewModel.connectionError,
            title: viewModel.alertTitle
        )
    }

    private var connectingOverlay: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Подключение к \(viewModel.draft.endpoint)…")
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .padding(.bottom, 70)
    }
}

#Preview {
    ConnectionView(viewModel: ConnectionViewModel())
        .frame(width: 1000, height: 640)
}
