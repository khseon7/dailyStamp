import Foundation

extension NotionService {
    func markAttendance(date: Date = .now) async throws {
        if try await findTodayAttendancePageId(for: date) != nil {
            return
        }

        let pageId = try await createAttendancePage(title: AppConfig.attendancePageTitle, date: date)
        cacheTodayPageId(pageId, for: date)
    }
}

private extension NotionService {
    func buildCreatePayload(title: String, date: Date) throws -> [String: Any] {
        let databaseId = try readDatabaseId()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        return [
            "parent": [
                "database_id": databaseId
            ],
            "properties": [
                AppConfig.titlePropertyName: [
                    "title": [
                        [
                            "text": [
                                "content": title
                            ]
                        ]
                    ]
                ],
                AppConfig.completedPropertyName: [
                    "checkbox": false
                ],
                AppConfig.timestampPropertyName: [
                    "date": [
                        "start": dateString
                    ]
                ]
            ]
        ]
    }

    func createAttendancePage(title: String, date: Date) async throws -> String {
        guard let url = URL(string: "\(baseURL)/pages") else {
            throw NotionServiceError.invalidURL
        }

        var payload = try buildCreatePayload(title: title, date: date)
        payload["template"] = [
            "type": "default"
        ]
        let data = try await sendJSONRequest(url: url, method: "POST", payload: payload)
        let page: NotionPage = try decode(NotionPage.self, from: data)
        return page.id
    }
}
