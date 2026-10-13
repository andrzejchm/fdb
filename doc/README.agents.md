# fdb for AI Agents

fdb is a CLI that lets AI agents launch, reload, screenshot, inspect, and interact with Flutter apps running on physical devices and simulators.

## Step 1: Install the CLI

```bash
dart pub global activate fdb
```

Requires Dart SDK >= 3.0.0. Ensure `~/.pub-cache/bin` is in your `PATH`.

## Step 2: Install the skill file

Install the skill once so your agent automatically knows how to use fdb:

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

For other agents, place the SKILL.md wherever your agent reads skill definitions from, or run `fdb skill` to print its contents directly.

## Step 3: Verify

```bash
fdb status
```

Restart your agent after installing the skill file, then load the `using-fdb` skill for full usage instructions.

For OS panels outside Flutter, use `fdb native-swipe --from x,y --to x,y --duration <ms>`.
All flags are required, with duration 1-60000 integer milliseconds. Coordinates are
iOS simulator points or Android physical pixels in the current orientation. It
targets the recorded session device without contacting the VM or `fdb_helper`.
Physical iOS and desktop targets are unsupported. Run `fdb skill interact` for
examples and the `NATIVE_SWIPED` output contract.
