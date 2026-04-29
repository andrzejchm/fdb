/// Marker base type for all command result sealed hierarchies.
///
/// Each command in `lib/core/commands/<name>.dart` declares its own sealed
/// result hierarchy as a subtype of [CommandResult]. CLI / MCP / REST
/// adapters pattern-match exhaustively over each command's specific result
/// type to produce their interface-specific output (e.g., the CLI adapter
/// translates results into UPPER_SNAKE_CASE stdout tokens).
///
/// This base type carries no fields; it exists purely to document the
/// convention and enable shared helpers (e.g., a generic adapter wrapper
/// that knows nothing about specific command results but logs them).
abstract class CommandResult {
  const CommandResult();
}
