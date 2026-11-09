/// When the session locks itself (SPEC section 4): after 5 minutes with no interaction in
/// the foreground, or after 2 minutes in the background.
///
/// Pure, and it takes elapsed time rather than dates: the caller measures with a monotonic
/// clock (`ContinuousClock`), so setting the device clock back can't stop the lock.
public struct AutoLockPolicy: Hashable, Sendable {
    public var inactivityLimit: Duration
    public var backgroundLimit: Duration

    public init(inactivityLimit: Duration = .seconds(5 * 60), backgroundLimit: Duration = .seconds(2 * 60)) {
        self.inactivityLimit = inactivityLimit
        self.backgroundLimit = backgroundLimit
    }

    /// `idle`: time since the last touch, foreground or not.
    public func shouldLock(idle: Duration) -> Bool {
        idle >= inactivityLimit
    }

    /// `away`: time the app spent in the background.
    public func shouldLockOnReturn(away: Duration) -> Bool {
        away >= backgroundLimit
    }
}
