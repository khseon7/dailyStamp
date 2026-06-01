import Foundation
import Combine

@MainActor
final class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var inputText: String = ""
    @Published var editingTodoId: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastUpdatedAt: Date?

    private let notionService: NotionService

    init(notionService: NotionService) {
        self.notionService = notionService
    }

    convenience init() {
        self.init(notionService: NotionService())
    }

    func loadTodos() async {
        await runTask {
            try await self.refreshTodos()
        }
    }

    func addTodo() async {
        let title = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        await runTask {
            if let editingId = self.editingTodoId {
                let currentState = self.todos.first { $0.id == editingId }?.isCompleted ?? false
                try await self.notionService.updateTodoTitle(
                    blockId: editingId,
                    title: title,
                    isCompleted: currentState
                )
            } else {
                try await self.notionService.addTodoToTodayAttendance(title: title)
            }

            self.inputText = ""
            self.editingTodoId = nil
            try await self.refreshTodos()
        }
    }

    func markAttendance() async {
        await runTask {
            try await self.notionService.markAttendance()
            try await self.refreshTodos()
        }
    }

    func complete(todo: TodoItem) async {
        await runTask {
            try await self.notionService.toggleTodo(
                blockId: todo.id,
                isCompleted: !todo.isCompleted
            )
            try await self.refreshTodos()
        }
    }

    func delete(todo: TodoItem) async {
        await runTask {
            try await self.notionService.deleteTodo(blockId: todo.id)
            if self.editingTodoId == todo.id {
                self.cancelEditing()
            }
            try await self.refreshTodos()
        }
    }

    func beginEditing(todo: TodoItem) {
        inputText = todo.title
        editingTodoId = todo.id
    }

    func cancelEditing() {
        inputText = ""
        editingTodoId = nil
    }

    private func refreshTodos() async throws {
        let items = try await notionService.fetchTodayTodos()
        todos = items
        lastUpdatedAt = Date()
    }

    private func runTask(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Notion 서버 주소를 찾지 못했습니다. 네트워크 권한/인터넷 연결을 확인해주세요."
            case .notConnectedToInternet:
                return "인터넷 연결이 없습니다. 네트워크 상태를 확인해주세요."
            case .timedOut:
                return "요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요."
            case .cannotConnectToHost:
                return "Notion 서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
