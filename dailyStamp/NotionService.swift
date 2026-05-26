import Foundation

enum NotionServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingConfiguration(String)
    case noTodayAttendance
    case serverError(code: Int, message: String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Notion URL is invalid."
        case .invalidResponse:
            return "Invalid response from Notion."
        case let .missingConfiguration(message):
            return message
        case .noTodayAttendance:
            return "오늘 출석 체크를 먼저 눌러주세요."
        case let .serverError(code, message):
            return "Notion error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse Notion response."
        }
    }
}

struct NotionDatabaseQueryResponse: Decodable {
    let results: [NotionPage]
}

struct NotionPage: Decodable {
    let id: String
}

struct NotionBlockChildrenResponse: Decodable {
    let results: [NotionBlock]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct NotionBlock: Decodable {
    let id: String
    let type: String
    let hasChildren: Bool
    let heading1: NotionRichTextContainer?
    let heading2: NotionRichTextContainer?
    let heading3: NotionRichTextContainer?
    let toDo: NotionToDoContent?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case hasChildren = "has_children"
        case heading1 = "heading_1"
        case heading2 = "heading_2"
        case heading3 = "heading_3"
        case toDo = "to_do"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        hasChildren = try container.decodeIfPresent(Bool.self, forKey: .hasChildren) ?? false
        heading1 = try container.decodeIfPresent(NotionRichTextContainer.self, forKey: .heading1)
        heading2 = try container.decodeIfPresent(NotionRichTextContainer.self, forKey: .heading2)
        heading3 = try container.decodeIfPresent(NotionRichTextContainer.self, forKey: .heading3)
        toDo = try container.decodeIfPresent(NotionToDoContent.self, forKey: .toDo)
    }
}

struct NotionRichTextContainer: Decodable {
    let richText: [NotionRichText]

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionToDoContent: Decodable {
    let richText: [NotionRichText]
    let checked: Bool

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
        case checked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        richText = try container.decodeIfPresent([NotionRichText].self, forKey: .richText) ?? []
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    }
}

struct NotionRichText: Decodable {
    let plainText: String?
    let text: NotionTextContent?

    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
        case text
    }
}

struct NotionTextContent: Decodable {
    let content: String?
}

private struct NotionErrorResponse: Decodable {
    let message: String?
}

final class NotionService {
    private let session: URLSession
    let baseURL = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"

    init(session: URLSession = .shared) {
        self.session = session
    }
}

extension NotionService {
    private static let blockFetchPageSize = 100
    private static let dayRangeISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    private static let todayCacheDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static var cachedTodayPageDateKey: String?
    private static var cachedTodayPageId: String?

    private func dayKey(for date: Date) -> String {
        Self.todayCacheDateFormatter.string(from: date)
    }

    private func cachedTodayPage(for date: Date) -> String? {
        let key = dayKey(for: date)
        guard Self.cachedTodayPageDateKey == key else { return nil }
        return Self.cachedTodayPageId
    }

    func cacheTodayPageId(_ pageId: String, for date: Date = .now) {
        Self.cachedTodayPageDateKey = dayKey(for: date)
        Self.cachedTodayPageId = pageId
    }

    func findTodayAttendancePageId(for date: Date = .now) async throws -> String? {
        if let cached = cachedTodayPage(for: date) {
            return cached
        }

        let databaseId = try readDatabaseId()
        guard let url = URL(string: "\(baseURL)/databases/\(databaseId)/query") else {
            throw NotionServiceError.invalidURL
        }

        let range = dayRange(for: date)
        let payload: [String: Any] = [
            "filter": [
                "and": [
                    [
                        "property": AppConfig.timestampPropertyName,
                        "date": [
                            "on_or_after": range.start
                        ]
                    ],
                    [
                        "property": AppConfig.timestampPropertyName,
                        "date": [
                            "before": range.end
                        ]
                    ]
                ]
            ],
            "sorts": [
                [
                    "property": AppConfig.timestampPropertyName,
                    "direction": "descending"
                ]
            ],
            "page_size": 1
        ]

        let data = try await sendJSONRequest(url: url, method: "POST", payload: payload)
        let response: NotionDatabaseQueryResponse = try decode(NotionDatabaseQueryResponse.self, from: data)

        guard let first = response.results.first else {
            return nil
        }
        cacheTodayPageId(first.id, for: date)
        return first.id
    }

    func fetchChildBlocks(pageId: String) async throws -> [NotionBlock] {
        var allBlocks: [NotionBlock] = []
        var nextCursor: String?

        repeat {
            var urlString = "\(baseURL)/blocks/\(pageId)/children?page_size=\(Self.blockFetchPageSize)"
            if let nextCursor {
                let encodedCursor = nextCursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? nextCursor
                urlString += "&start_cursor=\(encodedCursor)"
            }

            guard let url = URL(string: urlString) else {
                throw NotionServiceError.invalidURL
            }

            let data = try await sendJSONRequest(url: url, method: "GET")
            let response: NotionBlockChildrenResponse = try decode(NotionBlockChildrenResponse.self, from: data)

            allBlocks.append(contentsOf: response.results)
            if response.hasMore {
                nextCursor = response.nextCursor
            } else {
                nextCursor = nil
            }
        } while nextCursor != nil

        return allBlocks
    }
}

extension NotionService {
    func dayRange(for date: Date) -> (start: String, end: String) {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        return (
            Self.dayRangeISOFormatter.string(from: startOfDay),
            Self.dayRangeISOFormatter.string(from: nextDay)
        )
    }

    func sendJSONRequest(
        url: URL,
        method: String,
        payload: [String: Any]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        request.timeoutInterval = 20

        request.setValue("Bearer \(try readAccessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(from: data) ?? "Unknown error"
            throw NotionServiceError.serverError(code: httpResponse.statusCode, message: message)
        }

        return data
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NotionServiceError.parsingError
        }
    }
}

extension NotionService {
    private func parseErrorMessage(from data: Data) -> String? {
        let decoded = try? JSONDecoder().decode(NotionErrorResponse.self, from: data)
        return decoded?.message
    }

    func readAccessToken() throws -> String {
        do {
            return try AppConfig.notionApiToken()
        } catch {
            throw NotionServiceError.missingConfiguration(error.localizedDescription)
        }
    }

    func readDatabaseId() throws -> String {
        do {
            return try AppConfig.notionDatabaseId()
        } catch {
            throw NotionServiceError.missingConfiguration(error.localizedDescription)
        }
    }
}
