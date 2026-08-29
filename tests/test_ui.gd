## UI module tests — hermetic: exercises only pure static helpers (no autoloads, no scene
## tree, no nodes): the coach hint evaluator/picker, number formatting, status glyphs,
## and the code-built theme resource.
extends "res://tests/test_framework.gd"

const Coach = preload("res://src/ui/coach.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const BigNum = preload("res://src/sim/big_num.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")


func test_eval_conditions() -> void:
	var ctx := {
		"max_starved_s": 12.0,
		"bottleneck_stuck_s": 45.0,
		"affordable_bottleneck_upgrade": true,
		"kp": 3.0,
		"skill_affordable": true,
		"can_prestige": false,
	}
	assert_true(Coach.eval_condition({"type": "always"}, ctx), "always fires")
	assert_true(Coach.eval_condition({"type": "station_starved_seconds", "value": 10}, ctx))
	assert_false(Coach.eval_condition({"type": "station_starved_seconds", "value": 20}, ctx))
	assert_true(Coach.eval_condition({"type": "bottleneck_stuck_seconds", "value": 30}, ctx))
	assert_false(Coach.eval_condition({"type": "bottleneck_stuck_seconds", "value": 60.5}, ctx))
	assert_true(Coach.eval_condition({"type": "affordable_bottleneck_upgrade"}, ctx))
	assert_true(Coach.eval_condition({"type": "kp_unspent", "value": 2}, ctx))
	assert_false(Coach.eval_condition({"type": "kp_unspent", "value": 5}, ctx))
	assert_false(Coach.eval_condition({"type": "can_prestige"}, ctx))
	assert_true(Coach.eval_condition({"type": "can_prestige"}, {"can_prestige": true}))
	assert_false(Coach.eval_condition({"type": "unknown_condition"}, ctx), "unknown types never fire")
	assert_false(Coach.eval_condition({}, ctx), "empty condition never fires")


func test_kp_unspent_needs_buyable_skill() -> void:
	var ctx := {"kp": 9.0, "skill_affordable": false}
	assert_false(Coach.eval_condition({"type": "kp_unspent", "value": 1}, ctx),
			"kp_unspent must not nag when no skill is actually buyable")
	ctx["skill_affordable"] = true
	assert_true(Coach.eval_condition({"type": "kp_unspent", "value": 1}, ctx))


func test_pick_hint_priority_and_cooldown() -> void:
	var hints := [
		{"id": "low", "priority": 2, "cooldown_s": 30, "cond": {"type": "always"}},
		{"id": "high", "priority": 9, "cooldown_s": 30, "cond": {"type": "always"}},
		{"id": "off", "priority": 50, "cooldown_s": 30, "cond": {"type": "can_prestige"}},
	]
	var ctx := {"can_prestige": false}
	var picked: Dictionary = Coach.pick_hint(hints, ctx, {}, 100.0)
	assert_eq(str(picked.get("id")), "high", "higher priority int wins")
	picked = Coach.pick_hint(hints, ctx, {"high": 200.0}, 100.0)
	assert_eq(str(picked.get("id")), "low", "cooldown excludes the winner")
	picked = Coach.pick_hint(hints, ctx, {"high": 90.0}, 100.0)
	assert_eq(str(picked.get("id")), "high", "expired cooldown allows again")
	picked = Coach.pick_hint(hints, {"can_prestige": true}, {}, 100.0)
	assert_eq(str(picked.get("id")), "off", "condition flips the winner")
	picked = Coach.pick_hint([], ctx, {}, 100.0)
	assert_true(picked.is_empty(), "no hints -> empty pick")
	var ties := [
		{"id": "first", "priority": 5, "cond": {"type": "always"}},
		{"id": "second", "priority": 5, "cond": {"type": "always"}},
	]
	picked = Coach.pick_hint(ties, ctx, {}, 0.0)
	assert_eq(str(picked.get("id")), "first", "ties resolve to file order")


func test_fmt_mode_shapes() -> void:
	var b = BigNum.make(1.23, 5)
	assert_eq(UiUtil.fmt_mode(b, "suffix"), "123K")
	assert_eq(UiUtil.fmt_mode(b, "scientific"), "1.23e5")
	assert_eq(UiUtil.fmt_mode({"m": 2.0, "e": 3}, "suffix"), "2K", "BigNum dicts format too")
	assert_eq(UiUtil.fmt_mode(950.0, "suffix"), "950")
	assert_eq(UiUtil.fmt_mode(12, "suffix"), "12")
	assert_eq(UiUtil.fmt_mode("weird", "suffix"), "weird", "non-numbers pass through as text")


func test_small_formatters() -> void:
	assert_eq(UiUtil.pct(0.934), "93%")
	assert_eq(UiUtil.pct(0.0), "0%")
	assert_eq(UiUtil.signed_pct_from_mult(0.93), "-7%")
	assert_eq(UiUtil.signed_pct_from_mult(1.05), "+5%")
	assert_eq(UiUtil.trim_float(1.5), "1.5")
	assert_eq(UiUtil.trim_float(2.0), "2")
	var d := UiUtil.duration(3725.0)
	assert_true(d.contains("1") and d.contains("2"), "3725s mentions 1h 2m: got " + d)
	var d2 := UiUtil.duration(42.0)
	assert_true(d2.contains("42"), "short durations show seconds: got " + d2)


func test_status_glyphs() -> void:
	assert_eq(UiUtil.status_glyph(SimTypes.STATUS_RUNNING, true), "!", "bottleneck overrides status")
	assert_eq(UiUtil.status_glyph(SimTypes.STATUS_STARVED, false), "Zz")
	assert_eq(UiUtil.status_glyph(SimTypes.STATUS_BLOCKED, false), "■")
	assert_eq(UiUtil.status_glyph(SimTypes.STATUS_RUNNING, false), "●")
	assert_eq(UiUtil.status_glyph(SimTypes.STATUS_IDLE, false), "○")
	assert_true(UiUtil.status_color(SimTypes.STATUS_RUNNING, true) == UiTheme.COL_RED)
	assert_true(UiUtil.status_color(SimTypes.STATUS_BLOCKED, false) == UiTheme.COL_AMBER)


func test_theme_builds() -> void:
	var t: Theme = UiTheme.build()
	assert_true(t != null, "theme builds headless")
	assert_true(t.has_stylebox("panel", "PanelContainer"))
	assert_true(t.has_stylebox("normal", "Button"))
	assert_true(t.has_stylebox("focus", "Button"), "keyboard focus style exists")
	assert_true(t.has_stylebox("normal", "AccentButton"))
	assert_true(t.has_stylebox("normal", "UpgradeButtonHot"), "bottleneck-help glow style exists")
	assert_eq(String(t.get_type_variation_base("AccentButton")), "Button")
	assert_eq(String(t.get_type_variation_base("CardPanel")), "PanelContainer")
	assert_eq(String(t.get_type_variation_base("SkillNodeReady")), "SkillNode")
