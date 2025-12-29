# agentsync

**One Source of Truth for your AI Skills & Agents.**

Stop copying files between **Cursor**, **Claude Code**, **OpenCode**, **Windsurf**, **Codex**, and **Aider**. Define your AI configuration once and sync it everywhere.

## The Problem

You use multiple AI tools, but they all speak different languages:
- **Agents (Personas):** Claude wants `.claude/agents/*.md`, Cursor wants `.cursor/rules/`, OpenCode wants `.opencode/agent/`.
- **Skills (Tools):** Claude wants `.claude/skills/`, Codex wants `.codex/skills/`, OpenCode wants `.opencode/skill/`.

If you write a great "Senior React Developer" agent, you have to copy-paste it 5 times. If you write a custom "Git Release" skill, you have to duplicate it everywhere.

**Agentsync solves this.** It acts as a **Universal Adapter**, translating your single source of truth into the exact format each tool expects.

## Features

- **Unified Config:** Manage **Agents** (prompts/personas) and **Skills** (executable scripts) in one place: `.shared/`.
- **Universal Translation:** Automatically converts your files to the format each tool expects (folders for Cursor, flat files for Claude, singular for OpenCode).
- **Hybrid Scope:** Overlay your personal **Global** tools on top of **Project** tools without polluting the git repo.
- **Live Sync:** The daemon watches for changes and updates every tool instantly.

## How to Use

### 1. Project Mode (For Teams)
You want to enforce rules like "Use React Hooks" for everyone working on this repo.

1. Run `agentsync init` inside your project folder.
2. Select **Project** when asked.
3. Add your agents to `.shared/agents/` (e.g., `react-rules.md`).
4. Commit `.shared` to Git.
5. **Result:** Anyone who clones the repo gets these rules automatically.

### 2. Global Mode (For You)
You have personal preferences (e.g., "Senior Dev Persona", "Be concise") that you want everywhere.

1. Run `agentsync init` anywhere.
2. Select **My Machine (Global)**.
3. Add your personal agents to `~/.shared/agents/`.
4. **Result:** These agents follow you to every project on your machine, but stay private.

### 3. Hybrid Mode (The Best of Both)
You want the team's rules **PLUS** your personal power tools.

1. In a team project, run `agentsync init`.
2. Say **YES** to "Include global skills?".
3. **Result:** You get the project's shared agents **AND** your personal global agents overlayed on top. Your team never sees your personal files.

## Installation

Install **agentsync** globally with a single command:

```bash
curl -sSL https://raw.githubusercontent.com/rdvo/agentsync/main/install.sh | bash
```

This will clone the repository to `~/.agentsync` and symlink the binary to `/usr/local/bin/agentsync`.

## Usage

### 1. Initialize

Run `init` to set up your environment. Agentsync will ask: **"Who is this for?"**

```bash
agentsync init
```

- **Project based:** Creates `.shared/` in your current folder. **Commit this to Git.** Everyone working on this project gets these skills.
- **My Machine (Global):** Creates `~/.shared/` in your home folder. **Do not commit.** These are your personal tools.

### 2. Managing Global Skills

If you have prompts or personas you want to use across **every** project:
1. Run `agentsync init` and choose **"My Machine (Global)"**.
2. Add your persona files to `~/.shared/agents/` (e.g., `senior-dev.md`).
3. Now, in any project where you run `agentsync init`, say **"Yes"** to inheritance.
4. Your global tools will magically appear in that project's Cursor/Claude/etc.

### 3. Add Skills

You can install skills directly from GitHub:

```bash
# Install a specific agent
agentsync add user/repo/agents/architect.md

# Install a whole collection
agentsync add user/repo
```

Or create them manually in your source directory.

### 4. Check & Repair

Validate your configuration and repair broken symlinks:

```bash
# Check configuration and tool availability
agentsync check

# Repair broken symlinks
agentsync repair
```

### 5. Sync

If you enabled the daemon during init, changes sync automatically. Otherwise:

```bash
# Manual sync
agentsync

# Watch mode (Daemon)
agentsync watch -d
```

## How It Works (The Translation Layer)

`agentsync` intelligently maps your Source files to Target tools:

| Source File | Syncs to Cursor | Syncs to Claude | Syncs to OpenCode | Syncs to Codex | Syncs to Aider |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `agents/architect.md` | `.cursor/rules/architect/RULE.md` <br>*(Auto-creates folder structure)* | `.claude/agents/architect.md` | `.opencode/agent/architect.md` | *(Ignored)* | *(Ignored)* |
| `skills/git-tool/` | *(Via Agent Skills)* | `.claude/skills/git-tool/` | `.opencode/skill/git-tool/` | `.codex/skills/git-tool/` | *(Ignored)* |
| `commands/deploy.sh` | *(Ignored)* | `.claude/commands/deploy.sh` | `.opencode/command/deploy.sh` | *(Ignored)* | *(Ignored)* |
| `AGENTS.md` | `./AGENTS.md` | `./AGENTS.md` | `./AGENTS.md` | `./AGENTS.md` | `.aider/CONVENTIONS.md` |

## Directory Structure

We recommend using `.shared` as your Source of Truth, but you can use any folder.

```
MyProject/
├── .shared/                  # Source of Truth (Git-tracked)
│   ├── agents/                # Agents (Markdown) -> Synced to all tools
│   ├── skills/                # Executable Skills (Folders with SKILL.md)
│   └── AGENTS.md             # Project Instructions -> Synced to Root
├── .cursor/
│   └── rules/                # Auto-generated by agentsync
├── .claude/
│   ├── agents/               # Auto-generated by agentsync
│   └── skills/               # Auto-generated by agentsync
└── .codex/
    └── skills/               # Auto-generated by agentsync
```

## License

MIT
