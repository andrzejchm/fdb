# Beads Issue Tracker

This repo uses `bd` (Beads) for issue tracking.

Issues live in `.beads/embeddeddolt/` (gitignored, local Dolt DB) and are auto-exported to `.beads/issues.jsonl` (git-tracked) after every write.

## Quick start

```bash
bd prime                                                          # Load session context
bd ready                                                          # List available issues
bd show <id>                                                      # View issue details
bd update <id> --claim                                            # Claim an issue
bd create --title="..." --description="..." --type=task --priority=2  # Create an issue
bd close <id>                                                     # Close an issue
bd github sync                                                    # Bidirectional sync with GitHub Issues
bd bootstrap                                                      # Rebuild local DB after git pull
```

## Collaboration flow

1. Write/update issues with `bd`
2. Commit `issues.jsonl` alongside code changes
3. Teammates run `git pull` + `bd bootstrap`

See `AGENTS.md` for full agent instructions.
