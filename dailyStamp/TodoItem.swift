import Foundation

struct TodoItem: Identifiable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
}
