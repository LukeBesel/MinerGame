## Data module tests — loads src/data JSONs via the loader statics (no autoload),
## asserts validation is clean, counts/vocabularies match ARCHITECTURE.md section 7,
## and checks the early-game pacing arithmetic against the pinned throughput formula.
extends "res://tests/test_framework.gd"

const Loader = preload("res://src/data/loader.gd")
const BigNum = preload("res://src/sim/big_num.gd")

const STARTERS := ["press", "lathe", "weld"]
const REQUIRED_SKILL_IDS := [
	"powered_conveyors", "kanban", "heijunka", "one_piece_flow", "five_s", "tpm",
	"autonomous_maintenance", "andon_cord", "poka_yoke", "spc", "standard_work",
	"root_cause_analysis", "smed_workshop", "quick_change_tooling", "cellular_layout",
	"takt_time_tuning", "cross_training", "gemba_walks", "suggestion_system", "ci_manager",
]
const REQUIRED_UI_KEYS := [
	"ui.money", "ui.parts_per_sec", "ui.oee", "ui.bottleneck", "ui.kaizen_points",
	"ui.buy", "ui.unlock", "ui.max", "ui.level", "ui.cost", "ui.owned",
	"ui.tab_skills", "ui.tab_kaizen", "ui.tab_stats", "ui.tab_settings",
	"ui.settings_master", "ui.settings_music", "ui.settings_sfx",
	"ui.settings_reduce_motion", "ui.settings_screen_shake", "ui.settings_number_format",
	"ui.settings_export_save", "ui.settings_import_save",
	"ui.offline_title", "ui.offline_body", "ui.prestige_title", "ui.prestige_explain",
	"ui.prestige_confirm", "ui.prestige_button",
	"ui.stats_lifetime_parts", "ui.stats_scrap", "ui.stats_time_played",
	"ui.stats_prestige_count", "ui.toast_save_ok", "ui.toast_save_fail",
	"ui.toast_import_ok", "ui.toast_import_fail", "ui.locked", "ui.walk_hint",
	"ui.orbit_hint", "ui.throughput", "ui.quality", "ui.uptime", "ui.changeover",
	"ui.wip", "ui.scrap",
]


func _db() -> Dictionary:
	var db_v = Loader.load_all()
	var db: Dictionary = db_v
	return db


func _find(arr: Array, id: String) -> Dictionary:
	for item_v in arr:
		if typeof(item_v) == TYPE_DICTIONARY and str(item_v.get("id", "")) == id:
			return item_v
	return {}


## Effective base throughput per the pinned sim formula (section 6).
func _base_throughput(s: Dictionary, changeover_period: float) -> float:
	var base: Dictionary = s["base"]
	var avail: float = maxf(0.05, float(base["uptime"]) * (1.0 - float(base["changeover_time"]) / changeover_period))
	return float(base["capacity"]) * avail * float(base["quality"]) / float(base["cycle_time"])


func test_validate_returns_no_errors() -> void:
	var db: Dictionary = _db()
	var errors = Loader.validate(db)
	assert_eq(errors.size(), 0, "validation errors: " + str(errors))
	for key in ["stations", "skills", "milestones", "achievements", "balance", "hints", "locale"]:
		assert_true(db.has(key), "db missing key '%s'" % key)


func test_stations_pinned_shape() -> void:
	var db: Dictionary = _db()
	var stations: Array = db["stations"]
	assert_eq(stations.size(), 6, "six pinned stations")
	var expected := ["press", "lathe", "weld", "paint", "assembly", "pack"]
	for i in stations.size():
		var s: Dictionary = stations[i]
		assert_eq(s["id"], expected[i], "station order pinned")
		assert_eq(int(s["order"]), i, "order field matches index")
		var ups: Dictionary = s["upgrades"]
		assert_eq(ups.size(), 4, "exactly four upgrade tracks on %s" % expected[i])
		for track in ["speed", "machine", "tooling", "smed"]:
			assert_true(ups.has(track), "%s has pinned track '%s'" % [expected[i], track])
	# first three free, the rest cost money in ascending order
	var prev_unlock := 0.0
	for i in stations.size():
		var s: Dictionary = stations[i]
		var cost_d: Dictionary = s["unlock_cost"]
		var cost = BigNum.from_dict(cost_d)
		var cost_f: float = cost.to_float()
		if i < 3:
			assert_true(cost.is_zero(), "%s starts unlocked (cost 0)" % str(s["id"]))
		else:
			assert_true(cost_f > 0.0, "%s must cost money" % str(s["id"]))
			assert_true(cost_f > prev_unlock, "unlock costs ascend along the line")
			prev_unlock = cost_f


