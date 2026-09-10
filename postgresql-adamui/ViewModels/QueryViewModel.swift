//
//  QueryViewModel.swift
//  postgresql-adamui
//
//  Состояние редактора SQL: текст запроса, результат и история.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class QueryViewModel: ObservableObject {

    // MARK: - Редактор

    @Published var queryText = ""
    @Published var currentResult: QueryResult?
    @Published private(set) var history: [QueryHistoryEntry] = []

    // MARK: - Состояние выполнения

    @Published var isExecuting = false
    @Published var error: String?
    @Published var showError = false
    /// Текст предупреждения для изменяющих запросов.
    @Published var confirmationMessage: String?
    @Published var showConfirmation = false

    // MARK: - Зависимости

    private let databaseService: DatabaseService
    private var currentTask: Task<Void, Never>?

    init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
        queryText = Self.defaultQuery
    }

    // MARK: - Вычисляемые свойства

    /// `true`, если есть что выполнять и запрос сейчас не выполняется.
    var canExecute: Bool {
        !queryText.isBlank && !isExecuting
    }

    /// `true`, если запрос потенциально изменяет данные.
    var isMutating: Bool {
        queryText.isMutatingSQL
    }

    /// Сводка по последнему результату для строки статуса.
    var statusText: String {
        guard let currentResult else { return "Готов к работе" }
        return currentResult.summary
    }

    // MARK: - Действия

    /// Выполняет текст из редактора.
    func execute() async {
        let sql = queryText.trimmed
        guard !sql.isBlank else { return }

        isExecuting = true
        defer { isExecuting = false }

        do {
            let outcome = try await databaseService.executeQuery(sql)
            let result = QueryResult(
                query: sql,
                columns: outcome.columns,
                rows: outcome.rows,
                executionTime: outcome.executionTime,
                rowCount: outcome.affectedRows ?? outcome.rows.count,
                commandTag: outcome.commandTag
            )
            currentResult = result
            appendHistory(sql: sql, succeeded: true, duration: outcome.executionTime)
        } catch {
            let duration = currentResult?.executionTime ?? 0
            currentResult = QueryResult(
                query: sql,
                columns: [],
                rows: [],
                executionTime: duration,
                commandTag: nil,
                error: error.displayMessage
            )
            appendHistory(sql: sql, succeeded: false, duration: duration)
            present(error: error)
        }
    }

    /// Подставляет запрос в редактор (например, из дерева объектов).
    func setQuery(_ sql: String) {
        queryText = sql
    }

    /// Очищает редактор и результат.
    func clear() {
        queryText = ""
        currentResult = nil
    }

    /// Восстанавливает запрос из истории.
    func restore(_ entry: QueryHistoryEntry) {
        queryText = entry.query
    }

    /// Очищает историю.
    func clearHistory() {
        history.removeAll()
    }

    /// Убирает текст ошибки.
    func clearError() {
        error = nil
        showError = false
    }

    // MARK: - Private

    private func appendHistory(sql: String, succeeded: Bool, duration: TimeInterval) {
        history.insert(
            QueryHistoryEntry(query: sql, succeeded: succeeded, duration: duration),
            at: 0
        )
        if history.count > AppConstants.Limits.queryHistoryCount {
            history.removeLast(history.count - AppConstants.Limits.queryHistoryCount)
        }
    }

    private func present(error: Error) {
        self.error = error.displayMessage
        showError = true
    }

    private static let defaultQuery = """
        -- Введите SQL-запрос и нажмите ⌘↩
        SELECT version();
        """
}
