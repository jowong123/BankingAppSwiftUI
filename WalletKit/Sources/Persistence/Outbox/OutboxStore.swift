import Domain
import Foundation
import SwiftData

/// The outbox's storage: SwiftData behind its own serial executor (`@ModelActor`), so the
/// non-Sendable `ModelContext` never leaves it. Takes and returns `Transfer` values only.
@ModelActor
actor OutboxStore {
    /// Inserts `transfer`, or returns the one already stored under its ID.
    func insertIfAbsent(_ transfer: Transfer) throws -> Transfer {
        if let existing = try record(transfer.id)?.transfer() {
            return existing
        }
        modelContext.insert(try TransferRecord(transfer))
        try modelContext.save()
        return transfer
    }

    func update(_ transfer: Transfer) throws {
        guard let record = try record(transfer.id) else {
            return
        }
        record.update(from: transfer)
        try modelContext.save()
    }

    func transfer(_ id: UUID) throws -> Transfer? {
        try record(id)?.transfer()
    }

    /// Every transfer that isn't Completed or Failed, oldest first.
    func unfinished() throws -> [Transfer] {
        let finished = [TransferState.completed.rawValue, TransferState.failed.rawValue]
        let descriptor = FetchDescriptor<TransferRecord>(
            predicate: #Predicate {
                !finished.contains($0.state)
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).compactMap {
            $0.transfer()
        }
    }

    /// Deletes Completed and Failed transfers.
    func removeFinished() throws {
        let finished = [TransferState.completed.rawValue, TransferState.failed.rawValue]
        try modelContext.delete(
            model: TransferRecord.self,
            where: #Predicate {
                finished.contains($0.state)
            })
        try modelContext.save()
    }

    private func record(_ id: UUID) throws -> TransferRecord? {
        var descriptor = FetchDescriptor<TransferRecord>(
            predicate: #Predicate {
                $0.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

extension OutboxStore {
    /// The store file lives in its own folder. On iOS the folder gets `.complete` file
    /// protection before anything is written, so the database and its journal files (which
    /// inherit it) can't be read while the phone is locked. It is also left out of backups:
    /// a pending transfer belongs to this device's session (ADR-009).
    ///
    /// - Parameter directory: `nil` keeps everything in memory, for tests and previews.
    static func make(directory: URL?) throws -> OutboxStore {
        let schema = Schema([TransferRecord.self])
        let configuration: ModelConfiguration
        if var directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: directory.path()
                )
            #endif
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "outbox.store"))
        } else {    
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return OutboxStore(modelContainer: try ModelContainer(for: schema, configurations: [configuration]))
    }
}
