import Foundation

/// JSON settings shared by every Wallet API call and by `backend/openapi.yaml`:
/// camelCase keys as declared, ISO 8601 dates, sorted keys so request bodies are stable.
enum WalletJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
