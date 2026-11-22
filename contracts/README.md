# Contracts

Facts the app and the backend must agree on, checked by tests on both sides. They are
separate Swift packages with no shared code, so this folder is the shared source of truth.

- `currencies.json`: supported ISO 4217 codes and their minor units.
  - `WalletKit/Tests/DomainTests/CurrencyContractTests.swift` checks `Currency.supported`.
  - `backend/Tests/WalletBackendTests/CurrencyContractTests.swift` checks `Currencies.minorUnits`
    and the `Money.currency` enum in `backend/openapi.yaml`.

To add a currency, change this file first; both test suites then fail until each side matches.
