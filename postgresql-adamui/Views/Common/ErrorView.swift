//
//  ErrorView.swift
//  postgresql-adamui
//
//  Экран и компактная строка для отображения ошибок.
//

import SwiftUI

/// Заполняющий экран ошибки с кнопкой повтора.
struct ErrorView: View {

    let message: String
    var title: String = "Не удалось выполнить операцию"
    var retryTitle: String = "Повторить"
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 420)

            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Компактная строка с ошибкой для панелей и редактора.
struct ErrorBanner: View {

    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35))
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        ErrorBanner(message: "Ошибка выполнения запроса: relation \"users\" does not exist") { }
        ErrorView(
            message: "Сервер недоступен по указанному адресу",
            retry: { }
        )
    }
    .padding()
    .frame(width: 520, height: 360)
}
