//
//  KeychainService.swift
//  postgresql-adamui
//
//  Безопасное хранение паролей подключений в системной связке ключей.
//

import Foundation
import Security

/// Обёртка над `Security.framework` для хранения паролей подключений.
///
/// Один пароль — одна запись `kSecClassGenericPassword` с сервисом
/// `AppConstants.App.keychainService` и аккаунтом, равным `UUID` подключения.
final class KeychainService {

    static let shared = KeychainService()

    private let service: String

    private init() {
        self.service = AppConstants.App.keychainService
    }

    // MARK: - Запись

    /// Сохраняет пароль. `nil` или пустая строка удаляют запись.
    @discardableResult
    func savePassword(_ password: String?, for id: UUID) -> Bool {
        guard let password, !password.isEmpty else {
            return deletePassword(for: id)
        }

        guard let data = password.data(using: .utf8) else { return false }

        // Базовый запрос используется и для удаления старого значения.
        var query = baseQuery(for: id)
        query[kSecValueData as String] = data
        // Пароль доступен только после первой разблокировки устройства.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // Обновляем существующую запись, не создавая дубликат.
        query[kSecAttrLabel as String] = "PostgreSQL AdamUI"

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            return updatePassword(data, for: id)
        default:
            return false
        }
    }

    // MARK: - Чтение

    /// Возвращает сохранённый пароль или `nil`, если записи нет.
    func getPassword(for id: UUID) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    /// `true`, если для подключения сохранён пароль.
    func hasPassword(for id: UUID) -> Bool {
        getPassword(for: id) != nil
    }

    // MARK: - Удаление

    @discardableResult
    func deletePassword(for id: UUID) -> Bool {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Удаляет пароли подключений, которых больше нет в списке.
    func prune(keeping ids: [UUID]) {
        let keep = Set(ids.map(\.uuidString))
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return
        }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  !keep.contains(account) else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }

    // MARK: - Private

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }

    private func updatePassword(_ data: Data, for id: UUID) -> Bool {
        let query = baseQuery(for: id)
        let attributes: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }
}
