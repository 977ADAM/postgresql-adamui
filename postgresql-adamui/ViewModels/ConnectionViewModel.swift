//
//  ConnectionViewModel.swift
//  postgresql-adamui
//
//  Состояние экрана подключений: список сохранённых подключений,
//  форма редактирования и операции подключения.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ConnectionViewModel: ObservableObject {

    // MARK: - Список подключений

    @Published private(set) var connections: [Connection] = []
    @Published var selectedConnection: Connection?

    // MARK: - Форма

    @Published var draft: Connection = .makeDefault()
    /// Пароль хранится отдельно от черновика, чтобы не читать Keychain на каждое нажатие.
    @Published var password: String = ""
    /// `true`, если для черновика в Keychain уже есть пароль.
    @Published private(set) var hasStoredPassword = false
    /// `true`, когда форма редактирует существующее подключение, а не новое.
    @Published private(set) var isEditingExisting = false

    // MARK: - Состояние операций

    @Published var isConnecting = false
    @Published var isTesting = false
    @Published var connectionError: String?
    @Published var showError = false
    /// Заголовок алерта: «Ошибка» или «Готово».
    @Published var alertTitle = "Ошибка"
    /// Подключение, с которым установлено соединение: переключает экран на рабочую область.
    @Published var activeConnection: Connection?

    // MARK: - Зависимости

    private let connectionManager: ConnectionManager
    private let databaseService: DatabaseService
    private let keychain: KeychainService

    // MARK: - Инициализация

    init(
        connectionManager: ConnectionManager = .shared,
        databaseService: DatabaseService = .shared,
        keychain: KeychainService = .shared
    ) {
        self.connectionManager = connectionManager
        self.databaseService = databaseService
        self.keychain = keychain
        loadSavedConnections()
    }

    // MARK: - Вычисляемые свойства

    /// `true`, если черновик проходит валидацию.
    var canSubmit: Bool {
        draft.isValid && !isConnecting && !isTesting
    }

    /// Подсказка о проблеме в форме.
    var validationMessage: String? {
        draft.validationError?.errorDescription
    }

    /// `true`, если подключение сейчас открыто.
    var isConnected: Bool {
        databaseService.isConnected
    }

    /// Текст кнопки «Подключиться» с учётом состояния.
    var connectButtonTitle: String {
        isConnecting ? "Подключение…" : "Подключиться"
    }

    // MARK: - Работа со списком

    /// Выбирает подключение из списка и загружает его в форму.
    func selectConnection(_ connection: Connection) {
        selectedConnection = connection
        draft = connection
        isEditingExisting = true
        password = keychain.getPassword(for: connection.id) ?? ""
        hasStoredPassword = !password.isEmpty
    }

    /// Готовит форму для нового подключения.
    func beginNewConnection() {
        selectedConnection = nil
        draft = .makeDefault()
        isEditingExisting = false
        password = ""
        hasStoredPassword = false
    }

    /// Сохраняет черновик в список и в Keychain.
    @discardableResult
    func saveDraft() -> Connection? {
        guard draft.isValid else {
            present(error: draft.validationError ?? .invalidData)
            return nil
        }

        var connection = draft
        // Соединение не переносится в список: это состояние сеанса.
        connection.isConnected = false

        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            // Дата последнего успешного подключения сохраняется.
            connection.lastConnected = connections[index].lastConnected
            connections[index] = connection
        } else {
            connections.append(connection)
        }

        if password.isEmpty {
            keychain.deletePassword(for: connection.id)
        } else {
            keychain.savePassword(password, for: connection.id)
        }
        hasStoredPassword = !password.isEmpty

        selectedConnection = connection
        draft = connection
        isEditingExisting = true
        persistConnections()
        return connection
    }

    /// Удаляет подключение из списка и стирает его пароль.
    func deleteConnection(_ connection: Connection) {
        if activeConnection?.id == connection.id {
            disconnect()
        }
        connections.removeAll { $0.id == connection.id }
        keychain.deletePassword(for: connection.id)
        persistConnections()

        if selectedConnection?.id == connection.id {
            beginNewConnection()
        }
    }

    /// Удаляет выбранное в списке подключение.
    func deleteSelectedConnection() {
        guard let selectedConnection else { return }
        deleteConnection(selectedConnection)
    }

    // MARK: - Операции с соединением

    /// Проверяет черновик без сохранения в список.
    func testConnection() async {
        guard draft.isValid else {
            present(error: draft.validationError ?? .invalidData)
            return
        }

        isTesting = true
        defer { isTesting = false }

        do {
            try await databaseService.testConnection(with: draft, password: password)
            present(info: "Подключение к \(draft.endpoint) успешно")
        } catch {
            present(error: error)
        }
    }

    /// Сохраняет черновик и открывает соединение.
    func connect() async {
        guard let connection = saveDraft() else { return }

        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            try await databaseService.connect(with: connection, password: password)
            markConnected(connection)
            activeConnection = connection
        } catch {
            present(error: error)
        }
    }

    /// Закрывает активное соединение.
    func disconnect() {
        databaseService.disconnect()

        if let id = activeConnection?.id,
           let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].lastConnected = Date()
        }
        connections.indices.forEach { connections[$0].isConnected = false }
        persistConnections()

        activeConnection = nil
        selectedConnection = nil
    }

    /// Убирает текст ошибки (например, после закрытия алерта).
    func clearError() {
        connectionError = nil
        showError = false
    }

    // MARK: - Private

    private func markConnected(_ connection: Connection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index].isConnected = true
        connections[index].lastConnected = Date()
        selectedConnection = connections[index]
        draft = connections[index]
        persistConnections()
    }

    /// Загрузка списка из `UserDefaults`.
    private func loadSavedConnections() {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.Storage.connectionsKey),
              let decoded = try? JSONDecoder().decode([Connection].self, from: data) else {
            return
        }
        connections = decoded.map { connection in
            var restored = connection
            // Состояние соединения не переносится между запусками.
            restored.isConnected = false
            return restored
        }
        // Подчищаем пароли удалённых подключений.
        keychain.prune(keeping: connections.map(\.id))
    }

    /// Сохранение списка в `UserDefaults`.
    private func persistConnections() {
        guard let encoded = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(encoded, forKey: AppConstants.Storage.connectionsKey)
    }

    private func present(error: Error) {
        alertTitle = "Ошибка"
        connectionError = error.displayMessage
        showError = true
    }

    private func present(error: AppError) {
        alertTitle = "Ошибка"
        connectionError = error.errorDescription ?? error.localizedDescription
        showError = true
    }

    private func present(info: String) {
        alertTitle = "Готово"
        connectionError = info
        showError = true
    }
}