func test_costs_normalized_per_sim_contract() -> void:
	# unlock_cost -> BigNum dict {"m","e"} (sim reads it via BigNum.from_dict);
	# base_cost -> plain float (sim's cost curves consume floats).
	var db: Dictionary = _db()
	var stations: Array = db["stations"]
	for s_v in stations:
		var s: Dictionary = s_v
		assert_true(s["unlock_cost"] is Dictionary and s["unlock_cost"].has("m") and s["unlock_cost"].has("e"),
			"unlock_cost normalized to {m,e} for %s" % str(s["id"]))
		var ups: Dictionary = s["upgrades"]
		for track in ups.keys():
			var u: Dictionary = ups[track]
			assert_true(typeof(u["base_cost"]) == TYPE_FLOAT,
				"base_cost normalized to float for %s.%s" % [str(s["id"]), str(track)])
			assert_true(float(u["base_cost"]) > 0.0,
				"base_cost positive for %s.%s" % [str(s["id"]), str(track)])
	var lathe: Dictionary = _find(stations, "lathe")
	assert_near(float(lathe["upgrades"]["speed"]["base_cost"]), 3.0, 0.001,
		"lathe speed base cost survives normalization")
	var paint: Dictionary = _find(stations, "paint")
	var paint_unlock = BigNum.from_dict(paint["unlock_cost"])
	assert_true(paint_unlock.to_float() > 0.0, "paint unlock cost round-trips through BigNum")


func test_growth_within_design_range() -> void:
	var db: Dictionary = _db()
	var stations: Array = db["stations"]
	for s_v in stations:
		var s: Dictionary = s_v
		var ups: Dictionary = s["upgrades"]
		for track in ups.keys():
			var g := float(ups[track]["growth"])
			assert_true(g >= 1.07 and g <= 1.15,
				"growth %.3f for %s.%s inside design range [1.07, 1.15]" % [g, str(s["id"]), str(track)])


func test_skill_tree_counts_and_required_nodes() -> void:
	var db: Dictionary = _db()
	var skills: Array = db["skills"]
	assert_true(skills.size() >= 44 and skills.size() <= 60, "44-60 skill nodes, found %d" % skills.size())
	for rid in REQUIRED_SKILL_IDS:
		assert_false(_find(skills, rid).is_empty(), "required lean node '%s' present" % rid)
	# every branch spans rows 0..8
	var rows_by_branch: Dictionary = {}
	for n_v in skills:
		var n: Dictionary = n_v
		var branch := str(n["branch"])
		if not rows_by_branch.has(branch):
			rows_by_branch[branch] = {}
		rows_by_branch[branch][int(n["row"])] = true
	for branch in ["flow", "reliability", "quality", "speed", "people"]:
		assert_true(rows_by_branch.has(branch), "branch '%s' populated" % branch)
		var rows: Dictionary = rows_by_branch.get(branch, {})
		assert_true(rows.has(0), "branch '%s' has a row-0 entry node" % branch)
		assert_true(rows.has(8), "branch '%s' has a row-8 capstone" % branch)


