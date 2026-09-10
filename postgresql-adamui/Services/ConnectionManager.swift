//
//  ConnectionManager.swift
//  postgresql-adamui
//
//  Реестр активных соединений с PostgreSQL.
//

import Foundation
import PostgresNIO

/// Хранит активные клиенты пула соединений и задачи, в которых они работают.
///
/// `PostgresClient` не умеет останавливаться сам: его нужно запустить в
/// долгоживущей задаче (`await client.run()`) и завершить её, когда соединение
/// больше не нужно. Именно этой парой «клиент + задача» управляет менеджер.
final class ConnectionManager: @unchecked Sendable {

    static let shared = ConnectionManager()

    /// Связка клиента и запускающей его задачи.
    private struct Entry {
        let client: PostgresClient
        let runTask: Task<Void, Never>
    }

    private var entries: [UUID: Entry] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Чтение

    /// Клиент для подключения, если оно активно.
    func getConnection(for id: UUID) -> PostgresClient? {
        lock.withLock { entries[id]?.client }
    }

    /// `true`, если для подключения есть работающий клиент.
    func isActive(_ id: UUID) -> Bool {
        lock.withLock { entries[id] != nil }
    }

    /// Идентификаторы всех активных подключений.
    var activeIDs: [UUID] {
        lock.withLock { Array(entries.keys) }
    }

    /// Сколько соединений сейчас открыто.
    var activeCount: Int {
        lock.withLock { entries.count }
    }

    // MARK: - Изменение

    /// Регистрирует новый клиент вместе с задачей, в которой он запущен.
    func addConnection(_ client: PostgresClient, runTask: Task<Void, Never>, for id: UUID) {
        let previous: Entry? = lock.withLock {
            let old = entries[id]
            entries[id] = Entry(client: client, runTask: runTask)
            return old
        }
        // Предыдущее соединение с тем же id закрываем вне блокировки.
        previous?.runTask.cancel()
    }

    /// Закрывает соединение и убирает его из реестра.
    @discardableResult
    func removeConnection(for id: UUID) -> Bool {
        let removed: Entry? = lock.withLock { entries.removeValue(forKey: id) }
        guard let removed else { return false }
        // Отмена задачи приводит к graceful shutdown пула соединений.
        removed.runTask.cancel()
        return true
    }

    /// Закрывает все соединения.
    func removeAll() {
        let all: [Entry] = lock.withLock {
            let values = Array(entries.values)
            entries.removeAll()
            return values
        }
        all.forEach { $0.runTask.cancel() }
    }

    deinit {
        removeAll()
    }
}
