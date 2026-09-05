# <project name>

<!--
Project instructions for Claude Code. Copy this file to the repo root as
CLAUDE.md, fill in the sections that apply, delete the ones that do not.
Keep it short: Claude reads this on every turn, so every line should change
how it works.
-->

## What this is

One or two sentences: what the project does and who uses it.

## Commands

```sh
# build
# test
# lint / format
# run locally
```

Prefer the commands above over guessing. If a command is slow or needs
services running, say so here.

## Layout

- `src/` — ...
- `tests/` — ...

Name the directories that matter and what lives in each. Skip the obvious.

## Conventions

- Language / framework version:
- Formatting and lint rules are enforced by: (tool). Do not hand-format.
- Commit message style:
- Branching: work on feature branches; never commit to `master` directly.

## Do not touch

- Files or directories that are generated, vendored, or owned by someone else.
- Secrets: `.env*`, credential files. Never read or print them.

## Testing

How to add a test, where fixtures live, and what counts as done
(for example: "a change is complete only when `make test` passes").

## Gotchas

Anything non-obvious that has bitten people before.
