# Development guide

How to run, use and test Wallet. For the design and the reasons behind it, see the [README](../README.md) and [`docs/adr/`](adr).

- [Requirements](#requirements)
- [Run the backend](#run-the-backend)
- [Run the app](#run-the-app)
- [Using the app](#using-the-app)
- [On a real iPhone](#on-a-real-iphone)
- [Sandbox data](#sandbox-data)
- [Configuration](#configuration)
- [Launch arguments](#launch-arguments)
- [Tests and lint](#tests-and-lint)

## Requirements

- macOS with Xcode 26 (Swift 6 toolchain)
- An iOS 17+ simulator, such as iPhone 16

## Run the backend

```bash
cd backend
ATTEST_MODE=sandbox swift run WalletBackend serve
```

The API runs on `http://127.0.0.1:8080`. The first run creates `backend/wallet-sandbox.sqlite` and fills it with the [sandbox data](#sandbox-data). To start again from fresh data, stop the server and delete that file.

`ATTEST_MODE=sandbox` is needed because the simulator can't produce App Attest. The server won't start until you choose an attestation mode, so the check can't be left off by accident.

## Run the app

1. Open `Wallet.xcodeproj` and choose the **Wallet** scheme and an iOS simulator.
2. Press **Run** (⌘R). The Debug build talks to `http://127.0.0.1:8080`.
3. In the Simulator menu, turn on **Features → Face ID → Enrolled**. Without it, the app signs in as view only and can't send money.

**No backend?** Add `-mockServer` under **Product → Scheme → Edit Scheme → Run → Arguments → Arguments Passed On Launch**. The app then uses an in-memory fake bank. It accepts any email (the password `wrong` is refused) and approves transfers without a Face ID prompt.

## Using the app

### Sign in

1. Sign in with `demo@wallet.test` / `sandbox-demo`. Behind the scenes, the app creates a signing key and registers it with the server before it gets a session.
2. Create a 6-digit app PIN. After 5 wrong tries the session is wiped.

### Lock and unlock

- The app locks after 5 minutes of inactivity, or 2 minutes in the background.
- Unlock with Face ID (**Features → Face ID → Matching Face**) or your PIN.
- In the app switcher, a privacy cover hides your balances.

### Accounts

- Balances in SGD, USD, JPY and KWD.
- Tap an account to see its history. More pages load as you scroll, and you can pull to refresh.
- When offline, the app says so and offers Retry instead of showing old numbers.

### Send money

1. **Send money** → choose a recipient → enter an amount.
2. **Review** shows the rate, the fee, what the recipient gets, and a 30-second countdown.
3. Tap **Send** and approve with Face ID (**Matching Face**).
4. The status screen follows the transfer to Completed. The sandbox settles 3 seconds after the confirm.

| Try | What happens |
|---|---|
| Kill the app while it says "Sending", then reopen it | The outbox resumes and finishes the same transfer once. You don't sign again. |
| Double-tap **Send** | Only one transfer is created. |
| Send to **Test: always declined** | The transfer is declined at settlement and refunded. |
| Answer the prompt with **Non-matching Face**, or cancel it | Nothing is sent. |
| Turn **Features → Face ID → Enrolled** off and on again, then open Send money | "Face ID has changed". **Sign in again** creates a new key. |
| Wait on Review until the countdown ends | A new rate is shown before you can send. |

## On a real iPhone

1. Set `WalletAPIBaseURL` in `Config/Wallet-Debug.plist` to your Mac's local network address. The phone can't reach `127.0.0.1`.
2. Sign the app with a paid Apple developer team that has the **App Attest** capability.
3. Start the backend with App Attest checks on:

   ```bash
   APP_ATTEST_APP_ID=<TeamID>.jw.Wallet APP_ATTEST_ENV=development swift run WalletBackend serve
   ```

## Sandbox data

All of this is fake seed data, created on the backend's first run.

| | |
|---|---|
| Sign-in | `demo@wallet.test` / `sandbox-demo` |
| Second user (for isolation tests) | `other@wallet.test` / `sandbox-other` |
| Accounts | SGD 12,500.00 · USD 3,200.00 · JPY 150,000 · KWD 120.500 |
| Recipients | Alice Tan (USD) · Kenji Sato (JPY) · Marie Dubois (EUR) · Omar Al-Sabah (KWD) · Test: always declined (EUR) |

The API is described in [`backend/openapi.yaml`](../backend/openapi.yaml).

## Configuration

### Backend environment variables

Set these in Terminal, in front of the command that starts the server.

| Variable | Default | Purpose |
|---|---|---|
| `ATTEST_MODE` | none | `sandbox` skips App Attest, for the simulator. Either this or `APP_ATTEST_APP_ID` is required. |
| `APP_ATTEST_APP_ID` | none | `<TeamID>.<bundle ID>`. Turns on App Attest checks for real devices. |
| `APP_ATTEST_ENV` | production | `development` also accepts keys from Debug builds. |
| `DATABASE_PATH` | `wallet-sandbox.sqlite` | The SQLite file. |
| `SIMULATION_HEADERS` | off | `on` enables the `X-Sim-Delay` and `X-Sim-Fail` headers for injecting faults. |

### App build settings

| Setting | Where | Notes |
|---|---|---|
| `WalletAPIBaseURL` | `Config/Wallet-Debug.plist`, `Config/Wallet-Release.plist` | The backend URL for each build configuration. |
| `WalletAPIPins` | the same plists | SPKI SHA-256 pins: at least two, the current key and a backup. Empty in Release until a hosted server exists, so Release fails closed. |
| App Attest entitlement | `Config/Wallet-*.entitlements` | `development` in Debug, `production` in Release. |

## Launch arguments

These are mainly for UI tests. A UI test runs the app in a separate process, so launch arguments are the way it puts the app into a known state. They also help while developing. All of them are compiled out of Release builds (`#if DEBUG`), and none of them weakens a check on the real server.

Add them under **Edit Scheme → Run → Arguments → Arguments Passed On Launch**, not under Environment Variables.

| Argument | Effect |
|---|---|
| `-mockServer` | Use the in-memory fake bank instead of the backend. |
| `-uiTesting` | No artificial delays in the mock. |
| `-simulateOffline` | The mock behaves as if there's no connection. |
| `-signing keyInvalidated` / `-signing biometryNotSetUp` | The mock signer acts like a phone whose Face ID changed, or has none. |
| `-quoteSeconds <n>` | The mock quote's lifetime. |
| `-transferDelay <n>` | How long the mock takes to settle. |
| `-autoLockSeconds <n>` | A shorter auto-lock. |
| `-keepMockSession` | Keep the mock session across a relaunch. |
| `-resetSession` | Start signed out. |

## Tests and lint

```bash
# Swift package with all app modules, plus the import check
cd WalletKit && swift test --explicit-target-dependency-import-check error

# Generic HTTP client
cd NetworkingKit && swift test

# Backend
cd backend && swift test

# App unit tests and UI tests (against the mock)
xcodebuild test -project Wallet.xcodeproj -scheme Wallet \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Lint, format and module boundaries
swiftlint lint --strict
swift format lint --strict --recursive Wallet WalletTests WalletUITests WalletKit NetworkingKit backend/Sources backend/Tests
scripts/check-module-boundaries.sh
```

`EndToEndUITests` signs in against the real backend. It is skipped unless the backend is running and the credentials are passed in the environment, so none are in source:

```bash
TEST_RUNNER_WALLET_E2E_EMAIL=demo@wallet.test TEST_RUNNER_WALLET_E2E_PASSWORD=sandbox-demo \
  xcodebuild test -project Wallet.xcodeproj -scheme Wallet \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:WalletUITests/EndToEndUITests
```

GitHub Actions (`.github/workflows/pr.yml`) runs lint, every test suite and the module boundary check on each pull request.
