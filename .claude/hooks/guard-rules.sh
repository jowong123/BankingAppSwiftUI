#!/usr/bin/env bash
# PreToolUse hook: block edits that break the project's hard rules (see CLAUDE.md).
# Exit 2 = block the edit and show the reason to Claude so it can fix the code.
set -euo pipefail

input="$(cat)"

python3 - "$input" <<'PY'
import json, re, sys

data = json.loads(sys.argv[1])
ti = data.get("tool_input", {})
path = ti.get("file_path", "")

if not path.endswith(".swift"):
    sys.exit(0)

# Collect the new text being written (Write: content, Edit: new_string, MultiEdit: edits[]).
parts = [ti.get("content", ""), ti.get("new_string", "")]
parts += [e.get("new_string", "") for e in ti.get("edits", [])]
text = "\n".join(p for p in parts if p)

is_test = "/Tests/" in path or path.endswith("Tests.swift") or "UITests" in path
problems = []

# Money must never be Double/Float.
if re.search(r"\b(amount|balance|fee|price|total)\w*\s*:\s*(Double|Float|CGFloat)\b", text, re.I):
    problems.append("Money-like value typed as Double/Float. Use Money (Decimal) from Domain.")

# Secrets never in UserDefaults.
if re.search(r"UserDefaults[^\n]*(token|secret|password|pin|key)", text, re.I):
    problems.append("Sensitive value stored in UserDefaults. Use WalletSecurity/KeychainStore.")

# print is banned everywhere, tests included (use Logger, or #expect messages in tests).
if re.search(r"(^|[^\w.])print\(", text):
    problems.append("print() is banned. Use Logger from Observability with privacy: .private.")

# No try! outside tests.
if not is_test and "try!" in text:
    problems.append("try! is not allowed outside tests.")

# Features never import other features.
m = re.search(r"/Sources/(\w+Feature)/", path)
if m:
    own = m.group(1)
    for imp in re.findall(r"^\s*import\s+(\w+Feature)\b", text, re.M):
        if imp != own:
            problems.append(f"{own} imports {imp}. Features never import features; use an output closure.")

# IdentitySDK must not import WalletKit modules.
if "/Sources/IdentitySDK/" in path:
    banned = {"Domain","DesignSystem","Navigation","Networking","WalletSecurity","Persistence","Observability"}
    for imp in re.findall(r"^\s*import\s+(\w+)", text, re.M):
        if imp in banned:
            problems.append(f"IdentitySDK imports {imp}. The SDK must build alone.")

# Domain stays framework-free.
if "/Sources/Domain/" in path and re.search(r"^\s*import\s+(SwiftUI|UIKit|SwiftData)\b", text, re.M):
    problems.append("Domain must import Foundation only.")

if problems:
    print("Blocked by project rules (CLAUDE.md):\n- " + "\n- ".join(problems), file=sys.stderr)
    sys.exit(2)
PY
