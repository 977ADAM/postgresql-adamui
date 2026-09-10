//
//  String+Extensions.swift
//  postgresql-adamui
//
//  Расширения для работы с текстом (SQL, значения ячеек, размеры).
//

import Foundation

extension String {

    /// Строка без ведущих и завершающих пробельных символов.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `true`, если строка пустая или состоит только из пробелов.
    var isBlank: Bool {
        trimmed.isEmpty
    }

    /// Обрезает значение до указанной длины, добавляя многоточие.
    func truncated(to limit: Int) -> String {
        guard limit > 0, count > limit else { return self }
        return String(prefix(limit)) + "…"
    }

    /// Экранирует значение для использования в одинарных кавычках SQL.
    var sqlEscaped: String {
        replacingOccurrences(of: "'", with: "''")
    }

    /// Возвращает первый оператор-значимый токен запроса (`SELECT`, `INSERT`, ...) в верхнем регистре.
    var sqlKeyword: String? {
        let stripped = trimmed
        // Пропускаем комментарии и пустые строки в начале запроса.
        let meaningful = stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .first { !$0.isEmpty && !$0.hasPrefix("--") }

        guard let line = meaningful else { return nil }
        let token = line.prefix { $0.isLetter }
        return token.isEmpty ? nil : token.uppercased()
    }

    /// `true`, если хотя бы одна инструкция скрипта изменяет данные или схему.
    var isMutatingSQL: Bool {
        SQLScript.split(self).contains { statement in
            switch statement.sqlKeyword {
            case "INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE", "GRANT", "REVOKE":
                return true
            default:
                return false
            }
        }
    }

    /// Склонение существительного по числу: `1 строка`, `2 строки`, `5 строк`.
    static func pluralized(_ count: Int, one: String, few: String, many: String) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 {
            return "\(count) \(many)"
        }
        switch mod10 {
        case 1: return "\(count) \(one)"
        case 2, 3, 4: return "\(count) \(few)"
        default: return "\(count) \(many)"
        }
    }
}

extension Optional where Wrapped == String {
    /// Значение или прочерк для отображения `NULL` в таблице результатов.
    var orDash: String {
        switch self {
        case .some(let value): return value
        case .none: return "—"
        }
    }
}
