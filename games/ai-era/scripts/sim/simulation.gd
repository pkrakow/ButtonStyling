class_name Simulation
extends RefCounted
## Deterministic world simulation. All randomness flows through `rng`, seeded once
## in start(); identical seeds plus identical choices give identical runs.
## No engine nodes are used so it can be unit-tested headless.

const D := preload("res://scripts/sim/sim_data.gd")

enum Phase { CARD, DILEMMA, OVER }

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var turn: int = 0
var phase: Phase = Phase.CARD
var g: Dictionary = {}
var levers: Dictionary = {}
var regions: Array = []
var flags: Dictionary = {}
var fired: Dictionary = {}
var offers: Array = []
var pending_event: Dictionary = {}
var news: Array = [] # [{turn, title, text, region}]
var turn_news: Array = []
var history: Array = []
var ending_id: String = ""
var unrest_streak: int = 0
var picks_by_type: Dictionary = {"policy": 0, "research": 0, "invest": 0}
var picked_cards: Array = []
var actions: Array = [] # [["c"|"d", index], ...] replayable from the seed
var _last_offer_ids: Array = []


func start(p_seed: int) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	turn = 0
	phase = Phase.CARD
	g = D.START_GLOBAL.duplicate(true)
	levers = {}
	for l in D.LEVERS:
		levers[l] = 0.0
	regions = []
	for r in D.REGIONS:
		regions.append({
			"id": r.id, "code": r.code, "name": r.name, "pop": r.pop, "start_pop": r.pop,
			"hub": r.hub, "exposure": r.exposure, "birth": r.birth,
			"prosperity": r.prosperity, "jobs": r.jobs, "unrest": r.unrest,
			"compute": r.compute, "adoption": r.adoption,
		})
	flags = {}
	fired = {}
	news = []
	turn_news = []
	history = []
	ending_id = ""
	unrest_streak = 0
	picks_by_type = {"policy": 0, "research": 0, "invest": 0}
	picked_cards = []
	actions = []
	_last_offer_ids = []
	for ev in D.EVENTS:
		if ev.get("scripted_turn", -1) == 0:
			_fire_event(ev)
	history.append(snapshot())
	_draw_offers()


# ---------------------------------------------------------------- queries

static func date_for_turn(t: int) -> Dictionary:
	var q := (D.START_QUARTER - 1) + t
	return {"year": D.START_YEAR + q / 4, "quarter": q % 4 + 1}


func date() -> Dictionary:
	return date_for_turn(turn)


func date_label() -> String:
	var d := date()
	return "%d Q%d" % [d.year, d.quarter]


func is_over() -> bool:
	return phase == Phase.OVER


func world_population() -> float:
	var total := 0.0
	for r in regions:
		total += r.pop
	return total


func avg(stat: String) -> float:
	var total := 0.0
	for r in regions:
		total += r[stat]
	return total / regions.size()


func region_extreme(stat: String, highest: bool) -> Dictionary:
	var best: Dictionary = regions[0]
	for r in regions:
		if (highest and r[stat] > best[stat]) or (not highest and r[stat] < best[stat]):
			best = r
	return best


func snapshot() -> Dictionary:
	var d := date()
	return {
		"turn": turn, "year": d.year, "quarter": d.quarter,
		"population_m": snappedf(world_population(), 0.1),
		"prosperity": snappedf(avg("prosperity"), 0.01), "jobs": snappedf(avg("jobs"), 0.01),
		"unrest": snappedf(avg("unrest"), 0.01), "compute": snappedf(avg("compute"), 0.01),
		"adoption": snappedf(avg("adoption"), 0.01),
		"capability": snappedf(g.capability, 0.01), "safety": snappedf(g.safety, 0.01),
		"trust": snappedf(g.trust, 0.01), "inequality": snappedf(g.inequality, 0.01),
	}


func offer_ids() -> Array:
	var ids := []
	for c in offers:
		ids.append(c.id)
	return ids


# ---------------------------------------------------------------- actions

