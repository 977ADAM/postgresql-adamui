//
//  CSV.swift
//  postgresql-adamui
//
//  Разбор CSV-файлов по RFC 4180.
//

import Foundation

/// Разбор CSV-текста.
///
/// Поддерживаются: кавычки с удвоением (`""`), переводы строк внутри
/// закавыченных полей, CRLF и LF, BOM в начале файла, отсутствие перевода
/// строки в последней записи.
enum CSV {

    /// Разделители, которые распознаются автоматически.
    static let candidateDelimiters: [Character] = [",", ";", "\t", "|"]

    // MARK: - Разбор

    /// Разбирает CSV-текст в матрицу полей.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            // Полностью пустая строка не является записью.
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while index < text.endIndex {
            let character = text[index]

            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                    index = next
                    continue
                }
                field.append(character)
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                if field.isEmpty {
                    inQuotes = true
                } else {
                    // Кавычка внутри незакавыченного поля — обычный символ.
                    field.append(character)
                }
                index = text.index(after: index)
                continue
            }

            if character == delimiter {
                endField()
                index = text.index(after: index)
                continue
            }

            // В Swift CRLF — это один `Character`, поэтому проверяем isNewline,
            // а не сравнение с "\n".
            if character.isNewline {
                endRow()
                index = text.index(after: index)
                continue
            }

            field.append(character)
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            endRow()
        }

        return rows
    }

    /// Определяет разделитель по первым строкам: побеждает тот, что даёт больше колонок.
    static func detectDelimiter(in text: String) -> Character {
        let sample = String(text.prefix(64 * 1024))

        var best: Character = ","
        var bestCount = 1

        for candidate in candidateDelimiters {
            let rows = parse(sample, delimiter: candidate)
            guard let first = rows.first else { continue }
            // Смотрим на медиану по первым строкам: так устойчивее к «шумным» строкам.
            let counts = rows.prefix(20).map(\.count).sorted()
            let median = counts.isEmpty ? first.count : counts[counts.count / 2]
            if median > bestCount {
                bestCount = median
                best = candidate
            }
        }

        return best
    }

    /// Убирает BOM (U+FEFF), который часто добавляет Excel.
    static func strippingByteOrderMark(_ text: String) -> String {
        guard text.first == "\u{FEFF}" else { return text }
        return String(text.dropFirst())
    }

    /// Читает файл и разбирает его.
    static func read(contentsOf url: URL, delimiter: Character?) throws -> (rows: [[String]], delimiter: Character) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // В песочнице сюда попадает и отказ в доступе к файлу.
            throw AppError.validation(
                "Не удалось прочитать файл «\(url.lastPathComponent)»: \(error.localizedDescription)"
            )
        }

        // Пробуем UTF-8, затем Windows-1251 — частый случай для русских CSV из Excel.
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let cp1251 = String(data: data, encoding: .windowsCP1251) {
            text = cp1251
        } else if let maccyrillic = String(data: data, encoding: .macOSRoman) {
            text = maccyrillic
        } else {
            throw AppError.validation("Не удалось определить кодировку файла. Сохраните его в UTF-8.")
        }

        let normalized = strippingByteOrderMark(text)
        let resolved = delimiter ?? detectDelimiter(in: normalized)
        return (parse(normalized, delimiter: resolved), resolved)
    }

    // MARK: - Заголовки

    /// Приводит набор заголовков к пригодным именам колонок PostgreSQL.
    ///
    /// Пустые заголовки получают имя `column_N`, дубликаты — суффикс `_2`, `_3`, …
    static func normalizeHeaders(_ raw: [String]) -> [String] {
        var used: Set<String> = []
        var result: [String] = []

        for (index, value) in raw.enumerated() {
            var name = sanitizeIdentifier(value)
            if name.isEmpty {
                name = "column_\(index + 1)"
            }
            if used.contains(name.lowercased()) {
                var suffix = 2
                while used.contains("\(name)_\(suffix)".lowercased()) {
                    suffix += 1
                }
                name = "\(name)_\(suffix)"
            }
            used.insert(name.lowercased())
            result.append(name)
        }

        return result
    }

    /// Оставляет в имени только допустимые символы и приводит его к нижнему регистру.
    static func sanitizeIdentifier(_ value: String) -> String {
        let allowed = value.trimmed.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        var name = String(allowed)
        // Схлопываем подряд идущие подчёркивания.
        while name.contains("__") {
            name = name.replacingOccurrences(of: "__", with: "_")
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if let first = name.first, first.isNumber {
            name = "c_" + name
        }
        return name.lowercased()
    }

    /// Разделитель в виде читаемой подписи.
    static func describe(delimiter: Character) -> String {
        switch delimiter {
        case ",": return "запятая"
        case ";": return "точка с запятой"
        case "\t": return "табуляция"
        case "|": return "вертикальная черта"
        default: return "«\(delimiter)»"
        }
    }
}
