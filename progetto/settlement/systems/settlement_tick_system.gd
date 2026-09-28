class_name SettlementTickSystem
extends SimSystem
## Every hour: inhabitants finish and plan their actions (see SettlementSim).


func _init() -> void:
	id = &"settlement_tick"
	frequency = Frequency.TICK
	order = 50


func run(session: GameSession, _step: SimStep) -> void:
	SettlementSim.tick(session)

