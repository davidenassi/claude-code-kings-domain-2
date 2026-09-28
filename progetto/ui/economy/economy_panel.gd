class_name EconomyPanel
extends KDSheet
## The ECONOMIA sheet: what is missing first — where the realm is losing and what it should build — then what the
## crown takes in and pays out every month, what the village holds in its stores and how they moved, who works,
## and, folded, what things are worth on the market of the realm (consolidation: the answers the player looks for
## — what I produce, what I consume, where I am losing, what I must build — before the details; the work of the
## people by estate and family is on the Ceti sheet).

## Food days under which the granaries are a worry, and the hands without work that ask for a workshop.
const FOOD_DAYS_SHORT := 60.0
const IDLE_HANDS := 5

var _needs: VBoxContainer
var _treasury: Label
var _balance: VBoxContainer
var _stores: VBoxContainer
var _work: Label
var _prices: VBoxContainer


func build() -> void:
	section("COSA MANCA")
	_needs = box(2)
	section("IL TESORO")
	_treasury = parchment()
	_balance = box(2)
	section("DEPOSITI")
	_stores = box(2)
	section("LAVORO")
	_work = parchment()
	section("PREZZI DEL REGNO")
	var unfold := Button.new()
	unfold.text = "Mostra i prezzi"
	unfold.toggle_mode = true
	unfold.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(unfold)
	column.add_child(unfold)
	_prices = box(2)
	_prices.visible = false
	unfold.toggled.connect(func(on: bool) -> void:
		_prices.visible = on
		unfold.text = "Nascondi i prezzi" if on else "Mostra i prezzi")


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var world := session.world
	var k := world.player()
	if k == null:
		return
	var settlement: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			settlement = s
			break
	clear(_needs)
	var needs := needs_of(world, k, settlement)
	if needs.is_empty():
		line(_needs, "Nulla di urgente", "", "Depositi con spazio, cibo per più di due mesi, letti liberi, conti in pari.",
			Color("#BFE39A"))
	for need: Array in needs:
		line(_needs, String(need[0]), String(need[1]), String(need[2]), Color("#FFB09A"))
	_treasury.text = "%d oro nelle casse della corona." % roundi(k.treasury)
	if k.treasury < 0.0:
		_treasury.text += "\nLa corona è in debito: i poteri se ne accorgono e i soldati anche."

	clear(_balance)
	var bl: Dictionary = k.last_balance
	if bl.is_empty():
		line(_balance, "Il primo mese non è ancora chiuso", "")
	else:
		line(_balance, "Tasse degli abitanti", "%+.1f" % float(bl.get("taxes", 0.0)),
			"Riscosso: %d%% — quello che la stabilità del regno lascia arrivare alle casse"
				% roundi(float(bl.get("collection", 1.0)) * 100.0), Color("#BFE39A"))
		line(_balance, "Rendite delle province", "%+.1f" % float(bl.get("provinces", 0.0)),
			"Ridotte dal controllo amministrativo, dal malcontento e dalla devastazione; già tolto il costo dell'amministrazione (%.1f)"
				% float(bl.get("administration", 0.0)), Color("#BFE39A"))
		line(_balance, "Commercio", "%+.1f" % float(bl.get("trade", 0.0)),
			"Le eccedenze vendute ai mercanti, oltre la riserva di ogni villaggio (il cibo solo con un anno di scorte)",
			Color("#BFE39A"))
		if float(bl.get("imports", 0.0)) > 0.0:
			line(_balance, "Acquisti", "%-.1f" % -float(bl.get("imports", 0.0)),
				"Pietra, legna e ferro portati dai mercanti quando mancano, più cari del mercato", Color("#FFB09A"))
		line(_balance, "Salari", "%-.1f" % -float(bl.get("wages", 0.0)), "Pagati ogni mese ai lavoratori", Color("#FFB09A"))
		line(_balance, "Manutenzione", "%-.1f" % -float(bl.get("upkeep", 0.0)),
			"Tetti, mulini, magazzini: ogni edificio costa ogni mese una piccola parte di quanto è costato costruirlo", Color("#FFB09A"))
		var soldiers := 0.0
		for a in world.armies:
			if a.kingdom == k.id:
				soldiers += Military.upkeep_per_day(a) * 30.0
		if soldiers > 0.0:
			line(_balance, "Paghe dell'esercito", "%-.1f" % -soldiers, "Pagate ogni giorno alle schiere in campo",
				Color("#FFB09A"))
		var total := float(bl.get("total", 0.0)) - soldiers
		line(_balance, "Saldo del mese", "%+.1f" % total, "",
			Color("#BFE39A") if total >= 0.0 else Color("#FFB09A"))

	clear(_stores)
	if settlement:
		for res: StringName in [&"wood", &"stone", &"iron", &"grain", &"bread", &"weapons"]:
			var rd := Defs.resource(res)
			if rd == null:
				continue
			var capacity := settlement.capacity(world, rd.storage_group)
			var used := settlement.used(rd.storage_group)
			# with the register of the stores (Phase 18): how much it moved the month that closed, and why
			var last: Dictionary = settlement.last_flow.get(res, {})
			var balance := 0
			var why := PackedStringArray()
			for reason: StringName in last.keys():
				balance += int(last[reason])
				why.append("%s %+d" % [TopBar.FLOW_REASONS.get(reason, reason), int(last[reason])])
			var value := "%d" % settlement.amount(res)
			if not last.is_empty():
				value += "   (%+d al mese)" % balance
			line(_stores, rd.display_name, value,
				"Deposito %s: %d su %d%s" % [rd.storage_group, used, capacity,
					"\nIl mese scorso: " + ", ".join(why) if not why.is_empty() else ""],
				Color("#FFB09A") if capacity > 0 and used >= capacity else KDTheme.TEXT_LIGHT)
		line(_stores, "Giorni di cibo", "%d" % roundi(PopulationSystem.food_days(world, settlement)),
			"Quanto durano pane e grano al ritmo di oggi")
		line(_stores, "Letti liberi", "%d" % PopulationSystem.free_beds(world, settlement), "")
	else:
		line(_stores, "Nessun insediamento", "")

	_work.text = ("Al lavoro: %s.\nChi fa cosa, famiglia per famiglia, è nella scheda Ceti (T); nome per nome in Abitanti (P)." %
		EstatesPanel.work_groups_text(world, settlement)) if settlement else "Nessun insediamento."

	clear(_prices)
	var price_keys := k.prices.keys()
	price_keys.sort()
	for res: StringName in price_keys:
		var rd := Defs.resource(res)
		line(_prices, rd.display_name if rd else String(res), "%.2f oro" % float(k.prices[res]),
			"Prezzo di mercato: sale quando la merce scarseggia")
	if price_keys.is_empty():
		line(_prices, "Il mercato non ha ancora parlato", "")


