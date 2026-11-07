import Foundation

public struct HTTPResponse: Hashable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }

    public func header(_ name: String) -> String? {
        headers.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}
