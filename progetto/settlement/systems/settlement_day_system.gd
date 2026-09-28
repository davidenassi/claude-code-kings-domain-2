class_name SettlementDaySystem
extends SimSystem
## Every day: meals from the stores, job assignment refresh, stumps growing back.


func _init() -> void:
	id = &"settlement_day"
	frequency = Frequency.DAY
	order = 20


func run(session: GameSession, step: SimStep) -> void:
	SettlementSim.day(session, step.day)