func test_skill_signature_nodes() -> void:
	var db: Dictionary = _db()
	var skills: Array = db["skills"]
	var conveyors: Dictionary = _find(skills, "powered_conveyors")
	assert_eq(conveyors["branch"], "flow", "conveyor visual node in flow")
	assert_eq(int(conveyors["row"]), 0, "conveyor visual node early")
	assert_eq(int(conveyors["cost"]), 1, "conveyor visual node cheap")
	var has_feature := false
	for e_v in conveyors["effects"]:
		if str(e_v.get("type", "")) == "unlock_feature":
			has_feature = true
	assert_true(has_feature, "powered_conveyors carries unlock_feature")
	var kanban: Dictionary = _find(skills, "kanban")
	var has_buffer_shrink := false
	var has_tp_bonus := false
	for e_v in kanban["effects"]:
		var e: Dictionary = e_v
		if str(e.get("type", "")) == "buffer_cap_mult" and float(e.get("value", 1.0)) < 1.0:
			has_buffer_shrink = true
		if str(e.get("type", "")) == "global_throughput_mult" and float(e.get("value", 1.0)) > 1.0:
			has_tp_bonus = true
	assert_true(has_buffer_shrink, "Kanban shrinks buffers (buffer_cap_mult < 1)")
	assert_true(has_tp_bonus, "Kanban grants throughput bonus")
	var andon: Dictionary = _find(skills, "andon_cord")
	var has_refund := false
	for e_v in andon["effects"]:
		if str(e_v.get("type", "")) == "scrap_refund_frac":
			has_refund = true
	assert_true(has_refund, "Andon cord grants scrap_refund_frac")
	var suggest: Dictionary = _find(skills, "suggestion_system")
	var has_passive := false
	for e_v in suggest["effects"]:
		if str(e_v.get("type", "")) == "kp_passive_per_min":
			has_passive = true
	assert_true(has_passive, "suggestion system grants kp_passive_per_min")
	var ci: Dictionary = _find(skills, "ci_manager")
	assert_eq(ci["branch"], "people", "CI manager in people branch")
	assert_eq(int(ci["row"]), 8, "CI manager is the people capstone")
	assert_eq(int(ci["cost"]), 12, "CI manager costs 12 KP")
	var has_auto := false
	for e_v in ci["effects"]:
		var e: Dictionary = e_v
		if str(e.get("type", "")) == "auto_buyer" and float(e.get("interval", 0.0)) > 0.0:
			has_auto = true
	assert_true(has_auto, "CI manager grants auto_buyer with interval")


func test_skill_effect_vocabulary_and_prereqs() -> void:
	var db: Dictionary = _db()
	var skills: Array = db["skills"]
	var by_id: Dictionary = {}
	for n_v in skills:
		by_id[str(n_v["id"])] = n_v
	var vocab: Array = Loader.EFFECT_TYPES
	for n_v in skills:
		var n: Dictionary = n_v
		assert_true(n["effects"].size() >= 1, "%s has effects" % str(n["id"]))
		for e_v in n["effects"]:
			assert_true(vocab.has(str(e_v.get("type", ""))),
				"effect type '%s' on %s in pinned vocabulary" % [str(e_v.get("type", "")), str(n["id"])])
		for p_v in n["prereqs"]:
			var pid := str(p_v)
			assert_true(by_id.has(pid), "prereq '%s' of %s exists" % [pid, str(n["id"])])
			if by_id.has(pid):
				var pre: Dictionary = by_id[pid]
				assert_eq(pre["branch"], n["branch"], "prereq stays in branch for %s" % str(n["id"]))
				assert_true(int(pre["row"]) < int(n["row"]), "prereq row precedes %s" % str(n["id"]))


func test_milestones_counts_and_kp_budget() -> void:
	var db: Dictionary = _db()
	var milestones: Array = db["milestones"]
	assert_true(milestones.size() >= 20 and milestones.size() <= 26,
		"about 20-24 milestones, found %d" % milestones.size())
	var total_kp := 0
	var vocab: Array = Loader.TRIGGER_TYPES
	for m_v in milestones:
		var m: Dictionary = m_v
		var kp := int(m["kp"])
		assert_true(kp >= 1 and kp <= 3, "milestone %s grants 1-3 KP" % str(m["id"]))
		total_kp += kp
		var tr: Dictionary = m["trigger"]
		assert_true(vocab.has(str(tr["type"])), "milestone trigger type in vocabulary")
	assert_true(total_kp >= 30, "milestone KP total funds the early tree (got %d)" % total_kp)
	# the early drip alone must buy 6-10 cheap nodes (1-3 KP each)
	var early_kp := 0
	for m_v in milestones:
		var m: Dictionary = m_v
		var tr: Dictionary = m["trigger"]
		var ttype := str(tr["type"])
		var early := false
		if ttype == "lifetime_parts" and float(tr["value"]) <= 2500.0:
			early = true
		elif ttype == "money_earned" and float(tr["value"]) <= 5000.0:
			early = true
		elif ttype == "oee" or ttype == "skill_count":
			early = true
		elif ttype == "bottleneck_cleared_count" and float(tr["value"]) <= 15.0:
			early = true
		elif ttype == "upgrade_count" and float(tr["value"]) <= 50.0:
			early = true
		elif ttype == "pps" and float(tr["value"]) <= 5.0:
			early = true
		elif ttype == "station_unlocked" and str(tr["value"]) != "pack":
			early = true
		if early:
			early_kp += int(m["kp"])
	assert_true(early_kp >= 18, "pre-prestige milestone drip >= 18 KP (got %d)" % early_kp)


