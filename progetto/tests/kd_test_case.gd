class_name KDTestCase
extends RefCounted
## Minimal test base class. Test methods start with "test_". Failures are collected, not thrown.

var failures: PackedStringArray = PackedStringArray()
var current_test: String = ""
var assertions: int = 0
## Tests that could not run here and said why (a fixture missing from the package): listed, never silent.
var skipped: PackedStringArray = PackedStringArray()


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


## The test cannot run in this copy of the project: it is reported as SKIP with the reason.
func skip(reason: String) -> void:
	skipped.append("%s: %s" % [current_test, reason])


func assert_true(condition: bool, message: String = "expected true") -> bool:
	assertions += 1
	if not condition:
		fail(message)
	return condition


func assert_false(condition: bool, message: String = "expected false") -> bool:
	return assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	assertions += 1
	if typeof(actual) != typeof(expected) and not ((actual is int or actual is float) and (expected is int or expected is float)):
		fail("%s expected %s (%s) got %s (%s)" % [message, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
		return false
	if actual != expected:
		fail("%s expected %s got %s" % [message, str(expected), str(actual)])
		return false
	return true


func assert_near(actual: float, expected: float, epsilon: float = 0.0001, message: String = "") -> bool:
	assertions += 1
	if absf(actual - expected) > epsilon:
		fail("%s expected %f ± %f got %f" % [message, expected, epsilon, actual])
		return false
	return true




func assert_null(value: Variant, message: String = "expected null") -> bool:
	return assert_true(value == null, message)
func assert_not_null(value: Variant, message: String = "expected non-null") -> bool:
	return assert_true(value != null, message)


## Phase 15: a new game starts as a community without a crown. Tests that study the court, the laws or the
## edicts crown it at once — the eldest founder of age, with his family as the royal house — skipping the
## conditions the player has to earn.
static func crown_player(session: GameSession) -> KingdomState:
	var world := session.world
	var k := world.player()
	if k == null or k.monarchy_founded:
		return k
	var chosen: PersonState = null
	for s in world.settlements:
		if s.kingdom != k.id:
			continue
		for p in world.people_of(s.id):
			if p.family < 0 or p.female or p.age_years(world.day) < 18:
				continue
			if chosen == null or p.birth_day < chosen.birth_day:
				chosen = p
	if chosen:
		CourtSystem.found_monarchy(session, k, world.family(chosen.family), chosen)
	return k

