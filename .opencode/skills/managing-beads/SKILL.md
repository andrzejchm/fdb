---
name: managing-beads
description: >
  Project issue tracker using bd (Beads). Issues travel via git through
  .beads/issues.jsonl. Use when asked to work on, pick, or fix an issue;
  when capturing discovered work; or when checking what to do next.
---

# Managing Beads Issues

## Session workflow

1. Run `bd prime` — loads context and shows open/claimed issues.
2. Pick work with `bd ready`, claim with `bd update <id> --claim`.
3. Work on code. Create follow-up issues as you discover them.
4. Commit `issues.jsonl` together with the code it tracks (the pre-commit hook exports it automatically).
5. Before context compaction: run `bd sync` to flush any pending writes.
6. Close finished issues with `bd close <id>`.

## Core commands

```bash
bd prime                                                          # Session start: load context
bd ready                                                          # List unclaimed available issues
bd show <id>                                                      # View issue details
bd update <id> --claim                                            # Claim an issue
bd update <id> --status=in-progress                               # Update status
bd create --title="..." --description="..." --type=task --priority=2  # Create an issue
bd close <id>                                                     # Mark issue done
bd sync                                                           # Flush pending writes (before compaction)
bd bootstrap                                                      # Rebuild local DB after git pull
bd github sync                                                    # Bidirectional sync with GitHub Issues
bd github sync --pull-only                                        # Pull from GitHub only
bd github sync --push-only                                        # Push to GitHub only
```

## Creating issues

```bash
bd create \
  --title="Add scroll support for web" \
  --description="CDP-based scroll not yet implemented; fdb scroll fails on web targets." \
  --type=task \
  --priority=2
```

Types: `task`, `bug`, `feature`, `chore`  
Priorities: `1` (critical) → `4` (low)

## Rules

- Always commit `issues.jsonl` together with the code changes it tracks — never in isolation.
- Run `bd bootstrap` after `git pull` on any machine that already has a local DB.
- Run `bd prime` at session start only — not during compaction (`bd sync` handles compaction).
- Never run `bd doctor --fix` — it can corrupt the local DB.
- `bd` is the source of truth; GitHub Issues are a mirror — sync with `bd github sync`.
- Capture any work discovered during implementation as new issues immediately.

## Working in a git worktree

The pre-commit hook always exports to the **main repo's** `.beads/issues.jsonl`, not the worktree's copy. The "Exported N issues" message does not mean it was staged in the worktree.

Before committing from a worktree, manually copy and stage:

```bash
cp <repo-root>/.beads/issues.jsonl .beads/issues.jsonl
git add .beads/issues.jsonl
git commit -m "chore(bd): sync issues — <summary>"
```

Never push a worktree branch with a stale `issues.jsonl`.
