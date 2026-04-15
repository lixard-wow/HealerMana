# Claude Project Instructions

You are working on a World of Warcraft addon.

## Environment
- Game: World of Warcraft
- Interface version: 120001
- Expansion/client target: Midnight-era client unless the user explicitly says otherwise
- Language: Lua
- Addon type: WoW addon only

## Hard Rules
- Do not guess WoW API behavior
- If an API is uncertain, verify against trusted WoW API documentation before using it
- Do not perform math on secret/protected values
- Do not try to bypass hidden, protected, secure, or restricted game data
- Respect combat lockdown and protected frame restrictions at all times
- Use event-driven patterns over OnUpdate whenever possible
- Avoid unnecessary polling
- No external libraries unless explicitly approved
- Do not use Blizzard UI templates/assets unless explicitly approved
- Prefer custom frames and custom UI behavior
- Keep solutions lean and minimal
- Do not add extra features that were not requested
- Do not silently refactor unrelated systems
- Do not change TOC/interface version unless explicitly asked

## Code Style
- Use local scoping whenever possible
- Avoid duplicate helpers
- Reuse existing helpers before creating new ones
- Create a new helper only when it is clearly reusable
- Keep functions focused and responsibility-based
- Avoid bloated abstractions
- No comments in final code unless explicitly requested
- Preserve existing naming conventions unless asked to rename
- Prefer simple Lua over clever Lua

## Architecture
- Keep logic and UI separated
- Keep modules responsibility-focused
- Avoid mixed concerns in a single file
- Prefer data-only extraction first before larger refactors
- Refactor early if a file is growing too large
- Do not create unnecessary new files
- If creating a new file, it must have a clear reason

## SavedVariables
- Use one canonical SavedVariables table only unless explicitly told otherwise
- Do not create extra SavedVariables tables casually
- Keep defaults predictable and centralized

## Performance
- Avoid repeated allocations in hot paths
- Cache values reused multiple times
- Avoid unnecessary table creation in loops
- Avoid function calls in tight loops if a value can be stored once
- Prefer throttled/event-based updates over frequent refreshes
- Disable computation when a feature/toggle is off

## Localization
- All user-facing text should use localization keys
- Maintain enUS as source of truth
- Do not concatenate localized fragments if it can be avoided
- Missing localization entries should be easy to spot during development

## UI Rules
- Build responsive UI that does not clip at different scales
- Avoid fragile hard-coded sizes when variable text is involved
- Use anchors, padding, and measured widths where appropriate
- Avoid layouts that break at different resolutions or UI scale settings

## Workflow Rules
- Read this file before making changes
- Also read docs/DEV_RULES.md before making changes
- Follow docs/TODO.md as the work driver when present
- Update docs/CHANGELOG_DEV.md, docs/ISSUES.md, and docs/TODO.md whenever a task is completed, if the project is using that workflow
- If requirements are unclear, stop and ask instead of guessing
- When asked for a prompt, provide a copyable prompt block
- When asked to make code changes, keep scope narrow unless told to broaden it

## Output Rules
- Be direct
- Keep output minimal
- Provide only what is needed
- When finishing a requested prompt/task, print a completion marker in chat such as:
  PROMPT X COMPLETE
