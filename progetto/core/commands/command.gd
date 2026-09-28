class_name Command
extends RefCounted
## Every intentional change to the game state (player or AI) is a Command.
## validate() returns "" when the command can run, otherwise a human-readable reason
## (shown in the UI exactly like Regno's "perche()" helpers).

## Kingdom issuing the command (-1 = system).
var issuer: int = -1


func get_type() -> StringName:
	return &"command"


func validate(_session: GameSession) -> String:
	return ""


func execute(_session: GameSession) -> CommandResult:
	return CommandResult.ok()


func describe() -> String:
	return String(get_type())

