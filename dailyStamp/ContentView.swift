import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TodoViewModel()
    @FocusState private var isInputFocused: Bool
    private let rowHeight: CGFloat = 30
    private let minListHeight: CGFloat = 72
    private let maxListHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Stamp")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.markAttendance() }
                } label: {
                    Label("출석 체크", systemImage: "checkmark.circle")
                }
                .disabled(viewModel.isLoading)
            }

            HStack(spacing: 8) {
                TextField("오늘 할 일 입력", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        submitTodo()
                    }

                Button(viewModel.editingTodoId == nil ? "추가" : "저장") {
                    submitTodo()
                }
                .disabled(!canSubmitTodo || viewModel.isLoading)
            }

            if viewModel.editingTodoId != nil {
                Button("수정 취소") {
                    viewModel.cancelEditing()
                    isInputFocused = false
                }
                .font(.caption)
                .buttonStyle(.plain)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.todos.isEmpty {
                        Text("오늘 할 일이 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.todos) { todo in
                            todoRow(todo)
                        }
                    }
                }
            }
            .frame(height: todoListHeight)

            HStack {
                if let lastUpdatedAt = viewModel.lastUpdatedAt {
                    Text("업데이트: \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("업데이트: -")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.loadTodos() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("새로고침")
                .disabled(viewModel.isLoading)
            }
        }
        .padding(12)
        .frame(width: 250)
        .task {
            await viewModel.loadTodos()
        }
    }

    private var canSubmitTodo: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var todoListHeight: CGFloat {
        let rawHeight = CGFloat(max(viewModel.todos.count, 1)) * rowHeight
        return min(max(rawHeight, minListHeight), maxListHeight)
    }

    private func submitTodo() {
        Task { await viewModel.addTodo() }
        isInputFocused = false
    }

    @ViewBuilder
    private func todoRow(_ todo: TodoItem) -> some View {
        let visibleTitle = todo.title.isEmpty ? " " : todo.title

        HStack(spacing: 8) {
            Button {
                Task { await viewModel.complete(todo: todo) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            Text(visibleTitle)
                .strikethrough(todo.isCompleted, color: .secondary)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.beginEditing(todo: todo)
                isInputFocused = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            Button {
                Task { await viewModel.delete(todo: todo) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
}
