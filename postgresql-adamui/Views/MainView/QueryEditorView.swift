//
//  QueryEditorView.swift
//  postgresql-adamui
//
//  Редактор SQL и таблица результатов.
//

import SwiftUI

struct QueryEditorView: View {

    @ObservedObject var viewModel: QueryViewModel
    let onExecute: () -> Void
    let onClear: () -> Void

    var body: some View {
        VSplitView {
            editor
                .frame(minHeight: 160)

            results
                .frame(minHeight: 160)
        }
    }

    // MARK: - Редактор

    private var editor: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

            TextEditor(text: $viewModel.queryText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Button(action: onExecute) {
                Label("Выполнить", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExecute)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Выполнить запрос (⌘↩)")

            Button(action: onClear) {
                Label("Очистить", systemImage: "eraser")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.queryText.isEmpty)

            if viewModel.isExecuting {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            if viewModel.isMutating {
                Label("Изменяет данные", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Результаты

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Результат")
                    .font(.headline)
                Spacer()
                if let result = viewModel.currentResult, result.hasRows {
                    Text("\(result.columns.count) кол., \(result.rowCount) стр.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let result = viewModel.currentResult {
                ResultsTableView(result: result)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Результат появится здесь")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    QueryEditorView(viewModel: QueryViewModel(), onExecute: { }, onClear: { })
        .frame(width: 800, height: 560)
}
