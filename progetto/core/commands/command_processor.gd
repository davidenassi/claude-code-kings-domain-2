class_name CommandProcessor
extends RefCounted
## Validates and executes commands, keeping a short history for debugging and for the AI motivation log.

signal executed(command: Command, result: CommandResult)

const HISTORY_SIZE := 200

var history: Array[Dictionary] = []


func submit(session: GameSession, command: Command) -> CommandResult:
	var reason := command.validate(session)
	var result: CommandResult
	if reason != "":
		result = CommandResult.fail(reason)
	else:
		result = command.execute(session)
	history.append({
		"day": session.world.day if session.world else 0,
		"type": String(command.get_type()),
		"issuer": command.issuer,
		"ok": result.success,
		"reason": result.reason,
	})
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	executed.emit(command, result)
	return result

