# agentsync

**One Source of Truth for your AI Skills & Agents.**

Stop copying files between **Cursor**, **Claude Code**, **OpenCode**, **Windsurf**, **Codex**, and **Aider**. Define your AI configuration once and sync it everywhere.

## The Problem

Your AI personas are fragmented. You fix a prompt in Cursor (`.cursor/rules/`), but Claude (`.claude/agents/`) doesn't know about it. You switch to OpenCode (`.opencode/agent/`) and have to copy-paste everything again.

## The Solution

**agentsync** lets you pick **ONE** folder as your "Source of Truth" (e.g. `~/.claude` or `.shared`) and syncs it to every other tool automatically.

It handles all the annoying format differences for you:
- **Folders vs Files:** Claude wants folders (`agents/foo/AGENT.md`), OpenCode wants files (`agent/foo.md`). **We convert them.**
- **Skills:** Drop a flat markdown file (`skills/git.md`), and we expand it into the complex folder structure required by tools.

## Quick Start

### 1. Initialize
Run `init` to auto-detect your existing AI folders:

```bash
agentsync init
```

It will scan your system and ask:
> "We found `~/.claude` and `~/.cursor`. Which one is your Source of Truth?"

Pick one, and `agentsync` will mirror it to all other installed tools.

### 2. Add Skills
Install community skills directly from GitHub:

```bash
# Add a skill (auto-detects type)
agentsync add user/repo/skills/git-tool
```

### 3. Sync
Keep everything in sync:

```bash
# Run once
agentsync sync

# Watch for changes (Daemon)
agentsync watch -d
```

## Features

- **Any Source:** Use `.shared`, `.claude`, `.cursor`, or any folder as your master copy.
- **Smart Translation:** Automatically flattens/expands files to match what each tool expects.
- **Hybrid Scope:** Overlay global skills (`~/.shared`) onto project skills (`.shared`) seamlessly.
- **Wipe:** Clean up generated files with `agentsync wipe`.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/rdvo/agentsync/main/install.sh | bash
```

## How It Works (The Matrix)

You can be lazy with your source format. We clean it up.

| Source File | Syncs to Cursor | Syncs to Claude | Syncs to OpenCode |
| :--- | :--- | :--- | :--- |
| `agents/senior.md` | `rules/senior/RULE.md` | `agents/senior.md` | `agent/senior.md` |
| `skills/git.md` | *(Via Agent Skills)* | `skills/git/SKILL.md` | `skill/git/SKILL.md` |

## License

MIT
