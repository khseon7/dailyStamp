import Foundation

extension NotionService {
    func fetchTodayTodos() async throws -> [TodoItem] {
        guard let pageId = try await findTodayAttendancePageId() else {
            return []
        }

        let blocks = try await fetchChildBlocks(pageId: pageId)
        return parseTodoBlocks(from: blocks)
    }

    func addTodoToTodayAttendance(title: String) async throws {
        guard let pageId = try await findTodayAttendancePageId() else {
            throw NotionServiceError.noTodayAttendance
        }
        let blocks = try await fetchChildBlocks(pageId: pageId)
        let afterBlockId = insertionAnchorBlockId(for: blocks)
        _ = try await appendTodoBlock(
            to: pageId,
            text: title,
            checked: false,
            after: afterBlockId
        )
    }

    func toggleTodo(blockId: String, isCompleted: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/blocks/\(blockId)") else {
            throw NotionServiceError.invalidURL
        }

        let payload: [String: Any] = [
            "to_do": [
                "checked": isCompleted
            ]
        ]

        _ = try await sendJSONRequest(url: url, method: "PATCH", payload: payload)
    }

    func updateTodoTitle(blockId: String, title: String, isCompleted: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/blocks/\(blockId)") else {
            throw NotionServiceError.invalidURL
        }

        let payload: [String: Any] = [
            "to_do": [
                "rich_text": [
                    [
                        "type": "text",
                        "text": [
                            "content": title
                        ]
                    ]
                ],
                "checked": isCompleted
            ]
        ]

        _ = try await sendJSONRequest(url: url, method: "PATCH", payload: payload)
    }
}

private extension NotionService {
    var todaySectionTitleCandidates: Set<String> {
        [
            normalizeSectionTitle(AppConfig.todayTodoSectionTitle),
            normalizeSectionTitle("오늘 할 일")
        ]
    }

    func appendTodoBlock(
        to pageId: String,
        text: String,
        checked: Bool,
        after afterBlockId: String? = nil
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/blocks/\(pageId)/children") else {
            throw NotionServiceError.invalidURL
        }

        var payload: [String: Any] = [
            "children": [
                [
                    "object": "block",
                    "type": "to_do",
                    "to_do": [
                        "rich_text": [
                            [
                                "type": "text",
                                "text": [
                                    "content": text
                                ]
                            ]
                        ],
                        "checked": checked
                    ]
                ]
            ]
        ]
        if let afterBlockId {
            payload["after"] = afterBlockId
        }

        let data = try await sendJSONRequest(url: url, method: "PATCH", payload: payload)
        let response: NotionBlockChildrenResponse = try decode(NotionBlockChildrenResponse.self, from: data)
        guard let first = response.results.first else {
            throw NotionServiceError.parsingError
        }

        return first.id
    }

    func parseTodoBlocks(from blocks: [NotionBlock]) -> [TodoItem] {
        let sectionTodos = extractTodos(from: todoBlocksInTodaySection(from: blocks))
        if !sectionTodos.isEmpty {
            return sectionTodos
        }

        // Fallback: if section parsing fails, still show all todos in page.
        return extractTodos(from: blocks)
    }

    func insertionAnchorBlockId(for blocks: [NotionBlock]) -> String? {
        guard let sectionRange = todaySectionRange(in: blocks) else {
            return nil
        }

        let sectionBlocks = Array(blocks[sectionRange])
        if let lastTodo = sectionBlocks.last(where: { $0.type == "to_do" }) {
            return lastTodo.id
        }

        return blocks[sectionRange.lowerBound].id
    }

    func todoBlocksInTodaySection(from blocks: [NotionBlock]) -> [NotionBlock] {
        guard let sectionRange = todaySectionRange(in: blocks) else {
            return []
        }

        let sectionBlocks = Array(blocks[sectionRange])
        return Array(sectionBlocks.dropFirst())
    }

    func todaySectionRange(in blocks: [NotionBlock]) -> ClosedRange<Int>? {
        guard let headingIndex = blocks.firstIndex(where: { isTodayTodoHeading($0) }) else {
            return nil
        }

        let endIndex: Int
        if headingIndex + 1 < blocks.count,
           let nextHeadingIndex = blocks[(headingIndex + 1)...].firstIndex(where: { isHeadingBlock($0) }) {
            endIndex = max(headingIndex, nextHeadingIndex - 1)
        } else {
            endIndex = blocks.count - 1
        }

        return headingIndex ... endIndex
    }

    func isTodayTodoHeading(_ block: NotionBlock) -> Bool {
        guard isHeadingBlock(block) else {
            return false
        }

        let text = plainText(fromRichTextArray: headingRichText(from: block))
        return todaySectionTitleCandidates.contains(normalizeSectionTitle(text))
    }

    func isHeadingBlock(_ block: NotionBlock) -> Bool {
        block.type == "heading_1" || block.type == "heading_2" || block.type == "heading_3"
    }

    func headingRichText(from block: NotionBlock) -> [NotionRichText]? {
        switch block.type {
        case "heading_1":
            return block.heading1?.richText
        case "heading_2":
            return block.heading2?.richText
        case "heading_3":
            return block.heading3?.richText
        default:
            return nil
        }
    }

    func normalizeSectionTitle(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    func extractTodos(from blocks: [NotionBlock]) -> [TodoItem] {
        var items: [TodoItem] = []
        items.reserveCapacity(blocks.count)

        for block in blocks {
            guard block.type == "to_do", let todo = block.toDo else {
                continue
            }
            items.append(
                TodoItem(
                    id: block.id,
                    title: plainText(fromRichTextArray: todo.richText),
                    isCompleted: todo.checked
                )
            )
        }

        return items
    }

    func plainText(fromRichTextArray richText: [NotionRichText]?) -> String {
        guard let richText else { return "" }
        return richText.compactMap { part -> String? in
            if let plainText = part.plainText {
                return plainText
            }
            if
                let text = part.text,
                let content = text.content
            {
                return content
            }
            return nil
        }.joined()
    }
}