func test_achievements_counts_and_flavor() -> void:
	var db: Dictionary = _db()
	var achievements: Array = db["achievements"]
	assert_true(achievements.size() >= 28 and achievements.size() <= 32,
		"28-32 achievements, found %d" % achievements.size())
	var oee85: Dictionary = _find(achievements, "ACH_OEE_85")
	assert_false(oee85.is_empty(), "ACH_OEE_85 present")
	assert_near(float(oee85["trigger"]["value"]), 0.85, 0.0001, "OEE 85 threshold")
	var zero_scrap: Dictionary = _find(achievements, "ACH_ZERO_SCRAP_HOUR")
	assert_false(zero_scrap.is_empty(), "ACH_ZERO_SCRAP_HOUR present")
	assert_eq(zero_scrap["trigger"]["type"], "zero_scrap_seconds", "zero scrap trigger type")
	assert_near(float(zero_scrap["trigger"]["value"]), 3600.0, 0.001, "one full hour")
	var world_class: Dictionary = _find(achievements, "ACH_WORLD_CLASS")
	assert_false(world_class.is_empty(), "ACH_WORLD_CLASS present")
	assert_eq(world_class["trigger"]["type"], "prestige_count", "world class is deep prestige")
	assert_true(float(world_class["trigger"]["value"]) >= 10.0, "world class is DEEP prestige")
	var all_skills: Dictionary = _find(achievements, "ACH_SKILLS_ALL")
	assert_false(all_skills.is_empty(), "ACH_SKILLS_ALL present")
	var skills: Array = db["skills"]
	assert_near(float(all_skills["trigger"]["value"]), float(skills.size()), 0.001,
		"ACH_SKILLS_ALL threshold equals node count")


func test_hints_priorities_and_conditions() -> void:
	var db: Dictionary = _db()
	var hints: Array = db["hints"]
	assert_true(hints.size() >= 8 and hints.size() <= 12, "8-12 hints, found %d" % hints.size())
	var last := 0x7FFFFFFF
	var seen_types: Dictionary = {}
	for h_v in hints:
		var h: Dictionary = h_v
		var pr := int(h["priority"])
		assert_true(pr <= last, "hints sorted by priority descending")
		last = pr
		seen_types[str(h["cond"]["type"])] = true
	for required in ["station_starved_seconds", "affordable_bottleneck_upgrade", "kp_unspent", "can_prestige", "always"]:
		assert_true(seen_types.has(required), "hint condition '%s' covered" % required)


func test_locale_spot_checks() -> void:
	var db: Dictionary = _db()
	var locale: Dictionary = db["locale"]
	assert_eq(locale.get("station.press", ""), "Stamping Press", "pinned press name")
	assert_eq(locale.get("station.lathe", ""), "CNC Lathe", "pinned lathe name")
	assert_eq(locale.get("station.weld", ""), "Weld Cell", "pinned weld name")
	assert_eq(locale.get("station.paint", ""), "Paint Booth", "pinned paint name")
	assert_eq(locale.get("station.assembly", ""), "Assembly Cell", "pinned assembly name")
	assert_eq(locale.get("station.pack", ""), "QA & Packout", "pinned pack name")
	assert_eq(locale.get("upgrade.speed", ""), "Faster Machine", "pinned speed display name")
	assert_eq(locale.get("upgrade.machine", ""), "Add Machine", "pinned machine display name")
	assert_eq(locale.get("upgrade.tooling", ""), "Better Tooling", "pinned tooling display name")
	assert_eq(locale.get("upgrade.smed", ""), "SMED Changeover", "pinned smed display name")
	for key in REQUIRED_UI_KEYS:
		assert_true(locale.has(key), "ui namespace key '%s' present" % key)
	assert_true(str(locale.get("ui.offline_body", "")).contains("{0}"), "offline body has money placeholder")
	assert_true(str(locale.get("ui.offline_body", "")).contains("{1}"), "offline body has duration placeholder")
	assert_true(str(locale.get("ui.walk_hint", "")).contains("Gemba"), "walk hint teaches the term")