## Pick one of the offered cards. Returns false if the action is invalid now.
func choose_card(index: int) -> bool:
	if phase != Phase.CARD or index < 0 or index >= offers.size():
		return false
	var card: Dictionary = offers[index]
	actions.append(["c", index])
	picks_by_type[card.type] += 1
	picked_cards.append(card.id)
	turn_news = []
	_apply_fx(card.fx, card.get("target_index", -1))
	if card.has("sets"):
		flags[card.sets] = true
	_tick()
	_roll_event()
	if pending_event.is_empty():
		_finish_turn()
	else:
		phase = Phase.DILEMMA
	return true


func choose_dilemma(index: int) -> bool:
	if phase != Phase.DILEMMA:
		return false
	var opts: Array = pending_event.options
	if index < 0 or index >= opts.size():
		return false
	var opt: Dictionary = opts[index]
	actions.append(["d", index])
	_apply_fx(opt.fx, pending_event.get("target_index", -1))
	if opt.has("sets"):
		flags[opt.sets] = true
	pending_event = {}
	_finish_turn()
	return true


## Rebuilds a run from its seed and recorded actions. Returns null if the actions
## no longer replay (for example, content changed between versions).
static func restore(p_seed: int, p_actions: Array):
	var sim = load("res://scripts/sim/simulation.gd").new()
	sim.start(p_seed)
	for a in p_actions:
		if not (a is Array and a.size() == 2):
			return null
		var ok: bool = sim.choose_card(int(a[1])) if a[0] == "c" else sim.choose_dilemma(int(a[1]))
		if not ok:
			return null
	return sim


# ---------------------------------------------------------------- internals

func _finish_turn() -> void:
	turn += 1
	history.append(snapshot())
	_check_endings()
	if phase != Phase.OVER:
		phase = Phase.CARD
		_draw_offers()
	else:
		offers = []


func _check_endings() -> void:
	unrest_streak = unrest_streak + 1 if avg("unrest") >= 70.0 else 0
	var runaway: bool = g.capability >= 75.0 and g.capability - g.safety >= 40.0
	if turn >= D.MIN_TURN_FOR_EARLY_END:
		if runaway:
			_end("runaway")
			return
		if unrest_streak >= 3:
			_end("collapse")
			return
	if turn >= D.MAX_TURNS:
		_end(_final_ending(runaway))


func _final_ending(runaway: bool) -> String:
	if runaway:
		return "runaway"
	if unrest_streak >= 2:
		return "collapse"
	var spread: float = region_extreme("prosperity", true).prosperity - region_extreme("prosperity", false).prosperity
	if g.capability < 35.0:
		return "winter"
	if g.capability >= 50.0 and avg("prosperity") >= 65.0 and avg("unrest") <= 35.0 and g.inequality <= 50.0:
		return "abundance"
	if g.inequality >= 58.0 or spread >= 50.0:
		return "divide"
	if g.safety >= g.capability - 10.0 and avg("unrest") < 45.0:
		return "careful"
	return "muddle"


func _end(id: String) -> void:
	ending_id = id
	phase = Phase.OVER


