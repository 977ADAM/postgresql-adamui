//
//  View+Extensions.swift
//  postgresql-adamui
//
//  Небольшие вспомогательные модификаторы для SwiftUI.
//

import SwiftUI

extension View {

    /// Показывает алерт с текстом ошибки, привязанный к необязательной строке.
    func errorAlert(message: Binding<String?>, title: String = "Ошибка") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { text in
            Text(text)
        }
    }

    /// Общая «карточка» для секций формы.
    func formCard() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }

    /// Условное применение модификатора без изменения типа представления.
    @ViewBuilder
    func `if`<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Моноширинный шрифт для SQL-текста.
    func sqlFont(size: CGFloat = 13) -> some View {
        font(.system(size: size, design: .monospaced))
    }
}

extension Binding where Value == Bool {
    /// Удобное включение булева биндинга по необязательному значению.
    static func isPresent(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding<Bool>(
            get: { value.wrappedValue == true },
            set: { value.wrappedValue = $0 ? true : nil }
        )
    }
}
