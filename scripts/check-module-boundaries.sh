#!/usr/bin/env bash
# Proves the module rules in docs/SPEC.md section 3 are enforced by the build:
# every forbidden import below must fail to compile.
#
# Works on a throwaway copy of WalletKit, so the repo is never modified.
# Uses --explicit-target-dependency-import-check error because, with a warm
# .build cache, SwiftPM otherwise lets a target import an undeclared sibling.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -R "$root/WalletKit/Package.swift" "$root/WalletKit/Sources" "$root/WalletKit/Tests" "$work/"
cd "$work"

build() { swift build --explicit-target-dependency-import-check error >/dev/null 2>&1; }

echo "Baseline build..."
build || { echo "Baseline build failed; fix it before checking boundaries." >&2; exit 1; }

features=(AuthFeature OnboardingFeature AccountsFeature TransferFeature)
pairs=()
for from in "${features[@]}"; do
    for to in "${features[@]}"; do
        [[ "$from" != "$to" ]] && pairs+=("$from:$to")
    done
done
# Features reach infrastructure only through Domain protocols (ADR-004).
for from in "${features[@]}"; do
    for to in Networking Persistence WalletSecurity; do
        pairs+=("$from:$to")
    done
done
# Core and SDK rules.
pairs+=(
    "Domain:Observability"
    "Domain:DesignSystem"
    "DesignSystem:Networking"
    "DesignSystem:WalletSecurity"
    "Networking:DesignSystem"
    "WalletSecurity:AuthFeature"
    "Persistence:Networking"
    "Observability:Domain"
    "IdentitySDK:Domain"
    "IdentitySDK:WalletSecurity"
)

failures=0

# Positive control: an allowed import must still compile, otherwise every
# "ok" below could be a build failing for some unrelated reason.
printf 'import Domain\n' >Sources/OnboardingFeature/BoundaryProbe.swift
printf 'import IdentitySDK\n' >>Sources/OnboardingFeature/BoundaryProbe.swift
if build; then
    echo "ok    OnboardingFeature can import Domain and IdentitySDK (control)"
else
    echo "FAIL  control import did not compile" >&2
    exit 1
fi
rm Sources/OnboardingFeature/BoundaryProbe.swift

for pair in "${pairs[@]}"; do
    from="${pair%%:*}"
    to="${pair##*:}"
    probe="Sources/$from/BoundaryProbe.swift"
    printf 'import %s\n' "$to" >"$probe"
    if build; then
        echo "FAIL  $from can import $to"
        failures=$((failures + 1))
    else
        echo "ok    $from cannot import $to"
    fi
    rm "$probe"
done

if ((failures > 0)); then
    echo "$failures forbidden import(s) compiled." >&2
    exit 1
fi
echo "All ${#pairs[@]} forbidden imports are rejected."
