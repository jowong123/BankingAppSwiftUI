import Domain
import Foundation
import Testing

@testable import AccountsFeature

/// Scripted `AccountsRepository`. Records every call.
///
/// A gate holds one specific call (e.g. "the first request for cursor c2") until the
/// test opens it. Only that call waits: if the code under test wrongly sends an extra
/// request, it goes straight through and the test fails instead of hanging.
actor FakeAccountsRepository: AccountsRepository {
    private var accountsResults: [Result<[Account], DataSourceError>]
    private var pages: [String: Result<TransactionPage, DataSourceError>] = [:]
    private(set) var accountsCalls = 0
    private(set) var transactionCursors: [String?] = []
    private var accountsGates: [Int: Gate] = [:]
    private var pageGates: [String: Gate] = [:]
    private var pageRequestCounts: [String: Int] = [:]

    init(accounts: [Result<[Account], DataSourceError>] = [.success(sampleAccounts)]) {
        self.accountsResults = accounts
    }

    /// The last result repeats.
    func setAccounts(_ results: [Result<[Account], DataSourceError>]) {
        accountsResults = results
    }

    /// `cursor` nil is the first page.
    func setPage(cursor: String?, _ result: Result<TransactionPage, DataSourceError>) {
        pages[cursor ?? firstPageKey] = result
    }

    /// Holds the `call`-th `accounts()` request (1-based).
    func holdAccounts(call: Int, with gate: Gate) {
        accountsGates[call] = gate
    }

    /// Holds the `occurrence`-th request for this cursor (1-based).
    func holdPage(cursor: String?, occurrence: Int = 1, with gate: Gate) {
        pageGates["\(cursor ?? firstPageKey)#\(occurrence)"] = gate
    }

    func accounts() async throws(DataSourceError) -> [Account] {
        accountsCalls += 1
        await accountsGates[accountsCalls]?.wait()
        let next = accountsResults.count > 1 ? accountsResults.removeFirst() : accountsResults[0]
        return try next.get()
    }

    func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
        transactionCursors.append(cursor)
        let key = cursor ?? firstPageKey
        pageRequestCounts[key, default: 0] += 1
        await pageGates["\(key)#\(pageRequestCounts[key, default: 0])"]?.wait()
        guard let result = pages[cursor ?? firstPageKey] else {
            throw .invalidData
        }
        return try result.get()
    }

    private let firstPageKey = "<first>"
}

/// Suspends callers until `open()`.
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

/// Lets other tasks run until `condition` holds, so a test can wait for a call to
/// reach the fake. Fails the test instead of hanging.
@MainActor func waitUntil(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<1_000 {
        if await condition() {
            return
        }
        await Task.yield()
    }
    Issue.record("condition never became true")
}

let sampleAccounts = [
    Account(
        id: "acc_sgd", balance: Money(amountMinor: 1_250_000, currency: .sgd), updatedAt: Date(timeIntervalSince1970: 0)
    ),
    Account(
        id: "acc_jpy", balance: Money(amountMinor: 150_000, currency: .jpy), updatedAt: Date(timeIntervalSince1970: 0)),
]

func transaction(_ id: String, minor: Int64 = -450) -> AccountTransaction {
    AccountTransaction(
        id: id,
        accountID: "acc_sgd",
        amount: Money(amountMinor: minor, currency: .sgd),
        description: "Kopi Corner",
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

func page(_ ids: [String], next: String?) -> Result<TransactionPage, DataSourceError> {
    let items = ids.map { id in
        transaction(id)
    }
    return .success(TransactionPage(items: items, nextCursor: next))
}

/// Counts calls to an output closure such as `onSessionExpired`.
@MainActor final class CallCounter {
    private(set) var calls = 0

    func record() {
        calls += 1
    }
}
