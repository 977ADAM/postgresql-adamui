//
//  ImportViewModel.swift
//  postgresql-adamui
//
//  Состояние мастера импорта CSV.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ImportViewModel: ObservableObject {

    /// Какой разделитель использовать.
    enum DelimiterOption: String, CaseIterable, Identifiable {
        case automatic
        case comma
        case semicolon
        case tab
        case pipe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: return "Определить автоматически"
            case .comma: return "Запятая ( , )"
            case .semicolon: return "Точка с запятой ( ; )"
            case .tab: return "Табуляция"
            case .pipe: return "Вертикальная черта ( | )"
            }
        }

        var character: Character? {
            switch self {
            case .automatic: return nil
            case .comma: return ","
            case .semicolon: return ";"
            case .tab: return "\t"
            case .pipe: return "|"
            }
        }
    }

    /// Создавать новую таблицу или дописывать в существующую.
    enum Mode: String, CaseIterable, Identifiable {
        case createNew
        case appendExisting

        var id: String { rawValue }

        var title: String {
            switch self {
            case .createNew: return "Создать новую таблицу"
            case .appendExisting: return "Добавить в существующую"
            }
        }
    }

    // MARK: - Файл

    @Published var fileURL: URL?
    @Published private(set) var preview: CSVImportPreview?
    @Published var delimiterOption: DelimiterOption = .automatic
    @Published var hasHeaderRow = true
    @Published var isLoadingFile = false

    // MARK: - Назначение

    @Published var mode: Mode = .createNew
    @Published var schema = "public"
    @Published var tableName = ""
    @Published var dropIfExists = false
    @Published var trimWhitespace = true
    @Published var emptyAsNull = true
    @Published var columns: [ColumnDefinition] = []
    @Published var existingSchema = "public"
    @Published var existingTable: String?

    // MARK: - Выполнение

    @Published private(set) var isImporting = false
    @Published private(set) var loadedRows = 0
    @Published private(set) var report: CSVImportReport?
    @Published var error: String?
    @Published var showError = false

    // MARK: - Зависимости

    private let service: CSVImportService
    private let database: DatabaseService

    init(service: CSVImportService = .shared, database: DatabaseService = .shared) {
        self.service = service
        self.database = database
    }

    // MARK: - Вычисляемые свойства

    /// Доступные схемы (передаются из дерева объектов).
    var schemas: [String] = ["public"]

    /// Таблицы для режима дописывания.
    var existingTables: [DatabaseObject] = []

    var hasFile: Bool { preview != nil }

    /// Прогресс загрузки от 0 до 1.
    var progress: Double {
        guard let preview, preview.rowCount > 0 else { return 0 }
        return min(1, Double(loadedRows) / Double(preview.rowCount))
    }

    /// Описание файла для заголовка.
    var fileSummary: String? {
        guard let preview else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: Int64(preview.fileSize), countStyle: .file)
        let rows = String.pluralized(preview.rowCount, one: "строка", few: "строки", many: "строк")
        let columns = String.pluralized(preview.columnCount, one: "колонка", few: "колонки", many: "колонок")
        return "\(size) · \(rows) · \(columns) · разделитель: \(CSV.describe(delimiter: preview.delimiter))"
    }

    /// Описание таблицы, которая будет создана.
    var definition: TableDefinition {
        TableDefinition(schema: schema, name: tableName, columns: columns)
    }

    /// Проблема, мешающая запустить импорт.
    var blockingProblem: AppError? {
        guard let preview else { return .validation("Выберите CSV-файл") }
        if preview.rowCount == 0 {
            return .validation("В файле нет строк с данными")
        }
        switch mode {
        case .createNew:
            return definition.validationError
        case .appendExisting:
            if existingTable == nil {
                return .validation("Выберите таблицу для загрузки")
            }
            return nil
        }
    }

    var canImport: Bool {
        hasFile && !isImporting && blockingProblem == nil
    }

    var importButtonTitle: String {
        guard let preview else { return "Импортировать" }
        return "Импортировать \(preview.rowCount) стр."
    }

    // MARK: - Работа с файлом

    /// Загружает выбранный файл.
    func choose(url: URL) {
        fileURL = url
        if tableName.isBlank {
            tableName = CSV.sanitizeIdentifier(url.deletingPathExtension().lastPathComponent)
        }
        reload()
    }

    /// Перечитывает файл с текущими настройками разбора.
    func reload() {
        guard let fileURL else { return }

        isLoadingFile = true
        report = nil
        defer { isLoadingFile = false }

        do {
            let parsed = try service.prepare(
                url: fileURL,
                delimiter: delimiterOption.character,
                hasHeaderRow: hasHeaderRow
            )
            preview = parsed
            columns = TableDefinition.fromCSV(
                schema: schema,
                tableName: tableName,
                headers: parsed.headers,
                types: parsed.inferredTypes
            ).columns
        } catch {
            preview = nil
            columns = []
            present(error: error)
        }
    }

    /// Возвращает типы, выведенные из данных (если пользователь их менял).
    func resetTypesToInferred() {
        guard let preview else { return }
        for index in columns.indices where index < preview.inferredTypes.count {
            columns[index].dataType = preview.inferredTypes[index]
        }
    }

    /// Меняет схему у описания создаваемой таблицы.
    func applySchema(_ value: String) {
        schema = value
    }

    // MARK: - Загрузка

    /// Выполняет импорт. Возвращает `true` при успехе.
    @discardableResult
    func runImport() async -> Bool {
        guard let preview else { return false }
        if let problem = blockingProblem {
            present(error: problem)
            return false
        }

        let target: CSVImportTarget
        switch mode {
        case .createNew:
            target = .newTable(definition)
        case .appendExisting:
            guard let table = existingTable else { return false }
            let targetColumns = await targetColumnNames(schema: existingSchema, table: table)
            guard !targetColumns.isEmpty else {
                present(error: AppError.validation("Не удалось прочитать колонки таблицы \(existingSchema).\(table)"))
                return false
            }
            target = .existingTable(schema: existingSchema, table: table, columns: targetColumns)
        }

        let request = CSVImportRequest(
            preview: preview,
            target: target,
            dropIfExists: dropIfExists && mode == .createNew,
            emptyAsNull: emptyAsNull,
            trimWhitespace: trimWhitespace
        )

        isImporting = true
        loadedRows = 0
        report = nil
        defer { isImporting = false }

        do {
            let result = try await service.run(request) { [weak self] written, _ in
                Task { @MainActor [weak self] in
                    self?.loadedRows = written
                }
            }
            report = result
            return true
        } catch {
            present(error: error)
            return false
        }
    }

    /// Колонки существующей таблицы.
    private func targetColumnNames(schema: String, table: String) async -> [String] {
        do {
            return try await database.fetchColumns(schema: schema, table: table).map(\.name)
        } catch {
            present(error: error)
            return []
        }
    }

    /// Сбрасывает результат и ошибки.
    func reset() {
        error = nil
        showError = false
        report = nil
        loadedRows = 0
    }

    private func present(error: Error) {
        self.error = error.displayMessage
        showError = true
    }

    private func present(error: AppError) {
        self.error = error.errorDescription ?? error.localizedDescription
        showError = true
    }
}
