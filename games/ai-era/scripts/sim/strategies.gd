extends RefCounted
## Scripted players used by tests and the balance tool. Each strategy scores the
## offered cards by their effects; ties fall back to a separate seeded rng so the
## simulation's own rng stream is not disturbed.

const WEIGHTS := {
	"random": {},
	"accelerate": {"capability": 3.0, "lever.research": 4.0, "all.adoption": 1.0, "safety": 0.5, "lever.regulation": -3.0},
	"reckless": {"capability": 3.0, "lever.research": 4.0, "safety": -2.0, "lever.alignment": -3.0, "lever.regulation": -4.0, "all.unrest": 0.5},
	"cautious": {"safety": 2.0, "lever.alignment": 4.0, "lever.regulation": 3.0, "capability": -2.0, "lever.research": -3.0},
	"humane": {"all.unrest": -2.0, "lever.safety_net": 5.0, "lever.retraining": 5.0, "all.jobs": 2.0, "inequality": -1.5,
		"all.prosperity": 1.0, "lever.alignment": 2.0, "safety": 1.0, "capability": 0.5, "lever.health": 2.0, "trust": 0.5},
	"hubs": {"target.compute": 1.0, "capability": 2.0, "inequality": 2.0, "lever.openness": -4.0, "lever.safety_net": -3.0,
		"lever.research": 2.0, "all.jobs": -1.0, "safety": 1.0, "lever.alignment": 2.0},
	"chaos": {"all.jobs": -3.0, "all.unrest": 3.0, "trust": -2.0, "lever.safety_net": -5.0, "lever.retraining": -5.0,
		"all.adoption": 2.0, "inequality": 2.0, "capability": 1.0, "safety": 0.5},
}


static func pick(sim, strategy: String, tie_rng: RandomNumberGenerator) -> int:
	var options: Array
	if sim.phase == sim.Phase.DILEMMA:
		options = sim.pending_event.options
	else:
		options = sim.offers
	var w: Dictionary = WEIGHTS.get(strategy, {})
	if w.is_empty():
		return tie_rng.randi_range(0, options.size() - 1)
	var best := 0
	var best_score := -INF
	for i in options.size():
		var fx: Dictionary = options[i].fx
		var score := tie_rng.randf() * 0.01
		for k in fx:
			score += float(fx[k]) * w.get(k, 0.0)
		if score > best_score:
			best_score = score
			best = i
	return best


## Plays a full run and returns the finished simulation.
static func play(seed_value: int, strategy: String, max_steps: int = 500):
	var Sim := preload("res://scripts/sim/simulation.gd")
	var sim = Sim.new()
	sim.start(seed_value)
	var tie := RandomNumberGenerator.new()
	tie.seed = seed_value * 7919 + 13
	var steps := 0
	while not sim.is_over() and steps < max_steps:
		var i := pick(sim, strategy, tie)
		if sim.phase == sim.Phase.DILEMMA:
			sim.choose_dilemma(i)
		else:
			sim.choose_card(i)
		steps += 1
	return sim
