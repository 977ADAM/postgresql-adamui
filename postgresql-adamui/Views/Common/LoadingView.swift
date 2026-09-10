//
//  LoadingView.swift
//  postgresql-adamui
//
//  Индикатор загрузки с подписью.
//

import SwiftUI

/// Компактный индикатор загрузки для встраивания в панели.
struct LoadingView: View {

    var message: String = "Загрузка…"
    var controlSize: ControlSize = .regular

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(controlSize)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }
}

/// Индикатор загрузки, растянутый на всё доступное пространство.
struct FullScreenLoadingView: View {

    var message: String = "Загрузка…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    VStack {
        LoadingView()
        FullScreenLoadingView(message: "Соединение с базой данных…")
    }
    .frame(width: 360, height: 240)
}
