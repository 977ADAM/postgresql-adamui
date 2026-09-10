//
//  DatabaseViewModel.swift
//  postgresql-adamui
//
//  Состояние рабочей области: дерево объектов базы данных и колонки выбранной таблицы.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class DatabaseViewModel: ObservableObject {

    // MARK: - Дерево объектов

    @Published private(set) var schemas: [DatabaseObject] = []
    @Published private(set) var objects: [DatabaseObject] = []
    @Published private(set) var columns: [ColumnInfo] = []
    @Published var expandedSchemas: Set<String> = []
    @Published var selectedObject: DatabaseObject?
    /// Фильтр по имени объекта.
    @Published var searchText = ""

    // MARK: - Состояние загрузки

    @Published var isLoading = false
    @Published var isLoadingColumns = false
    @Published var error: String?
    @Published var showError = false
    @Published var serverVersion: String?

    // MARK: - Зависимости

    private let databaseService: DatabaseService

    init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }

    // MARK: - Чтение

    /// Объекты конкретной схемы с учётом фильтра поиска.
    func objects(in schema: String) -> [DatabaseObject] {
        let items = objects.filter { $0.schema == schema }
        guard !searchText.isBlank else { return items }

        let needle = searchText.trimmed.lowercased()
        return items.filter { $0.name.lowercased().contains(needle) }
    }

    /// Схемы, которые нужно показать с учётом фильтра.
    var visibleSchemas: [DatabaseObject] {
        guard !searchText.isBlank else { return schemas }
        return schemas.filter { !objects(in: $0.name).isEmpty }
    }

    /// `true`, если фильтр что-то скрыл.
    var isFiltering: Bool {
        !searchText.isBlank
    }

    /// Находит загруженный объект по имени.
    func object(schema: String, table: String) -> DatabaseObject? {
        objects.first { $0.schema == schema && $0.name == table }
    }

    /// `true`, если дерево пустое, но загрузка уже проходила.
    var isEmpty: Bool {
        schemas.isEmpty && objects.isEmpty && !isLoading
    }

    // MARK: - Загрузка

    /// Загружает версию сервера, список схем и все объекты.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let version = databaseService.fetchServerVersion()
            async let schemaNames = databaseService.fetchSchemas()

            let names = try await schemaNames
            schemas = names.map { DatabaseObject(name: $0, type: .schema) }

            // Схемы по умолчанию раскрыты, чтобы дерево было полезно сразу.
            if expandedSchemas.isEmpty {
                expandedSchemas = Set(names)
            }

            objects = try await databaseService.fetchTables(schema: nil)
            serverVersion = try? await version
        } catch {
            present(error: error)
        }
    }

    /// Перезагружает дерево.
    func refresh() async {
        await load()
    }

    /// Загружает колонки выбранного объекта.
    func select(_ object: DatabaseObject) async {
        selectedObject = object
        guard object.type == .table || object.type == .view, let schema = object.schema else {
            columns = []
            return
        }

        isLoadingColumns = true
        defer { isLoadingColumns = false }

        do {
            columns = try await databaseService.fetchColumns(schema: schema, table: object.name)
        } catch {
            columns = []
            present(error: error)
        }
    }

    /// Раскрывает или сворачивает схему.
    func toggle(_ schema: DatabaseObject) {
        if expandedSchemas.contains(schema.name) {
            expandedSchemas.remove(schema.name)
        } else {
            expandedSchemas.insert(schema.name)
        }
    }

    /// Запрос `SELECT` для выбранного объекта, подставляемый в редактор.
    func previewQuery(for object: DatabaseObject) -> String {
        "SELECT *\nFROM \(object.escapedQualifiedName)\nLIMIT 100;"
    }

    /// Убирает текст ошибки.
    func clearError() {
        error = nil
        showError = false
    }

    private func present(error: Error) {
        self.error = error.displayMessage
        showError = true
    }
}
