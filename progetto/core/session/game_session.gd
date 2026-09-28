class_name GameSession
extends RefCounted
## One running campaign: world state + the machinery that advances it.
## Contains no scene nodes, so it can be driven headless by tests.

var world: WorldState
var calendar: GameCalendar
var clock: SimClock
var scheduler: Scheduler
var commands: CommandProcessor
## Transient per-session data that is rebuilt after loading (caches, dirty flags). Never saved.
var runtime: Dictionary = {}
var _step := SimStep.new()


## Builds a brand new campaign. The map is fixed; only the campaign seed (never shown) varies.
static func create_new(options: Dictionary = {}) -> GameSession:
	var s := GameSession.new()
	var time_cfg: Dictionary = Defs.balance("time")
	s.world = WorldState.new()
	s.world.ticks_per_day = int(time_cfg.get("ticks_per_day", 24))
	# the founders arrive in the morning (Rebirth, Phase 3): the first thing seen is six people round their fire
	s.world.tick = clampi(int(time_cfg.get("start_hour", 0)), 0, s.world.ticks_per_day - 1)
	var seed_value: int = int(options.get("campaign_seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	s.world.rng = KDRng.new(seed_value)
	if options.has("homeland"):
		s.world.flags["homeland"] = String(options["homeland"])   # "none": a valley cut out of the continent
	if WorldData.is_available():
		StartSetup.apply(s.world)
		SettlementSetup.found_player_settlement(s.world)
	s._setup_runtime(time_cfg)
	s._seed_spirits()
	CourtSystem.found_courts(s)
	Diplomacy.found_relations(s.world)
	return s


static func from_world(world_state: WorldState) -> GameSession:
	var s := GameSession.new()
	s.world = world_state
	if s.world.provinces.is_empty() and WorldData.is_available():
		StartSetup.apply(s.world)  # saves from before Phase 3 had no political map
	if s.world.settlements.is_empty() and not s.world.provinces.is_empty() and WorldData.is_available():
		SettlementSetup.found_player_settlement(s.world)  # saves from before Phase 4 had no settlement
	var time_cfg: Dictionary = Defs.balance("time")
	s._setup_runtime(time_cfg)
	CourtSystem.found_courts(s)  # saves from before Phase 7 had no court
	Diplomacy.found_relations(s.world)
	return s


func _setup_runtime(time_cfg: Dictionary) -> void:
	calendar = GameCalendar.from_config(time_cfg)
	clock = SimClock.from_config(time_cfg)
	clock.ticks_per_day = world.ticks_per_day
	scheduler = Scheduler.new()
	commands = CommandProcessor.new()
	SystemRegistry.register_all(self)
	EventBus.chronicle_written.connect(_write_chronicle)


## Called when this session stops being the current one: everything it hung on the global bus comes off.
func dispose() -> void:
	if EventBus.chronicle_written.is_connected(_write_chronicle):
		EventBus.chronicle_written.disconnect(_write_chronicle)


## What the other crowns do that changes the world, and so belongs to its history (see _write_chronicle).
const WORLD_KINDS: Array[String] = ["war", "peace", "conquest", "revolt", "revolt_over", "ruler_died", "succession",
	"succession_crisis", "reign_begins"]


## Every deed worth remembering ends up here, and from here in the save and in the Cronaca panel. The chronicle
## keeps the history, not the traffic (consolidation): everything of the player's realm and of whoever deals with
## it — the enemy that lays siege to its lands is in, with its name — but of the other crowns only what changes the
## world: wars and peaces, conquests, revolts, the deaths and successions of kings, the foundations. Two saves of
## forty years had 600 lines of which 47 were the player's: the marches, pacts, sieges and occupations of the
## others had pushed his history out of it.
func _write_chronicle(entry: Dictionary) -> void:
	var kingdom := int(entry.get("kingdom", -1))
	var other := int(entry.get("other", -1))
	var kind := String(entry.get("kind", ""))
	if kingdom >= 0 and kingdom != world.player_kingdom and other != world.player_kingdom \
			and not kind.begins_with("founding") and not WORLD_KINDS.has(kind):
		return
	var line := {"day": int(entry.get("day", world.day)), "kingdom": kingdom, "kind": kind,
		"text": String(entry.get("text", ""))}
	if other >= 0:
		line["other"] = other
	world.chronicle.append(line)
	var maximum := int((Defs.balance("events").get("events", {}) as Dictionary).get("chronicle_max", 600))
	# the oldest lines go first, except the founding ones: the arrival of the six, the first families, the
	# choice of the house and the crowning are the beginning of the story and are never forgotten
	var i := 0
	while world.chronicle.size() > maximum and i < world.chronicle.size():
		if is_founding_entry(world.chronicle[i]):
			i += 1
			continue
		world.chronicle.remove_at(i)


static func is_founding_entry(entry: Dictionary) -> bool:
	return String(entry.get("kind", "")).begins_with("founding")


## Each realm starts with the spirits its own land suggests.
func _seed_spirits() -> void:
	for k in world.kingdoms:
		if k.spirits.is_empty() and not bool(k.records.get(&"spirits_seeded", 0.0)):
			k.records[&"spirits_seeded"] = 1.0
			NationalSpiritSystem.grant_initial(self, k)


## Turns one simulation system off (or back on): used by the scenarios and by the tests that want to weigh
## one part of the world without the rest of it moving.
func set_system_enabled(system_id: StringName, on: bool) -> void:
	var system := scheduler.get_system(system_id)
	if system:
		system.enabled = on


func day() -> int:
	return world.day


func date_text() -> String:
	return calendar.format_date(world.day)


func submit(command: Command) -> CommandResult:
	return commands.submit(self, command)


## Advance by real elapsed time (called every frame by SimulationRunner). Returns ticks simulated.
func advance_real(real_delta: float) -> int:
	var n := clock.consume(real_delta)
	for i in n:
		step_tick()
	return n


## Advance exactly one tick.
func step_tick() -> void:
	world.tick += 1
	var tpd := world.ticks_per_day
	_step.tick = world.tick
	_step.ticks_per_day = tpd
	_step.tick_in_day = world.tick % tpd
	_step.day = world.tick / tpd
	_step.is_new_day = _step.tick_in_day == 0
	_step.is_new_month = _step.is_new_day and calendar.is_month_start(_step.day)
	_step.is_new_year = _step.is_new_day and calendar.is_year_start(_step.day)
	scheduler.run_step(self, _step)


## Headless helper: simulate whole days.
func advance_days(days: int) -> void:
	for i in days * world.ticks_per_day:
		step_tick()

