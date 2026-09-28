class_name SimSystem
extends RefCounted
## Base class for every simulation system. Systems hold no scene nodes and operate on the
## GameSession passed to run(). Frequency and rotation are declared here and honoured by the Scheduler.

enum Frequency { TICK, DAY, DAY_ROTATING, MONTH, YEAR }

var id: StringName = &"system"
var frequency: int = Frequency.DAY
## Number of buckets for DAY_ROTATING systems (e.g. 7 = every entity once a week).
var spread: int = 1
## Lower values run first inside the same frequency pass.
var order: int = 100
var enabled: bool = true

## Accumulated microseconds spent in run(), for profiling.
var profile_usec: int = 0
var profile_runs: int = 0


func run(_session: GameSession, _step: SimStep) -> void:
	pass


## Helper for rotating systems: true if the entity with this id belongs to the current bucket.
static func in_bucket(entity_id: int, step: SimStep) -> bool:
	if step.spread <= 1:
		return true
	return entity_id % step.spread == step.bucket

