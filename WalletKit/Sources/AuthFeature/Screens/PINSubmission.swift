import Foundation

/// One completed PIN entry, handed from the PIN pad to a screen's `.task(id:)`. A fresh
/// `id` each time, so entering the same PIN twice (create, then confirm) runs twice.
struct PINSubmission: Equatable {
    let id = UUID()
    let pin: String
}
