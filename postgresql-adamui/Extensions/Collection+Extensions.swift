//
//  Collection+Extensions.swift
//  postgresql-adamui
//
//  Безопасный доступ к элементам коллекций.
//

import Foundation

extension Collection {
    /// Элемент по индексу или `nil`, если индекс вне границ.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element == String? {
    /// Значение колонки по позиции: `nil`, если колонки нет или в ней SQL `NULL`.
    func element(at index: Int) -> String? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
