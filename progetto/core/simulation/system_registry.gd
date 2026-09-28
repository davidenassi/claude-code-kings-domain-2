class_name SystemRegistry
extends RefCounted
## The single place where simulation systems are instantiated and registered, in order.
## Adding a system to the game = adding one line here.


static func register_all(session: GameSession) -> void:
	var sch := session.scheduler
	sch.register(TimeSignalsSystem.new())
	sch.register(SettlementDaySystem.new())
	sch.register(SettlementTickSystem.new())
	sch.register(FamilySystem.new())
	sch.register(PopulationSystem.new())
	sch.register(CommunityMilestonesSystem.new())
	sch.register(DistrictSystem.new())
	sch.register(EconomySystem.new())
	sch.register(ProvinceGrowthSystem.new())
	sch.register(NationalSpiritSystem.new())
	sch.register(CultureSystem.new())
	sch.register(CourtSystem.new())
	sch.register(DiplomacySystem.new())
	sch.register(MilitarySystem.new())
	sch.register(WarSystem.new())
	sch.register(ResearchSystem.new())
	sch.register(EventSystem.new())
	sch.register(RealmAiSystem.new())

