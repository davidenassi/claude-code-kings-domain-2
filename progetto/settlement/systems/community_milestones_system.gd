class_name CommunityMilestonesSystem
extends SimSystem
## The first pages of the chronicle — the first house, the first harvest, the day the settlement becomes a village,
## the end of a community — written at the close of the day they happen, after the births, the deaths and the
## travellers of that day (Rebirth check: written by FamilySystem at the start of the month, the day a settlement
## became a village could come a month after the day it could already choose its crown).


func _init() -> void:
	id = &"milestones"
	frequency = Frequency.DAY
	order = 26   # after the population (25): the thirtieth soul of the village has arrived


func run(session: GameSession, step: SimStep) -> void:
	FamilySystem.milestones(session, step.day)