func _tick() -> void:
	var cap: float = g.capability
	var avg_compute := avg("compute")
	var cap_growth: float = 0.7 + 0.6 * levers.research + avg_compute / 30.0 - 0.35 * levers.regulation + rng.randf_range(-0.3, 0.5)
	g.capability += maxf(cap_growth, 0.1) * (1.0 - cap / 120.0)
	g.safety += 0.15 + 0.35 * levers.alignment + 0.15 * levers.regulation - 0.15 * levers.openness + rng.randf_range(-0.2, 0.2)

	for r in regions:
		var noise := rng.randf_range(-1.0, 1.0)
		r.compute += 0.3 + 0.9 * r.hub + 0.4 * levers.openness * (1.0 - r.hub)
		r.adoption += (cap / 100.0) * (2.0 + 2.5 * r.hub + 1.2 * levers.openness + r.compute / 40.0) \
			* (0.5 + g.trust / 100.0) * (1.0 - 0.2 * levers.regulation) * (1.0 - r.adoption / 100.0)
		var automation: float = (r.adoption / 100.0) * (cap / 100.0) * r.exposure
		r.jobs += -automation * 6.0 + 0.3 * levers.retraining + r.adoption / 100.0 * 0.8 \
			+ (r.prosperity - 50.0) * 0.01 + (60.0 - r.jobs) * 0.04 + noise * 0.5
		var gain: float = (r.adoption / 100.0) * (cap / 100.0) * 3.0 \
			* (0.6 + 0.4 * r.hub + 0.3 * levers.openness * (1.0 - r.hub))
		var drag: float = (r.unrest / 100.0) * 1.5 + 0.15 * levers.safety_net + maxf(0.0, 40.0 - r.jobs) * 0.03
		r.prosperity += gain - drag + 0.15 * levers.health + 0.2 + noise * 0.3
		var unrest_target: float = 20.0 + maxf(0.0, 60.0 - r.jobs) * 1.2 + (g.inequality - 40.0) * 0.6 \
			+ (50.0 - g.trust) * 0.25 + maxf(0.0, 45.0 - r.prosperity) * 0.5 - levers.safety_net * 4.0
		r.unrest += (unrest_target - r.unrest) * 0.18 + noise
		var rate: float = r.birth * (1.0 + (r.prosperity - 50.0) / 150.0) + 0.0004 * levers.health
		if r.unrest > 70.0:
			rate -= 0.002 * (r.unrest - 70.0) / 30.0
		r.pop *= 1.0 + rate
		_clamp_region(r)

	var spread: float = region_extreme("prosperity", true).prosperity - region_extreme("prosperity", false).prosperity
	var ineq_target: float = 25.0 + spread * 0.5 + (60.0 - avg("jobs")) * 0.3 - levers.openness * 3.0 - levers.safety_net * 2.0
	g.inequality += (ineq_target - g.inequality) * 0.15
	var trust_target: float = 55.0 + (g.safety - g.capability * 0.6) * 0.4 - (avg("unrest") - 25.0) * 0.4 + (avg("prosperity") - 50.0) * 0.2
	g.trust += (trust_target - g.trust) * 0.12
	_clamp_global()


func _clamp_region(r: Dictionary) -> void:
	for s in D.REGION_STATS:
		r[s] = clampf(r[s], 0.0, 100.0)


func _clamp_global() -> void:
	for s in D.GLOBAL_STATS:
		g[s] = clampf(g[s], 0.0, 100.0)


func _apply_fx(fx: Dictionary, target_index: int) -> void:
	for key in fx:
		var v: float = float(fx[key])
		var parts: PackedStringArray = String(key).split(".")
		if parts.size() == 1:
			g[key] += v
		elif parts[0] == "lever":
			levers[parts[1]] = clampf(levers[parts[1]] + v, 0.0, 3.0)
		elif parts[0] == "all":
			for r in regions:
				r[parts[1]] += v
		elif parts[0] == "target" and target_index >= 0:
			regions[target_index][parts[1]] += v
	for r in regions:
		_clamp_region(r)
	_clamp_global()


func _card_eligible(c: Dictionary) -> bool:
	if c.has("requires") and not flags.has(c.requires):
		return false
	if g.capability < c.get("min_capability", 0.0):
		return false
	return not _last_offer_ids.has(c.id)


func _draw_offers() -> void:
	offers = []
	for type in ["policy", "research", "invest"]:
		var pool := []
		for c in D.CARDS:
			if c.type == type and _card_eligible(c):
				pool.append(c)
		var card: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate(true)
		var target := -1
		match card.get("target", ""):
			"any":
				target = rng.randi_range(0, regions.size() - 1)
			"poor":
				target = _poorest_indices(3)[rng.randi_range(0, 2)]
		if target >= 0:
			card["target_index"] = target
			card["target_id"] = regions[target].id
			card.text = String(card.text).format({"region": regions[target].name})
		offers.append(card)
	_last_offer_ids = offer_ids()


func _poorest_indices(n: int) -> Array:
	var idx := range(regions.size())
	idx.sort_custom(func(a, b): return regions[a].prosperity < regions[b].prosperity)
	return idx.slice(0, n)


