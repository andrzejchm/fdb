# fdb for AI Agents

fdb is a CLI that lets AI agents launch, reload, screenshot, inspect, and interact with Flutter apps running on physical devices and simulators.

## Step 1: Install the CLI

```bash
dart pub global activate fdb
```

Requires Dart SDK >= 3.0.0. Ensure `~/.pub-cache/bin` is in your `PATH`.

## Step 2: Install the skill file

Install the skill so your agent automatically knows how to use fdb.

The skill file is a lean shim — it never needs to be reinstalled after fdb updates. When loaded,
it instructs the agent to run `fdb skill`, which prints the full, version-matched reference
straight from the installed CLI.

**OpenCode:**
```bash
mkdir -p ~/.config/opencode/skills/using-fdb
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.config/opencode/skills/using-fdb/SKILL.md
```

**Claude Code:**
```bash
mkdir -p ~/.claude/skills/using-fdb
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.claude/skills/using-fdb/SKILL.md
```

**Cursor:**
```bash
mkdir -p ~/.cursor/skills/using-fdb
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.cursor/skills/using-fdb/SKILL.md
```

**Windsurf:**
```bash
mkdir -p ~/.codeium/windsurf/skills/using-fdb
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.codeium/windsurf/skills/using-fdb/SKILL.md
```

**Gemini CLI:**
```bash
gemini skills install https://github.com/andrzejchm/fdb.git --path skills/using-fdb
```

For other agents, place the SKILL.md wherever your agent reads skill definitions from.

## Step 3: Verify

```bash
fdb status
```

Restart your agent after installing the skill file, then load the `using-fdb` skill for full usage instructions.
