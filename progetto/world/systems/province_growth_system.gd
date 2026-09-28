class_name ProvinceGrowthSystem
extends SimSystem
## Once a year the aggregate population of the provinces moves: villages without a crown and the lands of the AI
## kingdoms grow slowly with fertility and development, and are held back by devastation and by the land itself.
## Provinces that hold a real settlement are left alone: there the people are simulated one by one.


func _init() -> void:
	id = &"province_growth"
	frequency = Frequency.YEAR
	order = 40


func run(session: GameSession, _step: SimStep) -> void:
	var world := session.world
	world.political_version += 1   # the weight of the lands is recomputed with the new census
	var cfg: Dictionary = Defs.balance("population").get("province_growth", {})
	var wd := WorldData.get_instance()
	var simulated := {}
	for s in world.settlements:
		simulated[s.province] = true
	var rng := world.rng.stream(&"provinces")
	for p in world.provinces:
		if simulated.has(p.id):
			continue
		var g := wd.province_geo(p.id)
		var rate := float(cfg.get("annual_rate", 0.006))
		rate *= lerpf(1.0 - float(cfg.get("fertility_weight", 0.9)) * 0.5, 1.0 + float(cfg.get("fertility_weight", 0.9)) * 0.5, g.fertility)
		rate += float(cfg.get("development_weight", 0.05)) * 0.01 * p.development
		rate *= 1.0 - 0.9 * p.devastation
		var cap := int(float(cfg.get("max_per_km2", 45.0)) * g.area_km2 * (0.4 + 0.6 * g.fertility))
		var grown := int(round(p.population * (1.0 + rate)))
		if grown == p.population and rate > 0.0 and rng.randf() < rate * 100.0:
			grown += 1
		p.population = mini(grown, cap)