func _event_eligible(ev: Dictionary) -> bool:
	if ev.has("scripted_turn"):
		return false
	if ev.get("once", true) and fired.has(ev.id):
		return false
	if ev.has("requires") and not flags.has(ev.requires):
		return false
	if date().year < ev.get("min_year", 0):
		return false
	if g.capability < ev.get("min_capability", 0.0):
		return false
	if g.safety > ev.get("max_safety", 101.0):
		return false
	if g.capability - g.safety < ev.get("min_gap", -101.0):
		return false
	if avg("adoption") < ev.get("min_avg_adoption", 0.0):
		return false
	if avg("compute") < ev.get("min_avg_compute", 0.0):
		return false
	if region_extreme("unrest", true).unrest < ev.get("min_max_unrest", 0.0):
		return false
	var ml: Dictionary = ev.get("min_lever", {})
	for l in ml:
		if levers[l] < ml[l]:
			return false
	return true


func _roll_event() -> void:
	var candidates := []
	for ev in D.EVENTS:
		if _event_eligible(ev):
			candidates.append(ev)
	# Fisher-Yates with our rng so ordering is seed-determined.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	for ev in candidates:
		if rng.randf() < ev.get("chance", 0.0):
			_fire_event(ev)
			return


func _fire_event(ev: Dictionary) -> void:
	fired[ev.id] = true
	var target := -1
	match ev.get("target", ""):
		"max_unrest":
			target = regions.find(region_extreme("unrest", true))
		"max_compute":
			target = regions.find(region_extreme("compute", true))
		"any":
			target = rng.randi_range(0, regions.size() - 1)
	var region_name: String = regions[target].name if target >= 0 else ""
	var item := {"turn": turn, "id": ev.id, "title": ev.title,
		"text": String(ev.text).format({"region": region_name}), "region": regions[target].id if target >= 0 else ""}
	news.append(item)
	turn_news.append(item)
	if ev.has("options"):
		pending_event = ev.duplicate(true)
		pending_event["target_index"] = target
		pending_event.text = item.text
	else:
		_apply_fx(ev.fx, target)
		if ev.has("sets"):
			flags[ev.sets] = true


# ---------------------------------------------------------------- summary

func summary() -> Dictionary:
	var start_pop := 0.0
	for r in regions:
		start_pop += r.start_pop
	return {
		"ending": ending_id,
		"turns": turn,
		"final_date": "%d Q%d" % [date_for_turn(turn - 1).year, date_for_turn(turn - 1).quarter],
		"population_start_m": snappedf(start_pop, 0.1),
		"population_end_m": snappedf(world_population(), 0.1),
		"state": snapshot(),
		"levers": levers.duplicate(),
		"flags": flags.keys(),
		"picks_by_type": picks_by_type.duplicate(),
		"events_fired": fired.keys(),
		"richest_region": region_extreme("prosperity", true).id,
		"most_unrest_region": region_extreme("unrest", true).id,
	}


func epilogue() -> Array:
	var lines := []
	var e: Dictionary = D.ENDINGS.get(ending_id, D.ENDINGS.muddle)
	lines.append(e.summary)
	var s := summary()
	lines.append("World population went from %.2f billion to %.2f billion." % [s.population_start_m / 1000.0, s.population_end_m / 1000.0])
	lines.append("%s ended up the most prosperous region; %s saw the most unrest." % [
		region_extreme("prosperity", true).name, region_extreme("unrest", true).name])
	if flags.has("treaty"):
		lines.append("The compute treaty you signed is still enforced by inspectors.")
	if flags.has("shipped_unsafe"):
		lines.append("Engineers still argue about the model you patched and shipped.")
	if flags.has("open_era"):
		lines.append("Open models became shared infrastructure, like roads or water.")
	if levers.health >= 2.0:
		lines.append("AI-driven medicine added years to average life expectancy.")
	if levers.safety_net >= 2.0:
		lines.append("A strong safety net caught most people whose jobs disappeared.")
	if avg("jobs") < 40.0:
		lines.append("Fewer than half of working-age adults hold a traditional job.")
	match ending_id:
		"runaway":
			lines.append("Rebuilding trust in computers took the rest of the decade.")
		"collapse":
			lines.append("A new generation of leaders promised to do it differently.")
		"abundance":
			lines.append("Historians will call this the decade the world got a raise.")
		"divide":
			lines.append("Migration to the AI hubs became the defining fight of the 2030s.")
		"winter":
			lines.append("Somewhere, a lab is still quietly training the next model.")
		"careful":
			lines.append("Nobody threw a parade. That was the point.")
		_:
			lines.append("The next decade will test whether that was enough.")
	return lines
