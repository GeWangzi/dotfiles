# Global instructions for Claude Code

These apply to every project on this machine. Project-specific rules live in
each repo's own `CLAUDE.md` (start one from `~/.claude/templates/CLAUDE.md`).

<!-- Paste global instructions below this line. -->
## Environment
- Arch Linux, Hyprland, zsh, Kitty. Package manager is pacman; AUR via paru.

## How to work
- Before saying a task is done, run the relevant tests or the project's
  build command. If there isn't one, say so explicitly.
- Prefer small diffs. Don't refactor unrelated code while fixing something.
- Ask before adding a dependency, changing a build config, or touching
  anything under `.github/` or CI.
- Don't create new files when editing an existing one would do.