func test_early_pacing_arithmetic() -> void:
	var db: Dictionary = _db()
	var balance: Dictionary = db["balance"]
	var stations: Array = db["stations"]
	var period := float(balance["changeover_period_seconds"])
	var starting_money := float(balance["starting_money"])
	# find the slowest starter per the pinned throughput formula
	var slowest: Dictionary = {}
	var slowest_tp := INF
	var tps: Array = []
	for sid in STARTERS:
		var s: Dictionary = _find(stations, sid)
		var tp := _base_throughput(s, period)
		tps.append(tp)
		assert_true(tp > 0.0, "%s base throughput positive" % sid)
		if tp < slowest_tp:
			slowest_tp = tp
			slowest = s
	assert_eq(slowest["id"], "lathe", "lathe opens as the bottleneck")
	# starters staggered but close: everyone stays in the early dance
	var tp_min: float = tps.min()
	var tp_max: float = tps.max()
	assert_true(tp_max / tp_min < 1.6, "starter stagger < 60%% so the constraint keeps moving (%.2f)" % (tp_max / tp_min))
	assert_true(tp_max / tp_min > 1.05, "starters not identical — there IS a bottleneck")
	# upgrade #1 for the slowest starter is affordable at boot
	var cheapest := INF
	var ups: Dictionary = slowest["upgrades"]
	for track in ups.keys():
		cheapest = minf(cheapest, float(ups[track]["base_cost"]))
	assert_true(cheapest <= starting_money,
		"slowest starter's first upgrade (%d) affordable with starting money (%d)" % [int(cheapest), int(starting_money)])
	# the first three speed levels on the slowest starter stay cheap: the opening stays busy
	var speed: Dictionary = ups["speed"]
	var base_f := float(speed["base_cost"])
	var g := float(speed["growth"])
	var first_three: float = base_f * (1.0 + g + g * g)
	assert_true(first_three < 120.0, "first three speed upgrades on slowest starter < 120 (got %.1f)" % first_three)
	# and across ALL starters, the opening speed buys together stay under 120
	var opening_sum := 0.0
	for sid in STARTERS:
		var s: Dictionary = _find(stations, sid)
		opening_sum += float(s["upgrades"]["speed"]["base_cost"])
	assert_true(opening_sum < 120.0, "sum of starters' first speed upgrades < 120 (got %.1f)" % opening_sum)


func test_balance_pinned_keys_and_sanity() -> void:
	var db: Dictionary = _db()
	var balance: Dictionary = db["balance"]
	for key in ["price_per_part", "starting_money", "tick_rate", "buffer_base_cap",
			"changeover_period_seconds", "offline", "prestige", "autosave_seconds",
			"visual", "pacing"]:
		assert_true(balance.has(key), "balance pinned key '%s'" % key)
	assert_true(float(balance["price_per_part"]) > 0.0, "price positive")
	var prestige: Dictionary = balance["prestige"]
	assert_true(float(prestige["min_lifetime_parts"]) > 0.0, "prestige gate positive")
	var pacing: Dictionary = balance["pacing"]
	var window: Array = pacing["first_prestige_target_minutes"]
	assert_eq(window.size(), 2, "prestige window is [lo, hi]")
	assert_true(float(window[0]) < float(window[1]), "prestige window ascending")
	# changeover derate must never floor availability at base stats
	var stations: Array = db["stations"]
	var period := float(balance["changeover_period_seconds"])
	for s_v in stations:
		var s: Dictionary = s_v
		var base: Dictionary = s["base"]
		assert_true(float(base["changeover_time"]) < period * 0.5,
			"%s base changeover well under the changeover period" % str(s["id"]))


func test_orders_data_shape_and_ranges() -> void:
	var db: Dictionary = _db()
	assert_true(db.has("orders"), "db carries the orders config")
	var cfg: Dictionary = db["orders"]
	# Pinned spawn knobs from the design schema.
	assert_near(float(cfg["start_after_seconds"]), 300.0, 1e-9, "orders start after 5 min")
	assert_near(float(cfg["cooldown_seconds"]), 90.0, 1e-9)
	assert_near(float(cfg["min_pps"]), 0.3, 1e-9)
	assert_near(float(cfg["duration_fraction_of_capacity"]), 0.7, 1e-9,
			"orders sized under capacity so they stay beatable")
	var templates: Array = cfg["templates"]
	assert_true(templates.size() >= 8 and templates.size() <= 10,
			"8-10 templates, found %d" % templates.size())
	var locale: Dictionary = db["locale"]
	var seen: Array = []
	var kp_templates := 0
	for t_v in templates:
		var t: Dictionary = t_v
		var tid := str(t["id"])
		assert_false(seen.has(tid), "unique order id '%s'" % tid)
		seen.append(tid)
		assert_true(locale.has(str(t["name_key"])), "order name key '%s' resolves" % str(t["name_key"]))
		var seconds := float(t["seconds"])
		assert_true(seconds >= 60.0 and seconds <= 240.0,
				"'%s' seconds %.0f in design band [60, 240]" % [tid, seconds])
		var mult := float(t["reward_mult"])
		assert_true(mult >= 1.5 and mult <= 3.0,
				"'%s' reward_mult %.2f in design band [1.5, 3.0]" % [tid, mult])
		var kp_bonus := int(t["kp_bonus"])
		assert_true(kp_bonus == 0 or kp_bonus == 1, "'%s' kp_bonus 0 or 1" % tid)
		if kp_bonus == 1:
			kp_templates += 1
		assert_true(int(t["weight"]) >= 1, "'%s' weight >= 1" % tid)
	assert_true(kp_templates >= 1, "at least one order pays a Kaizen Point")


