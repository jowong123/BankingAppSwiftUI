---
name: adr
description: Write or update an Architecture Decision Record in docs/adr/ using the project template. Use when the user says /adr, asks to record a decision, or when a task needs a decision the spec doesn't cover.
argument-hint: <number> <short title>
---

# Write an ADR

Arguments: $ARGUMENTS (number, then title). If no number is given, use the next free number in `docs/adr/`.

1. Read `docs/adr/000-template.md` and the ADR table in `docs/SPEC.md` section 9. If this ADR is listed there, follow its decision and rejected alternative.
2. Read the spec sections and code the decision affects, so the context is concrete (name real types and modules).
3. Write `docs/adr/NNN-kebab-title.md` from the template:
   - **Context**: the problem and constraints, specific to this app (fintech, iOS 17, Swift 6, DBS/Wise/Thales audience).
   - **Decision**: one clear sentence, then the details.
   - **Alternatives considered**: at least two, each with why it lost. This is the part interviewers read most.
   - **Consequences**: what gets easier, what gets harder, what we'd revisit at team scale.
4. Keep it under 400 words. Plain language, no marketing tone.
5. If the decision changes the spec, update `docs/SPEC.md` (and `CLAUDE.md` if a rule changes) in the same change, and say so.
6. Set Status to `Proposed` unless the user said it's accepted.
