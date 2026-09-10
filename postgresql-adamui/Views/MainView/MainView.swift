//
//  MainView.swift
//  postgresql-adamui
//
//  Рабочая область: дерево объектов и редактор SQL.
//

import SwiftUI

struct MainView: View {

    let connection: Connection
    let onDisconnect: () -> Void

    @StateObject private var databaseViewModel = DatabaseViewModel()
    @StateObject private var queryViewModel = QueryViewModel()
    @StateObject private var importViewModel = ImportViewModel()
    @StateObject private var designerViewModel = TableDesignerViewModel()

    @State private var showingImport = false
    @State private var showingDesigner = false
    @State private var banner: String?

    var body: some View {
        HSplitView {
            SidebarView(
                viewModel: databaseViewModel,
                onInsertQuery: { sql in queryViewModel.setQuery(sql) },
                onCreateTable: presentDesigner,
                onImportCSV: presentImport
            )
            .frame(
                minWidth: AppConstants.Layout.sidebarMinWidth,
                idealWidth: AppConstants.Layout.sidebarIdealWidth,
                maxWidth: 380
            )

            VStack(spacing: 0) {
                header
                Divider()

                if let banner {
                    successBanner(banner)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                }

                if let error = databaseViewModel.error {
                    ErrorBanner(message: error) {
                        databaseViewModel.clearError()
                    }
                    .padding(10)
                }

                QueryEditorView(
                    viewModel: queryViewModel,
                    onExecute: { Task { await queryViewModel.execute() } },
                    onClear: queryViewModel.clear
                )
            }
            .frame(minWidth: 520)
        }
        .frame(minWidth: AppConstants.Layout.windowMinWidth,
               minHeight: AppConstants.Layout.windowMinHeight)
        .task {
            await databaseViewModel.load()
        }
        .sheet(isPresented: $showingImport) {
            ImportCSVView(
                viewModel: importViewModel,
                onFinish: { report in
                    showingImport = false
                    Task { await finishImport(report) }
                },
                onCancel: { showingImport = false }
            )
        }
        .sheet(isPresented: $showingDesigner) {
            TableDesignerView(
                viewModel: designerViewModel,
                onFinish: { definition in
                    showingDesigner = false
                    Task { await finishCreatingTable(definition) }
                },
                onCancel: { showingDesigner = false }
            )
        }
        .errorAlert(message: $queryViewModel.error, title: "Ошибка запроса")
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.headline)
                Text(connection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if databaseViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(databaseViewModel.serverVersion ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                presentImport()
            } label: {
                Label("Импорт CSV…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .help("Загрузить данные из CSV-файла, создав таблицу")

            Button {
                presentDesigner()
            } label: {
                Label("Новая таблица…", systemImage: "tablecells.badge.plus")
            }
            .buttonStyle(.bordered)
            .help("Создать таблицу вручную")

            Button("Отключиться", action: onDisconnect)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func successBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                banner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
    }

    // MARK: - Открытие диалогов

    private func presentImport() {
        importViewModel.schemas = availableSchemas
        importViewModel.existingTables = databaseViewModel.objects
        importViewModel.schema = availableSchemas.first ?? "public"
        importViewModel.existingSchema = availableSchemas.first ?? "public"
        importViewModel.existingTable = nil
        importViewModel.reset()
        banner = nil
        showingImport = true
    }

    private func presentDesigner() {
        designerViewModel.schemas = availableSchemas
        designerViewModel.definition.schema = availableSchemas.first ?? "public"
        // Если выбрана таблица — предлагаем её имя как отправную точку.
        if let selected = databaseViewModel.selectedObject, selected.type == .table {
            designerViewModel.definition.name = selected.name + "_copy"
        }
        banner = nil
        showingDesigner = true
    }

    private var availableSchemas: [String] {
        let names = databaseViewModel.schemas.map(\.name)
        return names.isEmpty ? ["public"] : names
    }

    // MARK: - Завершение операций

    /// Обновляет дерево после импорта и открывает загруженную таблицу.
    private func finishImport(_ report: CSVImportReport) async {
        banner = report.summary
        await databaseViewModel.refresh()
        await focus(schema: report.schema, table: report.table)
    }

    /// Обновляет дерево после создания таблицы.
    private func finishCreatingTable(_ definition: TableDefinition) async {
        banner = "Таблица \(definition.qualifiedName) создана"
        await databaseViewModel.refresh()
        await focus(schema: definition.schema, table: definition.name)
    }

    /// Выбирает таблицу в дереве и подставляет запрос в редактор.
    private func focus(schema: String, table: String) async {
        guard let object = databaseViewModel.object(schema: schema, table: table) else { return }
        databaseViewModel.expandedSchemas.insert(schema)
        await databaseViewModel.select(object)
        queryViewModel.setQuery(databaseViewModel.previewQuery(for: object))
    }
}

#Preview {
    MainView(
        connection: Connection(
            name: "Локальная БД",
            host: "localhost",
            port: 5432,
            username: "postgres",
            database: "postgres"
        ),
        onDisconnect: { }
    )
    .frame(width: 1100, height: 700)
}
