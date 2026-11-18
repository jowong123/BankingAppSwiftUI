import Foundation

/// The small part of CBOR (RFC 8949) that App Attest objects use: integers, byte and text
/// strings, arrays, and maps with text keys. Anything else (floats, tags, indefinite
/// lengths) is refused rather than skipped, so a malformed object can't slip past.
enum CBOR: Equatable, Sendable {
    case unsigned(UInt64)
    case negative(UInt64)
    case bytes(Data)
    case text(String)
    case array([CBOR])
    case map([String: CBOR])
    case bool(Bool)
    case null

    struct DecodingError: Error, Equatable {
        let reason: String
    }

    /// Decodes exactly one item; trailing bytes are an error.
    static func decode(_ data: Data) throws -> CBOR {
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.item(depth: 0)
        guard reader.offset == reader.bytes.count else {
            throw DecodingError(reason: "trailing bytes")
        }
        return value
    }

    subscript(key: String) -> CBOR? {
        guard case .map(let map) = self else {
            return nil
        }
        return map[key]
    }

    var bytesValue: Data? {
        guard case .bytes(let data) = self else {
            return nil
        }
        return data
    }

    var textValue: String? {
        guard case .text(let text) = self else {
            return nil
        }
        return text
    }

    var arrayValue: [CBOR]? {
        guard case .array(let items) = self else {
            return nil
        }
        return items
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        /// Nesting is bounded, so a hostile object can't exhaust the stack.
        static let maxDepth = 8
        /// Larger than any App Attest object, small enough that a forged length can't
        /// make the server allocate much.
        static let maxLength: UInt64 = 64 * 1024

        mutating func item(depth: Int) throws -> CBOR {
            guard depth <= Self.maxDepth else {
                throw DecodingError(reason: "nested too deeply")
            }
            let initial = try byte()
            let major = initial >> 5
            let info = initial & 0x1F
            switch major {
            case 0:
                return .unsigned(try argument(info))
            case 1:
                return .negative(try argument(info))
            case 2:
                return .bytes(Data(try take(try length(info))))
            case 3:
                guard let text = String(bytes: try take(try length(info)), encoding: .utf8) else {
                    throw DecodingError(reason: "invalid UTF-8")
                }
                return .text(text)
            case 4:
                return .array(try array(count: try length(info), depth: depth))
            case 5:
                return .map(try map(count: try length(info), depth: depth))
            case 7:
                return try simple(info)
            default:
                throw DecodingError(reason: "unsupported major type \(major)")
            }
        }

        private mutating func array(count: Int, depth: Int) throws -> [CBOR] {
            var items: [CBOR] = []
            for _ in 0..<count {
                items.append(try item(depth: depth + 1))
            }
            return items
        }

        private mutating func map(count: Int, depth: Int) throws -> [String: CBOR] {
            var map: [String: CBOR] = [:]
            for _ in 0..<count {
                guard case .text(let key) = try item(depth: depth + 1) else {
                    throw DecodingError(reason: "map key is not text")
                }
                guard map[key] == nil else {
                    throw DecodingError(reason: "duplicate map key")
                }
                map[key] = try item(depth: depth + 1)
            }
            return map
        }

        private func simple(_ info: UInt8) throws -> CBOR {
            switch info {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22: return .null
            default: throw DecodingError(reason: "unsupported simple value")
            }
        }

        private mutating func length(_ info: UInt8) throws -> Int {
            let value = try argument(info)
            guard value <= Self.maxLength, value <= UInt64(bytes.count - offset) else {
                throw DecodingError(reason: "length out of range")
            }
            return Int(value)
        }

        private mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24:
                return UInt64(info)
            case 24, 25, 26, 27:
                let count = 1 << Int(info - 24)
                return try take(count).reduce(0) {
                    $0 << 8 | UInt64($1)
                }
            default:
                throw DecodingError(reason: "indefinite or reserved length")
            }
        }

        private mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else {
                throw DecodingError(reason: "unexpected end")
            }
            defer {
                offset += 1
            }
            return bytes[offset]
        }

        private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, count <= bytes.count - offset else {
                throw DecodingError(reason: "unexpected end")
            }
            defer {
                offset += count
            }
            return bytes[offset..<offset + count]
        }
    }
}
