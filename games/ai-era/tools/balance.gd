extends SceneTree
## Balance report: plays many seeded runs per scripted strategy and prints the
## ending distribution. Usage:
##   godot --headless --path games/ai-era -s res://tools/balance.gd -- [runs]

const Strategies := preload("res://scripts/sim/strategies.gd")


func _init() -> void:
	var runs := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	for strategy in Strategies.WEIGHTS:
		var counts := {}
		var turns := 0
		var pop := 0.0
		for s in runs:
			var sim = Strategies.play(1000 + s, strategy)
			counts[sim.ending_id] = counts.get(sim.ending_id, 0) + 1
			turns += sim.turn
			pop += sim.world_population()
		print("%-10s avg_turns=%.1f avg_pop=%.0fM endings=%s" % [strategy, float(turns) / runs, pop / runs, JSON.stringify(counts)])
	var sim = Strategies.play(1234, "random")
	print("sample final state: ", JSON.stringify(sim.snapshot()))
	print("levers: ", JSON.stringify(sim.levers))
	quit()
