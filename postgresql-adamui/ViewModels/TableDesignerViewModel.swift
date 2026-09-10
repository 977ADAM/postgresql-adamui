//
//  TableDesignerViewModel.swift
//  postgresql-adamui
//
//  Состояние конструктора таблиц.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TableDesignerViewModel: ObservableObject {

    @Published var definition: TableDefinition
    @Published var dropIfExists = false

    @Published private(set) var isCreating = false
    @Published var error: String?
    @Published var showError = false
    /// Описание созданной таблицы.
    @Published private(set) var createdTable: TableDefinition?

    private let database: DatabaseService

    /// Доступные схемы (передаются из дерева объектов).
    var schemas: [String] = ["public"]

    init(schema: String = "public", database: DatabaseService = .shared) {
        self.database = database
        self.definition = .empty(schema: schema)
    }

    // MARK: - Вычисляемые свойства

    var canCreate: Bool {
        definition.isValid && !isCreating
    }

    var validationMessage: String? {
        definition.validationError?.errorDescription
    }

    var sqlPreview: String {
        var statements: [String] = []
        if dropIfExists {
            statements.append(definition.dropSQL + ";")
        }
        statements.append(definition.createSQL)
        return statements.joined(separator: "\n\n")
    }

    // MARK: - Редактирование

    func addColumn() {
        definition.columns.append(ColumnDefinition(name: suggestionForNewColumn()))
    }

    func removeColumn(_ column: ColumnDefinition) {
        definition.columns.removeAll { $0.id == column.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        definition.columns.move(fromOffsets: source, toOffset: destination)
    }

    /// Переключает первичный ключ, оставляя его только у одной колонки.
    func setPrimaryKey(_ column: ColumnDefinition) {
        for index in definition.columns.indices {
            definition.columns[index].isPrimaryKey = definition.columns[index].id == column.id
                ? !column.isPrimaryKey
                : false
        }
        // Первичный ключ не может быть NULL.
        if let index = definition.columns.firstIndex(where: { $0.id == column.id }),
           definition.columns[index].isPrimaryKey {
            definition.columns[index].isNullable = false
        }
    }

    /// Готовит таблицу с колонкой `id integer PRIMARY KEY`.
    func addIDColumn() {
        guard !definition.columns.contains(where: { $0.name.lowercased() == "id" }) else { return }
        let column = ColumnDefinition(
            name: "id",
            dataType: "integer",
            isNullable: false,
            isPrimaryKey: true
        )
        definition.columns.insert(column, at: 0)
    }

    // MARK: - Создание

    /// Создаёт таблицу. Возвращает `true` при успехе.
    @discardableResult
    func create() async -> Bool {
        if let problem = definition.validationError {
            present(error: problem)
            return false
        }

        isCreating = true
        createdTable = nil
        defer { isCreating = false }

        do {
            _ = try await database.createTable(definition, dropIfExists: dropIfExists)
            createdTable = definition
            return true
        } catch {
            present(error: error)
            return false
        }
    }

    /// Загружает описание существующей таблицы в конструктор.
    func load(schema: String, table: String) async {
        do {
            let columns = try await database.fetchColumns(schema: schema, table: table)
            definition = TableDefinition(
                schema: schema,
                name: table,
                columns: columns.map { column in
                    ColumnDefinition(
                        name: column.name,
                        dataType: column.dataType,
                        isNullable: column.isNullable,
                        isPrimaryKey: column.isPrimaryKey,
                        defaultValue: column.defaultValue
                    )
                }
            )
        } catch {
            present(error: error)
        }
    }

    private func suggestionForNewColumn() -> String {
        var index = definition.columns.count + 1
        let existing = Set(definition.columns.map { $0.name.lowercased() })
        while existing.contains("column_\(index)") {
            index += 1
        }
        return "column_\(index)"
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
