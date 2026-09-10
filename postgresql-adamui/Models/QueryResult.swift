//
//  QueryResult.swift
//  postgresql-adamui
//
//  Результат выполнения SQL-запроса.
//

import Foundation

/// Табличный результат запроса, пригодный для отображения в UI.
struct QueryResult: Identifiable {

    let id: UUID
    let query: String
    let columns: [String]
    /// Строки результата; `nil` в ячейке означает SQL `NULL`.
    let rows: [[String?]]
    let executionTime: TimeInterval
    let rowCount: Int
    /// Сообщение сервера для команд без набора строк (`INSERT`, `UPDATE`, `CREATE`, ...).
    let commandTag: String?
    var error: String?

    init(
        id: UUID = UUID(),
        query: String,
        columns: [String],
        rows: [[String?]],
        executionTime: TimeInterval,
        rowCount: Int? = nil,
        commandTag: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.query = query
        self.columns = columns
        self.rows = rows
        self.executionTime = executionTime
        self.rowCount = rowCount ?? rows.count
        self.commandTag = commandTag
        self.error = error
    }

    /// `true`, если запрос вернул набор строк (а не просто тег команды).
    var hasRows: Bool {
        !columns.isEmpty
    }

    /// `true`, если результат был обрезан перед показом в таблице.
    var isTruncated: Bool {
        rows.count > AppConstants.Limits.visibleResultRows
    }

    /// Строки, которые реально показываются в таблице.
    var visibleRows: [[String?]] {
        isTruncated ? Array(rows.prefix(AppConstants.Limits.visibleResultRows)) : rows
    }

    /// Текст сводки: `SELECT · 12 строк · 24 мс`.
    var summary: String {
        let duration = String(format: "%.0f мс", executionTime * 1000)
        if let commandTag {
            return "\(commandTag) · \(duration)"
        }
        guard hasRows else { return duration }
        let rowsText = String.pluralized(rowCount, one: "строка", few: "строки", many: "строк")
        return "\(rowsText) · \(duration)"
    }

    /// Пустой результат для начального состояния редактора.
    static let empty = QueryResult(
        query: "",
        columns: [],
        rows: [],
        executionTime: 0
    )
}

/// «Сырой» результат запроса на выходе `DatabaseService`.
///
/// Сервис не знает о UI, поэтому возвращает колонки, строки и метаданные
/// команды, а `QueryViewModel` превращает это в `QueryResult`.
struct QueryOutcome {

    let columns: [String]
    let rows: [[String?]]
    /// Тег команды сервера: `SELECT`, `INSERT`, `CREATE TABLE`, ...
    let commandTag: String?
    /// Сколько строк затронула команда (`nil` для `SELECT` без счётчика).
    let affectedRows: Int?
    let executionTime: TimeInterval
}

/// Запись в истории выполненных запросов.
struct QueryHistoryEntry: Identifiable, Hashable {

    let id: UUID
    let query: String
    let executedAt: Date
    let succeeded: Bool
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        query: String,
        executedAt: Date = Date(),
        succeeded: Bool,
        duration: TimeInterval
    ) {
        self.id = id
        self.query = query
        self.executedAt = executedAt
        self.succeeded = succeeded
        self.duration = duration
    }

    /// Однострочный предпросмотр запроса для списка истории.
    var preview: String {
        query
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .first { !$0.isEmpty }?
            .truncated(to: 80) ?? query.truncated(to: 80)
    }
}
