# ADR-020: The app root follows the session state

- **Status:** Proposed
- **Date:** 2026-11-08
- **Related:** SPEC sections 4 and 6, ADR-002, ADR-003, ADR-019

## Context

Phase 5 added four top-level states: signed out, needs PIN, locked and unlocked. Many events move between them: sign-in, PIN or Face ID, inactivity and background timeouts, a refused token refresh, a relaunch. A banking app must never allow "back" from the lock screen to balances, or keep balances alive behind a cover.

## Decision

`AppCoordinator` holds one `root` value, set only by `apply(SessionState)`, and `AppRootView` shows exactly one flow for it. Flows are swapped, never stacked.

- The mapping is fixed: `.signedOut` → Sign in, `.needsPIN` → Create PIN, `.locked` → Unlock, `.unlocked` → Accounts, plus `.launching` while the Keychain is read.
- Every event ends in `SessionManaging` returning a `SessionState`, which goes to `apply`. Features report it through `onSessionChange` and never navigate between flows themselves.
- Inside a flow, navigation is a normal `NavigationStack` owned by that flow's router (ADR-003).
- Locking tears down `AccountsFlowView` and its view models. `accountsRouter` survives a lock, so the user returns to the same screen with freshly loaded data. Sign-out resets it.
- The privacy cover is a separate overlay for the app switcher only, and isn't the lock.

## Alternatives considered

### Option A: One navigation stack for all screens
- Sign in → Create PIN → Accounts pushed in order, with the lock screen pushed on top.
- Lost because Back and swipe-back would lead to screens the session no longer allows, and every event would need its own push or pop sequence based on what is currently on screen.

### Option B: Lock screen as a `.fullScreenCover`
- Accounts stays mounted, and a cover hides it while locked.
- Lost because balances stay in memory and the views keep loading underneath. Safety then depends on the cover never being dismissed by mistake.

## Consequences

- **Easier:** the screen is a pure function of the session, so `AppCoordinatorTests` check `root` without driving UI. A new lock trigger only has to produce a `SessionState`.
- **Harder:** no push animation between flows (a `.transition` can add one). The place inside Accounts is kept only because the router outlives the view.
- **Revisit when:** something must show over a locked session (e.g. a Phase 6 transfer prompt). That needs its own state, not a stacked screen.
