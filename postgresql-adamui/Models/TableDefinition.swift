//
//  TableDefinition.swift
//  postgresql-adamui
//
//  Описание таблицы и генерация DDL.
//

import Foundation

/// Описание одной колонки для `CREATE TABLE`.
struct ColumnDefinition: Identifiable, Hashable, Sendable {

    let id: UUID
    var name: String
    var dataType: String
    var isNullable: Bool
    var isPrimaryKey: Bool
    /// SQL-выражение значения по умолчанию, например `now()` или `0`.
    var defaultValue: String?

    init(
        id: UUID = UUID(),
        name: String,
        dataType: String = "text",
        isNullable: Bool = true,
        isPrimaryKey: Bool = false,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
        self.defaultValue = defaultValue
    }

    /// `"name" text NOT NULL DEFAULT 0`
    var sql: String {
        var parts = ["\"\(name.sqlEscaped)\"", dataType.isEmpty ? "text" : dataType]
        if isPrimaryKey {
            // PRIMARY KEY уже подразумевает NOT NULL.
            parts.append("PRIMARY KEY")
        } else if !isNullable {
            parts.append("NOT NULL")
        }
        if let defaultValue, !defaultValue.isBlank {
            parts.append("DEFAULT \(defaultValue)")
        }
        return parts.joined(separator: " ")
    }

    /// Проблема в описании колонки или `nil`.
    var validationError: AppError? {
        if name.isBlank {
            return .validation("У колонки не задано имя")
        }
        if dataType.isBlank {
            return .validation("У колонки «\(name)» не задан тип")
        }
        return nil
    }
}

/// Описание таблицы целиком.
struct TableDefinition: Sendable {

    var schema: String
    var name: String
    var columns: [ColumnDefinition]

    init(schema: String = "public", name: String = "", columns: [ColumnDefinition] = []) {
        self.schema = schema
        self.name = name
        self.columns = columns
    }

    /// Полное имя таблицы для интерфейса.
    var qualifiedName: String {
        schema.isEmpty ? name : "\(schema).\(name)"
    }

    /// Первая проблема в описании или `nil`.
    var validationError: AppError? {
        if name.isBlank {
            return .validation("Укажите имя таблицы")
        }
        if schema.isBlank {
            return .validation("Укажите схему")
        }
        if columns.isEmpty {
            return .validation("Добавьте хотя бы одну колонку")
        }
        if let columnError = columns.compactMap(\.validationError).first {
            return columnError
        }

        // Дубликаты имён колонок PostgreSQL не допустит — проверяем заранее.
        var seen: Set<String> = []
        for column in columns {
            let key = column.name.lowercased()
            if seen.contains(key) {
                return .validation("Колонка «\(column.name)» указана дважды")
            }
            seen.insert(key)
        }

        let primaryKeys = columns.filter(\.isPrimaryKey).count
        if primaryKeys > 1 {
            return .validation("Составной первичный ключ пока не поддерживается: отметьте одну колонку")
        }

        return nil
    }

    var isValid: Bool {
        validationError == nil
    }

    /// `CREATE TABLE "schema"."name" (...)`
    var createSQL: String {
        let body = columns.map { "    " + $0.sql }.joined(separator: ",\n")
        return """
            CREATE TABLE "\(schema.sqlEscaped)"."\(name.sqlEscaped)" (
            \(body)
            );
            """
    }

    /// `DROP TABLE IF EXISTS "schema"."name"`
    var dropSQL: String {
        "DROP TABLE IF EXISTS \"\(schema.sqlEscaped)\".\"\(name.sqlEscaped)\""
    }

    /// Имена колонок в порядке описания.
    var columnNames: [String] {
        columns.map(\.name)
    }

    /// Пустая таблица с одной текстовой колонкой.
    static func empty(schema: String = "public") -> TableDefinition {
        TableDefinition(
            schema: schema,
            name: "",
            columns: [
                ColumnDefinition(name: "id", dataType: "integer", isNullable: false, isPrimaryKey: true),
                ColumnDefinition(name: "name", dataType: "text", isNullable: true)
            ]
        )
    }

    /// Таблица, выведенная из CSV: заголовки становятся колонками.
    static func fromCSV(
        schema: String,
        tableName: String,
        headers: [String],
        types: [String]
    ) -> TableDefinition {
        let columns = headers.enumerated().map { index, header in
            ColumnDefinition(
                name: header,
                dataType: index < types.count ? types[index] : "text",
                isNullable: true
            )
        }
        return TableDefinition(schema: schema, name: tableName, columns: columns)
    }
}
