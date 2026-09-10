//
//  ConnectionFormView.swift
//  postgresql-adamui
//
//  Форма параметров подключения.
//

import SwiftUI

/// Правая панель экрана подключений: поля подключения и кнопки действий.
struct ConnectionFormView: View {

    @ObservedObject var viewModel: ConnectionViewModel
    let onConnect: () -> Void
    let onTest: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    title
                    nameField
                    endpointFields
                    credentialsFields
                    advancedOptions

                    if let problem = viewModel.validationMessage {
                        ErrorBanner(message: problem)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }

            Divider()
            actions
        }
    }

    // MARK: - Части формы

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.isEditingExisting ? "Настройки подключения" : "Новое подключение")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Укажите параметры сервера PostgreSQL")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nameField: some View {
        field(title: "Имя подключения", systemImage: "tag") {
            TextField("Моё подключение", text: $viewModel.draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var endpointFields: some View {
        HStack(alignment: .top, spacing: 16) {
            field(title: "Хост", systemImage: "network") {
                TextField("localhost", text: $viewModel.draft.host)
                    .textFieldStyle(.roundedBorder)
            }

            field(title: "Порт", systemImage: "number") {
                TextField("5432", value: $viewModel.draft.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
        }
    }

    private var credentialsFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                field(title: "Пользователь", systemImage: "person") {
                    TextField("postgres", text: $viewModel.draft.username)
                        .textFieldStyle(.roundedBorder)
                }

                field(title: "База данных", systemImage: "cylinder") {
                    TextField("postgres", text: $viewModel.draft.database)
                        .textFieldStyle(.roundedBorder)
                }
            }

            field(title: "Пароль", systemImage: "lock") {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField(passwordPlaceholder, text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)

                    Text(viewModel.hasStoredPassword
                         ? "Пароль сохранён в связке ключей"
                         : "Пароль будет сохранён в связке ключей")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var passwordPlaceholder: String {
        viewModel.hasStoredPassword ? "••••••••" : "Пароль"
    }

    private var advancedOptions: some View {
        DisclosureGroup("Дополнительные параметры") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Использовать SSL/TLS (если сервер поддерживает)", isOn: $viewModel.draft.isSSLEnabled)

                HStack {
                    Text("Строка подключения")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.draft.summary)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 4)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Очистить", action: onCancel)
                .buttonStyle(.bordered)

            if viewModel.isTesting {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Проверить подключение", action: onTest)
                .buttonStyle(.bordered)
                .disabled(!viewModel.canSubmit)

            Button(viewModel.connectButtonTitle, action: onConnect)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: - Вспомогательное

    private func field<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ConnectionFormView(
        viewModel: ConnectionViewModel(),
        onConnect: { },
        onTest: { },
        onCancel: { }
    )
    .frame(width: 560, height: 520)
}
