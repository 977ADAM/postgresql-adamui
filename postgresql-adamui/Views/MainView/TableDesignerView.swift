//
//  TableDesignerView.swift
//  postgresql-adamui
//
//  Конструктор таблиц.
//

import SwiftUI

struct TableDesignerView: View {

    @ObservedObject var viewModel: TableDesignerViewModel
    let onFinish: (TableDefinition) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameSection
                    columnsSection
                    sqlSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .errorAlert(message: $viewModel.error)
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Новая таблица")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Опишите колонки — SQL сформируется автоматически")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Имя

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Схема")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.definition.schema) {
                        ForEach(viewModel.schemas, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Имя таблицы")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("users", text: $viewModel.definition.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                Spacer()
            }

            Toggle("Удалить таблицу, если она уже существует", isOn: $viewModel.dropIfExists)
                .toggleStyle(.checkbox)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Колонки

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Колонки", systemImage: "tablecells")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addIDColumn()
                } label: {
                    Label("Добавить id", systemImage: "key")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.definition.columns.contains { $0.name.lowercased() == "id" })

                Button {
                    viewModel.addColumn()
                } label: {
                    Label("Добавить колонку", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Имя").font(.caption).foregroundStyle(.secondary).frame(width: 180, alignment: .leading)
                    Text("Тип").font(.caption).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                    Text("PK").font(.caption).foregroundStyle(.secondary).frame(width: 34)
                    Text("NOT NULL").font(.caption).foregroundStyle(.secondary).frame(width: 70)
                    Text("DEFAULT").font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                    Spacer(minLength: 24)
                }
                .padding(.bottom, 4)

                ForEach($viewModel.definition.columns) { $column in
                    HStack(spacing: 8) {
                        TextField("имя", text: $column.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        TypePicker(selection: $column.dataType)
                            .frame(width: 170)

                        Toggle("", isOn: Binding(
                            get: { column.isPrimaryKey },
                            set: { _ in viewModel.setPrimaryKey(column) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .frame(width: 34)

                        Toggle("", isOn: $column.isNullable)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 70)
                            .disabled(column.isPrimaryKey)

                        TextField("значение", text: Binding(
                            get: { column.defaultValue ?? "" },
                            set: { column.defaultValue = $0.isBlank ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                        Button {
                            viewModel.removeColumn(column)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.definition.columns.count <= 1)
                        .help("Удалить колонку")

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - SQL

    private var sqlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("SQL", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
            Text(viewModel.sqlPreview)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Нижняя панель

    private var footer: some View {
        VStack(spacing: 8) {
            if let message = viewModel.validationMessage {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                Button("Отмена", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                if viewModel.isCreating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Создать таблицу") {
                    Task {
                        if await viewModel.create(), let created = viewModel.createdTable {
                            onFinish(created)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCreate)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Общий фон карточки

extension View {
    /// Фон карточки, используемый панелями диалогов.
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

#Preview {
    TableDesignerView(
        viewModel: TableDesignerViewModel(),
        onFinish: { _ in },
        onCancel: { }
    )
}
