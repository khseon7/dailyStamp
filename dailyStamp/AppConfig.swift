import Foundation

enum AppConfigError: LocalizedError {
    case missing(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .missing(key):
            return "앱 설정 누락: \(key) 값을 찾을 수 없습니다."
        case let .invalid(key):
            return "앱 설정 오류: \(key) 값이 비어 있거나 예시 값입니다."
        }
    }
}

enum AppConfig {
    static func notionApiToken() throws -> String {
        try require("NOTION_ACCESS_TOKEN")
    }

    static func notionDatabaseId() throws -> String {
        try require("NOTION_DATABASE_ID")
    }

    // Notion database property names used by this app.
    static let titlePropertyName = "이름"
    static let completedPropertyName = "완료"
    static let timestampPropertyName = "기록시간"
    static let attendancePageTitle = "출석 체크"
    static let todayTodoSectionTitle = "오늘 할일"
    private static let bundledSecrets = loadBundledSecrets()

    private static func require(_ key: String) throws -> String {
        let infoValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let value = infoValue ?? bundledSecrets[key]

        guard let value else {
            throw AppConfigError.missing(key)
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("xxxxxxxx") else {
            throw AppConfigError.invalid(key)
        }
        return trimmed
    }

    private static func loadBundledSecrets() -> [String: String] {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "xcconfig"),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            return [:]
        }

        var parsed: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                parsed[key] = value
            }
        }
        return parsed
    }
}