func test_onboarding_data_steps() -> void:
	var db: Dictionary = _db()
	assert_true(db.has("onboarding"), "db carries the onboarding steps")
	var steps: Array = db["onboarding"]
	assert_true(steps.size() >= 5 and steps.size() <= 6, "5-6 steps, found %d" % steps.size())
	var locale: Dictionary = db["locale"]
	var on_upgrade := 0
	var seen: Array = []
	for s_v in steps:
		var s: Dictionary = s_v
		assert_false(seen.has(str(s["id"])), "unique step id")
		seen.append(str(s["id"]))
		assert_true(Loader.ONBOARDING_TARGETS.has(str(s["target"])),
				"target '%s' in the pinned list" % str(s["target"]))
		assert_true(locale.has(str(s["text_key"])), "step text key resolves")
		assert_true(Loader.ONBOARDING_ADVANCE.has(str(s["advance"])), "advance mode valid")
		if str(s["advance"]) == "on_upgrade":
			on_upgrade += 1
			assert_eq(str(s["target"]), "fix_button",
					"the on_upgrade step is the FIX IT step")
	assert_eq(on_upgrade, 1, "exactly one step auto-advances on station_upgraded")
	assert_eq(str((steps[0] as Dictionary)["target"]), "world_bottleneck",
			"the tour opens on the bottleneck — the whole game in one glance")


func test_locale_assist_order_onboarding_keys() -> void:
	# This exact UI-facing list is pinned — the UI agent codes against it verbatim.
	var db: Dictionary = _db()
	var locale: Dictionary = db["locale"]
	assert_eq(locale.get("ui.fix_it", ""), "Fix it — {0}")
	assert_eq(locale.get("ui.fix_saving", ""), "Save up — {0}")
	assert_eq(locale.get("ui.fix_unlock", ""), "Extend the line — {0}")
	assert_eq(locale.get("ui.advanced_toggle", ""), "Advanced")
	assert_eq(locale.get("ui.simple_toggle", ""), "Simple")
	assert_eq(locale.get("ui.order_title", ""), "Rush order")
	assert_eq(locale.get("ui.order_progress", ""), "{0} / {1}")
	assert_eq(locale.get("ui.order_time_left", ""), "{0}s")
	assert_eq(locale.get("ui.order_reward", ""), "Bonus ×{0}")
	assert_eq(locale.get("ui.order_done", ""), "Order shipped! +{0}")
	assert_eq(locale.get("ui.order_missed", ""), "Order missed — another will come along.")
	assert_eq(locale.get("ui.next", ""), "Next")
	assert_eq(locale.get("ui.skip", ""), "Skip")
	assert_eq(locale.get("ui.done", ""), "Got it")
	for i in range(1, 7):
		assert_true(locale.has("onboarding.step%d" % i), "onboarding.step%d present" % i)
		assert_true(str(locale.get("onboarding.step%d" % i, "")).length() > 10,
				"onboarding step %d has real text" % i)


func test_lookup_helpers() -> void:
	var inst = Loader.new()
	inst.db = Loader.load_all()
	var press: Dictionary = inst.station("press")
	assert_eq(press.get("id", ""), "press", "station() lookup by id")
	var missing_station: Dictionary = inst.station("forge")
	assert_true(missing_station.is_empty(), "unknown station returns empty dict")
	var kanban: Dictionary = inst.skill("kanban")
	assert_eq(kanban.get("id", ""), "kanban", "skill() lookup by id")
	var missing_skill: Dictionary = inst.skill("six_sigma_black_hole")
	assert_true(missing_skill.is_empty(), "unknown skill returns empty dict")
	inst.free()
