class_name CrownEffects
extends RefCounted
## The political price of a decision: favour moved among the powers, turbulence added to the realm.
## Shared by laws, edicts and (later) events, so every decision pays in the same currency.


## `lasting`: a law is remembered by the powers (the daily drift does not undo it); an edict of one season is
## not — repeated every month it used to pin one power at 0 and another at 100 (Phase 16).
static func apply_political(k: KingdomState, entry: Dictionary, lasting: bool = true) -> void:
	var favour: Dictionary = entry.get("favour", {})
	for fid: String in favour.keys():
		var key := StringName(fid)
		k.favour[key] = clampf(float(k.favour.get(key, 55.0)) + float(favour[fid]), 0.0, 100.0)
		if not lasting:
			continue
		# the shift is remembered, so the daily drift does not simply undo the decision
		var bias := StringName("_law_bias_%s" % fid)
		k.favour[bias] = clampf(float(k.favour.get(bias, 0.0)) + float(favour[fid]) * 0.6, -25.0, 25.0)
	k.turbulence += float(entry.get("turbulence", 0.0))

