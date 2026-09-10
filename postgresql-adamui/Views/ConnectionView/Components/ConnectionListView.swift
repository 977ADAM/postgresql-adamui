//
//  ConnectionListView.swift
//  postgresql-adamui
//
//  Список сохранённых подключений.
//

import SwiftUI

/// Левая панель экрана подключений.
struct ConnectionListView: View {

    let connections: [Connection]
    let selectedConnection: Connection?
    let onSelect: (Connection) -> Void
    let onDelete: (Connection) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if connections.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(connections) { connection in
                        row(for: connection)
                            .listRowBackground(
                                connection.id == selectedConnection?.id
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(connection) }
                            .contextMenu {
                                Button("Открыть в форме") { onSelect(connection) }
                                Divider()
                                Button("Удалить", role: .destructive) { onDelete(connection) }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()
            footer
        }
    }

    // MARK: - Части

    private var header: some View {
        Text("Подключения")
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Нет сохранённых подключений")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Заполните форму справа и нажмите «Сохранить»")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for connection: Connection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: connection.isConnected ? "circle.fill" : "circle")
                .foregroundStyle(connection.isConnected ? Color.green : Color.secondary)
                .font(.system(size: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .lineLimit(1)
                Text(connection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .help("Новое подключение")

            Button {
                if let selectedConnection { onDelete(selectedConnection) }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedConnection == nil)
            .help("Удалить подключение")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

#Preview {
    ConnectionListView(
        connections: [
            Connection(name: "Локальная БД", host: "localhost", port: 5432,
                       username: "postgres", database: "postgres"),
            Connection(name: "Продакшн", host: "db.example.com", port: 5432,
                       username: "app", database: "main", isSSLEnabled: true)
        ],
        selectedConnection: nil,
        onSelect: { _ in },
        onDelete: { _ in },
        onAdd: { }
    )
    .frame(width: 250, height: 400)
}
