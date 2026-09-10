//
//  SidebarView.swift
//  postgresql-adamui
//
//  Дерево объектов базы данных.
//

import SwiftUI

/// Левая панель рабочей области: схемы, таблицы и колонки.
struct SidebarView: View {

    @ObservedObject var viewModel: DatabaseViewModel
    let onInsertQuery: (String) -> Void
    let onCreateTable: () -> Void
    let onImportCSV: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()

            if viewModel.isLoading && viewModel.schemas.isEmpty {
                LoadingView(message: "Чтение схемы…")
                Spacer()
            } else if viewModel.isEmpty {
                emptyState
            } else {
                tree
            }

            Divider()
            footer
        }
    }

    // MARK: - Части

    private var header: some View {
        HStack(spacing: 4) {
            Text("Объекты")
                .font(.headline)

            Spacer()

            Button(action: onCreateTable) {
                Image(systemName: "tablecells.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Создать таблицу")

            Button(action: onImportCSV) {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Импорт данных из CSV")

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
            .help("Обновить список объектов")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Поиск таблицы", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.callout)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tablecells")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)

            Text(viewModel.isFiltering
                 ? "Ничего не найдено"
                 : "В этой базе нет пользовательских объектов")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !viewModel.isFiltering {
                Button("Создать таблицу", action: onCreateTable)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                Button("Импорт из CSV", action: onImportCSV)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tree: some View {
        List {
            ForEach(viewModel.visibleSchemas) { schema in
                DisclosureGroup(isExpanded: expansionBinding(for: schema)) {
                    let items = viewModel.objects(in: schema.name)
                    if items.isEmpty {
                        Text("Нет объектов")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(items) { object in
                            objectRow(object)
                        }
                    }
                } label: {
                    Label(schema.name, systemImage: schema.type.systemImage)
                        .fontWeight(.medium)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func objectRow(_ object: DatabaseObject) -> some View {
        HStack(spacing: 6) {
            Label(object.name, systemImage: object.type.systemImage)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .listRowBackground(
            object.id == viewModel.selectedObject?.id
                ? Color.accentColor.opacity(0.18)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.select(object) }
        }
        .contextMenu {
            Button("Показать первые 100 строк") {
                onInsertQuery(viewModel.previewQuery(for: object))
            }
            Button("Вставить SELECT в редактор") {
                onInsertQuery(viewModel.previewQuery(for: object))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.isLoadingColumns {
                LoadingView(message: "Чтение колонок…", controlSize: .small)
            } else if let selected = viewModel.selectedObject, !viewModel.columns.isEmpty {
                Text(selected.qualifiedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ForEach(viewModel.columns) { column in
                    HStack(spacing: 4) {
                        if column.isPrimaryKey {
                            Image(systemName: "key.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.orange)
                        }
                        Text(column.name)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(column.dataType)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(viewModel.serverVersion ?? "Нет выбранного объекта")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// При активном поиске все схемы раскрыты, чтобы совпадения были видны сразу.
    private func expansionBinding(for schema: DatabaseObject) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.isFiltering || viewModel.expandedSchemas.contains(schema.name)
            },
            set: { expanded in
                if expanded {
                    viewModel.expandedSchemas.insert(schema.name)
                } else {
                    viewModel.expandedSchemas.remove(schema.name)
                }
            }
        )
    }
}

#Preview {
    SidebarView(
        viewModel: DatabaseViewModel(),
        onInsertQuery: { _ in },
        onCreateTable: { },
        onImportCSV: { }
    )
    .frame(width: 260, height: 500)
}
