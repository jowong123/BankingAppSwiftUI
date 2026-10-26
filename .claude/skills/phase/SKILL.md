---
name: phase
description: Run one build phase (1-10) from the plan in docs/SPEC.md section 10 and verify its "done when" checks. Use when the user says /phase <n>, "start phase 3", or "next phase".
argument-hint: <phase number>
---

# Run a build phase

The phase number is: $ARGUMENTS

1. Read `docs/SPEC.md` section 10 and find **Phase $ARGUMENTS**. Read every other spec section that phase depends on (e.g. Phase 6 → sections 4, 5, 7; Phase 7 → section 6).
2. Check the previous phase is done: its modules exist and `swift test` passes. If not, stop and tell the user what is missing.
3. Post a short plan before writing code:
   - the files you will create or change, grouped by module
   - any decision the spec doesn't cover (ask, or propose an ADR with `/adr`)
   - which "done when" checks you can verify yourself and which need the user (device, Face ID, real passport, TestFlight)
4. Implement in small steps, one module at a time. After each module: build, test, lint.
5. Before finishing, invoke the `architecture-reviewer` agent. Phases 5, 6, 7 and 8 also invoke the `security-reviewer` agent. Fix what they find.
6. Finish with a report:
   - **Done when** checklist with ✅ verified / ⏳ needs the user (and the exact steps for them)
   - commands you ran and their results
   - ADRs added or needed
   - 3–5 things the owner should be able to explain in an interview about this phase
   - suggested commit message(s), prefixed with the phase: `phase $ARGUMENTS: feat(scope): ...`

Never mark a check as verified unless you ran something that proves it.
