//
//  CSVImportService.swift
//  postgresql-adamui
//
//  Разбор CSV-файла и загрузка данных в PostgreSQL.
//

import Foundation

/// Результат разбора файла, который показывается в мастере импорта.
struct CSVImportPreview: Sendable {

    let url: URL
    let fileSize: Int
    let delimiter: Character
    let hasHeaderRow: Bool
    /// Заголовки колонок, уже приведённые к допустимым именам PostgreSQL.
    let headers: [String]
    /// Строки данных без заголовка.
    let rows: [[String]]
    let inferredTypes: [String]

    var columnCount: Int { headers.count }
    var rowCount: Int { rows.count }

    /// Первые строки для предпросмотра.
    func sample(_ count: Int = 5) -> [[String]] {
        Array(rows.prefix(count))
    }
}

/// Куда загружать данные.
enum CSVImportTarget: Sendable {
    /// Создать таблицу по описанию и залить в неё данные.
    case newTable(TableDefinition)
    /// Добавить данные в существующую таблицу; колонки сопоставляются по имени.
    case existingTable(schema: String, table: String, columns: [String])
}

/// Полное задание на импорт.
struct CSVImportRequest: Sendable {

    var preview: CSVImportPreview
    var target: CSVImportTarget
    /// Удалить таблицу перед созданием.
    var dropIfExists: Bool
    /// Считать пустые значения как `NULL`.
    var emptyAsNull: Bool
    /// Обрезать пробелы в начале и конце значений.
    var trimWhitespace: Bool
}

/// Итог импорта.
struct CSVImportReport: Sendable {

    let schema: String
    let table: String
    let importedRows: Int
    let duration: TimeInterval

    var qualifiedName: String {
        "\(schema).\(table)"
    }

    var summary: String {
        let rows = String.pluralized(importedRows, one: "строка", few: "строки", many: "строк")
        return "Загружено \(rows) в \(qualifiedName) за \(String(format: "%.2f", duration)) с"
    }
}

/// Читает CSV и заливает его в базу.
final class CSVImportService {

    static let shared = CSVImportService()

    private let database: DatabaseService

    init(database: DatabaseService = .shared) {
        self.database = database
    }

    // MARK: - Разбор файла

    /// Читает файл и готовит предпросмотр с выведенными типами.
    func prepare(url: URL, delimiter: Character?, hasHeaderRow: Bool) throws -> CSVImportPreview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let (rows, resolvedDelimiter) = try CSV.read(contentsOf: url, delimiter: delimiter)

        guard !rows.isEmpty else {
            throw AppError.validation("Файл пуст или не содержит данных")
        }

        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else {
            throw AppError.validation("В файле не найдено ни одной колонки")
        }

        let headers: [String]
        let dataRows: [[String]]

        if hasHeaderRow {
            let rawHeader = rows[0] + Array(repeating: "", count: max(0, columnCount - rows[0].count))
            headers = CSV.normalizeHeaders(Array(rawHeader.prefix(columnCount)))
            dataRows = Array(rows.dropFirst())
        } else {
            headers = CSV.normalizeHeaders((1...columnCount).map { "column_\($0)" })
            dataRows = rows
        }

        // Строки выравниваем по числу колонок.
        let normalizedRows = dataRows.map { row -> [String] in
            if row.count == columnCount { return row }
            if row.count > columnCount { return Array(row.prefix(columnCount)) }
            return row + Array(repeating: "", count: columnCount - row.count)
        }

        return CSVImportPreview(
            url: url,
            fileSize: size,
            delimiter: resolvedDelimiter,
            hasHeaderRow: hasHeaderRow,
            headers: headers,
            rows: normalizedRows,
            inferredTypes: CSVTypeInference.inferColumns(rows: normalizedRows, columnCount: columnCount)
        )
    }

    // MARK: - Импорт

    /// Создаёт таблицу (если нужно) и заливает данные.
    ///
    /// - Parameter progress: Вызывается с числом уже загруженных строк.
    func run(
        _ request: CSVImportRequest,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> CSVImportReport {
        let preview = request.preview
        let started = Date()

        let schema: String
        let table: String
        let columns: [String]
        let rows: [[String?]]

        switch request.target {
        case .newTable(let definition):
            guard definition.isValid else {
                throw definition.validationError ?? .invalidData
            }
            try await database.createTable(definition, dropIfExists: request.dropIfExists)
            schema = definition.schema
            table = definition.name
            columns = definition.columnNames
            rows = Self.project(
                rows: preview.rows,
                indices: Array(0..<columns.count),
                trim: request.trimWhitespace
            )

        case .existingTable(let targetSchema, let targetTable, let targetColumns):
            // Колонки назначения ищем по имени среди заголовков файла.
            var indices: [Int] = []
            var missing: [String] = []
            for name in targetColumns {
                if let index = preview.headers.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    indices.append(index)
                } else {
                    missing.append(name)
                }
            }
            guard missing.isEmpty else {
                throw AppError.validation("В файле нет колонок: \(missing.joined(separator: ", "))")
            }

            schema = targetSchema
            table = targetTable
            columns = targetColumns
            rows = Self.project(rows: preview.rows, indices: indices, trim: request.trimWhitespace)
        }

        let total = rows.count
        let imported = try await database.copyRows(
            schema: schema,
            table: table,
            columns: columns,
            rows: rows,
            emptyAsNull: request.emptyAsNull
        ) { written in
            progress(written, total)
        }

        return CSVImportReport(
            schema: schema,
            table: table,
            importedRows: imported,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Private

    /// Выбирает из строк CSV значения нужных колонок.
    private static func project(rows: [[String]], indices: [Int], trim: Bool) -> [[String?]] {
        rows.map { row in
            indices.map { index -> String? in
                guard index < row.count else { return nil }
                let value = row[index]
                return trim ? value.trimmed : value
            }
        }
    }
}
