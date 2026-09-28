class_name KDRng
extends RefCounted
## Named deterministic random streams derived from one campaign seed.
## Each system asks for its own stream so adding randomness in one system does not
## shift the sequence of another. Stream states are saved with the game.

var campaign_seed: int = 0
var _streams: Dictionary = {}  # StringName -> RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	campaign_seed = seed_value


func stream(stream_name: StringName) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(stream_name)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = derive_seed(campaign_seed, String(stream_name))
		_streams[stream_name] = rng
	return rng


static func derive_seed(base: int, key: String) -> int:
	var h1 := hash("%d|%s" % [base, key])
	var h2 := hash("%s|%d|kd" % [key, base])
	return (h1 << 32) ^ h2


## Stable hash in [0,1) for deterministic placement (trees, decorations). Independent of streams.
static func hash01(x: int, y: int, salt: int = 0) -> float:
	var h := (x * 374761393) ^ (y * 668265263) ^ (salt * 2147483647)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7fffffff) / 2147483648.0


func to_dict() -> Dictionary:
	var states := {}
	for k in _streams.keys():
		var rng: RandomNumberGenerator = _streams[k]
		states[String(k)] = {"seed": str(rng.seed), "state": str(rng.state)}
	return {"campaign_seed": str(campaign_seed), "streams": states}


static func from_dict(d: Dictionary) -> KDRng:
	var r := KDRng.new(String(d.get("campaign_seed", "0")).to_int())
	var states: Dictionary = d.get("streams", {})
	for k in states.keys():
		var s: Dictionary = states[k]
		var rng := RandomNumberGenerator.new()
		rng.seed = String(s.get("seed", "0")).to_int()
		rng.state = String(s.get("state", "0")).to_int()
		r._streams[StringName(k)] = rng
	return r

