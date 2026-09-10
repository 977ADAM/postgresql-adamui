//
//  DatabaseObject.swift
//  postgresql-adamui
//
//  Объекты базы данных: схемы, таблицы, представления, функции и колонки.
//

import Foundation

/// Объект внутри базы данных, который показывается в дереве сайдбара.
struct DatabaseObject: Identifiable, Hashable {

    let id: UUID
    let name: String
    let schema: String?
    let type: ObjectType

    init(id: UUID = UUID(), name: String, schema: String? = nil, type: ObjectType) {
        self.id = id
        self.name = name
        self.schema = schema
        self.type = type
    }

    /// Тип объекта базы данных.
    enum ObjectType: String, CaseIterable, Hashable {
        case schema
        case table
        case view
        case function
        case column

        /// Подпись для интерфейса.
        var title: String {
            switch self {
            case .schema: return "Схема"
            case .table: return "Таблица"
            case .view: return "Представление"
            case .function: return "Функция"
            case .column: return "Колонка"
            }
        }

        /// SF Symbol для иконки в дереве.
        var systemImage: String {
            switch self {
            case .schema: return "folder"
            case .table: return "tablecells"
            case .view: return "eye"
            case .function: return "function"
            case .column: return "textformat.abc"
            }
        }
    }

    /// Полное имя вида `schema.name` для SQL-запросов.
    var qualifiedName: String {
        guard let schema, !schema.isEmpty else { return name }
        return "\(schema).\(name)"
    }

    /// Экранированное полное имя, пригодное для подстановки в запрос.
    var escapedQualifiedName: String {
        let quotedName = "\"\(name.sqlEscaped)\""
        guard let schema, !schema.isEmpty else { return quotedName }
        return "\"\(schema.sqlEscaped)\".\(quotedName)"
    }
}

/// Колонка таблицы или представления.
struct ColumnInfo: Identifiable, Hashable {

    let id: UUID
    let name: String
    let dataType: String
    let isNullable: Bool
    let defaultValue: String?
    let isPrimaryKey: Bool

    init(
        id: UUID = UUID(),
        name: String,
        dataType: String,
        isNullable: Bool = true,
        defaultValue: String? = nil,
        isPrimaryKey: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.defaultValue = defaultValue
        self.isPrimaryKey = isPrimaryKey
    }

    /// `id integer NOT NULL` — компактное описание для подсказки.
    var signature: String {
        var parts = [name, dataType]
        if isPrimaryKey { parts.append("PRIMARY KEY") }
        if !isNullable { parts.append("NOT NULL") }
        if let defaultValue { parts.append("DEFAULT \(defaultValue)") }
        return parts.joined(separator: " ")
    }
}
