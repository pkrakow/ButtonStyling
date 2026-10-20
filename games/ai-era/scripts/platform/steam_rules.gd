extends RefCounted
## Pure mapping from gameplay moments to Steam achievements and stats, so the
## rules are testable without Steam. API names must match Steamworks App Admin.
## Stats are aggregated by Valve and carry no personal data.

const ACHIEVEMENTS := {
	"ACH_FIRST_DECISION": "First call: make your first decision.",
	"ACH_REACH_2025": "Still running: reach 2025.",
	"ACH_FINISH_RUN": "Runtime complete: reach the end of 2030 Q3.",
	"ACH_TREATY": "Signatory: sign the global compute treaty.",
	"ACH_HALT": "Pull the brake: halt after the lab near miss.",
	"ACH_END_ABUNDANCE": "Ending: Shared Abundance.",
	"ACH_END_CAREFUL": "Ending: Careful Hands.",
	"ACH_END_DIVIDE": "Ending: The Gilded Divide.",
	"ACH_END_MUDDLE": "Ending: Muddling Through.",
	"ACH_END_WINTER": "Ending: The Long Winter.",
	"ACH_END_COLLAPSE": "Ending: The Great Unrest.",
	"ACH_END_RUNAWAY": "Ending: The Unplugging.",
}

## All INT stats. Ending counters give global ending percentages for free.
const STATS := [
	"STAT_RUNS_STARTED", "STAT_RUNS_FINISHED", "STAT_RUNS_ABANDONED",
	"STAT_PICKS_POLICY", "STAT_PICKS_RESEARCH", "STAT_PICKS_INVEST",
	"STAT_MAX_YEAR",
	"STAT_END_ABUNDANCE", "STAT_END_CAREFUL", "STAT_END_DIVIDE", "STAT_END_MUDDLE",
	"STAT_END_WINTER", "STAT_END_COLLAPSE", "STAT_END_RUNAWAY",
]


## Returns {"achievements": [names], "add": {stat: delta}, "max": {stat: value}}.
static func on_run_start() -> Dictionary:
	return {"achievements": [], "add": {"STAT_RUNS_STARTED": 1}, "max": {}}


static func on_decision(kind: String, card_type: String, option_label: String, year: int, total_decisions: int) -> Dictionary:
	var out := {"achievements": [], "add": {}, "max": {"STAT_MAX_YEAR": year}}
	if total_decisions == 1:
		out.achievements.append("ACH_FIRST_DECISION")
	if year >= 2025:
		out.achievements.append("ACH_REACH_2025")
	if kind == "card":
		out.add["STAT_PICKS_" + card_type.to_upper()] = 1
	elif option_label == "Sign the treaty":
		out.achievements.append("ACH_TREATY")
	elif option_label == "Halt and investigate":
		out.achievements.append("ACH_HALT")
	return out


static func on_run_end(ending_id: String, turns: int, max_turns: int) -> Dictionary:
	var key := ending_id.to_upper()
	var out := {"achievements": ["ACH_END_" + key], "add": {"STAT_RUNS_FINISHED": 1, "STAT_END_" + key: 1}, "max": {}}
	if turns >= max_turns:
		out.achievements.append("ACH_FINISH_RUN")
	return out


static func on_run_abandon() -> Dictionary:
	return {"achievements": [], "add": {"STAT_RUNS_ABANDONED": 1}, "max": {}}
