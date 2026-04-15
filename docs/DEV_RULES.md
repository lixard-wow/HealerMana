# DEV_RULES.md

## Project Baseline
- WoW addon project
- Interface version: 120001
- Lua only
- No external libraries unless explicitly approved
- Prefer custom UI over Blizzard templates/assets

## Non-Negotiables
- No guessing on WoW APIs
- Verify uncertain API behavior before implementation
- Never do math on secret/protected values
- Never attempt to expose, infer, or bypass restricted values
- Respect combat lockdown and secure frame limitations
- Do not add hidden scope or unrelated cleanup

## Scope Control
- Do only what was requested
- Keep changes minimal and targeted
- Do not rewrite surrounding systems unless required for the task
- If a broader refactor would help, propose it instead of silently doing it

## Structure
- Keep files responsibility-focused
- Avoid duplicate helpers or duplicate implementations
- Reuse existing module boundaries where possible
- Prefer data-only extraction first
- Split growing files before they become unmanageable
- Do not create unnecessary conceptual layers

## Performance
- Event-driven first
- Avoid unnecessary OnUpdate usage
- Cache reused values
- Avoid repeated allocations in hot paths
- Gate disabled features so they stop doing work
- Use dirty/queued refreshes when appropriate instead of constant rebuilding

## SavedVariables
- Use one canonical SavedVariables table
- Keep defaults centralized
- Do not scatter persistence logic across unrelated files

## Localization
- All player-facing strings should be localized
- enUS is source of truth
- Avoid string concatenation for localized UI text
- Missing locale strings should be obvious during development

## UI / Layout
- Support different UI scales and resolutions
- Avoid clipping and zero-width layout states
- Avoid fragile offsets
- Prefer measured or bounded sizing for dynamic content
- Test layouts in narrow and wider frame states

## File and Docs Workflow
Project docs live in docs/.

Maintain these files when the workflow is active:
- docs/TODO.md
- docs/ISSUES.md
- docs/CHANGELOG_DEV.md
- docs/TESTING.md

Definition of done includes:
- requested code change completed
- relevant docs updated
- obvious regressions checked
- completion marker printed in chat

## Required Pre-Flight Check
Before making changes, confirm:
- scope is clear
- solution is minimal
- no duplicate helper is being introduced
- localization rules are being followed
- event-driven approach is preferred
- debug/dev-only code stays isolated when applicable

## Completion Marker
When finishing a prompt or task, print:
PROMPT X COMPLETE