## What is missing, in the order it hurts: [what, how much, what to do]. Only facts the game already measures:
## full stores, the food that will not reach, the beds, the balance of the month, the debt, the idle hands.
static func needs_of(world: WorldState, k: KingdomState, s: SettlementState) -> Array:
	var out: Array = []
	if s != null:
		var days := PopulationSystem.food_days(world, s)
		if days < FOOD_DAYS_SHORT:
			var ovens := PopulationSystem._ovens(world, s)
			var grain_waits := s.amount(&"grain") > 150 and ovens.is_empty()
			out.append(["Cibo per pochi giorni", "%d" % roundi(days),
				"Il grano c'è ma non diventa pane: serve un forno." if grain_waits
					else "Servono campi, e forni se il grano non basta a sfamare tutti."])
		for group: Array in [[&"food", "Granai pieni", "Il raccolto in più va perduto: serve un granaio."],
				[&"material", "Magazzini pieni", "Legna e pietra in più vanno perdute: serve un magazzino."]]:
			var cap := s.capacity(world, group[0])
			if cap > 0 and s.used(group[0]) >= cap:
				out.append([group[1], "%d su %d" % [s.used(group[0]), cap], group[2]])
		var beds := PopulationSystem.free_beds(world, s)
		if beds <= 0:
			out.append(["Nessun letto libero", "%d" % beds, "Chi nasce o arriva dorme all'aperto e se ne va: servono case."])
		var idle := 0
		for p in world.people_of(s.id):
			if p.job == &"idle":
				idle += 1
		if idle >= IDLE_HANDS:
			out.append(["Braccia senza lavoro", "%d" % idle, "Campi, boschi e botteghe darebbero loro un mestiere."])
	var bl: Dictionary = k.last_balance
	if not bl.is_empty() and float(bl.get("total", 0.0)) < 0.0:
		out.append(["Il mese chiude in perdita", "%.1f" % float(bl.get("total", 0.0)),
			"Più commercio e rendite, o meno salari, manutenzioni e truppe."])
	if k.treasury < 0.0:
		out.append(["La corona è in debito", "%d" % roundi(k.treasury), "I poteri se ne accorgono e i soldati anche."])
	return out

