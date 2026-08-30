## UI module tests — hermetic: exercises only pure static helpers (no autoloads, no scene
## tree, no nodes): the coach hint evaluator/picker, number formatting, status glyphs,
## ui-mode/fix-label resolution, order formatting, onboarding step/spotlight/bubble math,
## responsive layout-mode resolution, touch-camera gesture math, the target registry, and
## the code-built theme resource (desktop + mobile font scales).
extends "res://tests/test_framework.gd"

const Coach = preload("res://src/ui/coach.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Layout = preload("res://src/ui/layout.gd")
const OrderWidget = preload("res://src/ui/order_widget.gd")
const Onboarding = preload("res://src/ui/onboarding.gd")
const OnboardTargets = preload("res://src/ui/onboard_targets.gd")
const CameraRig = preload("res://src/world/camera_rig.gd")
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


func test_resolve_ui_mode() -> void:
	assert_eq(UiUtil.resolve_ui_mode("advanced"), "advanced")
	assert_eq(UiUtil.resolve_ui_mode("simple"), "simple")
	assert_eq(UiUtil.resolve_ui_mode(null), "simple", "missing field defaults to simple")
	assert_eq(UiUtil.resolve_ui_mode(""), "simple")
	assert_eq(UiUtil.resolve_ui_mode(42), "simple", "junk defaults to simple")
	assert_eq(UiUtil.resolve_ui_mode("ADVANCED"), "simple", "exact string match only")


func test_fix_label_key() -> void:
	assert_eq(UiUtil.fix_label_key("upgrade", true), "ui.fix_it")
	assert_eq(UiUtil.fix_label_key("unlock", true), "ui.fix_unlock")
	assert_eq(UiUtil.fix_label_key("upgrade", false), "ui.fix_saving")
	assert_eq(UiUtil.fix_label_key("unlock", false), "ui.fix_saving", "saving wins over kind")
	assert_eq(UiUtil.fix_label_key("", true), "ui.fix_it", "unknown kind reads as upgrade")


func test_order_formatting() -> void:
	assert_near(OrderWidget.order_ratio(5.0, 10.0), 0.5)
	assert_near(OrderWidget.order_ratio(15.0, 10.0), 1.0, 1e-6, "ratio clamped high")
	assert_near(OrderWidget.order_ratio(-3.0, 10.0), 0.0, 1e-6, "ratio clamped low")
	assert_near(OrderWidget.order_ratio(4.0, 0.0), 1.0, 1e-6, "degenerate required counts as done")
	assert_eq(OrderWidget.seconds_left_str(41.2), "42", "countdown ceils")
	assert_eq(OrderWidget.seconds_left_str(0.0), "0")
	assert_eq(OrderWidget.seconds_left_str(-7.0), "0", "never negative")
	var pair: Array = OrderWidget.progress_pair(33.7, 120.0)
	assert_eq(pair[0], "33", "progress floors")
	assert_eq(pair[1], "120")
	var over: Array = OrderWidget.progress_pair(140.2, 120.0)
	assert_eq(over[0], "120", "display never exceeds the requirement")
	var neg: Array = OrderWidget.progress_pair(-2.0, 10.0)
	assert_eq(neg[0], "0", "progress never negative")


func test_onboarding_steps_normalize() -> void:
	var loader_shape := [
		{"id": "a", "target": "coach", "text_key": "onboarding.step1", "advance": "next"},
		{"id": "b", "target": "fix_button", "text_key": "onboarding.step2", "advance": "on_upgrade"},
		"junk",
		{"id": "no_text", "target": "coach"},
	]
	var steps: Array = Onboarding.normalize_steps(loader_shape)
	assert_eq(steps.size(), 2, "junk and text-less steps dropped")
	assert_eq(str((steps[0] as Dictionary).get("advance")), "next")
	assert_eq(str((steps[1] as Dictionary).get("advance")), "on_upgrade")
	var doc_shape := {"steps": [{"text_key": "k", "advance": "weird"}]}
	var steps2: Array = Onboarding.normalize_steps(doc_shape)
	assert_eq(steps2.size(), 1, "document {steps:[...]} shape accepted too")
	assert_eq(str((steps2[0] as Dictionary).get("advance")), "next", "unknown advance -> next")
	assert_eq(str((steps2[0] as Dictionary).get("target")), "", "missing target tolerated")
	assert_true(Onboarding.normalize_steps(null).is_empty())
	assert_true(Onboarding.normalize_steps({"nope": 1}).is_empty())


func test_onboarding_flow_logic() -> void:
	var steps := [
		{"text_key": "a", "advance": "next"},
		{"text_key": "b", "advance": "on_upgrade"},
		{"text_key": "c", "advance": "next"},
	]
	assert_true(Onboarding.shows_next(steps[0]))
	assert_false(Onboarding.shows_next(steps[1]), "on_upgrade hides its Next button")
	assert_true(Onboarding.shows_next({}), "default advance is next")
	assert_eq(Onboarding.next_label_key(steps, 0), "ui.next")
	assert_eq(Onboarding.next_label_key(steps, 1), "ui.next")
	assert_eq(Onboarding.next_label_key(steps, 2), "ui.done", "final step reads Done")
	assert_true(Onboarding.should_show(null, steps), "missing done-field is falsy")
	assert_true(Onboarding.should_show(false, steps))
	assert_false(Onboarding.should_show(true, steps))
	assert_false(Onboarding.should_show(1, steps), "int 1 counts as done")
	assert_false(Onboarding.should_show(false, []), "no steps -> never show")
	assert_false(Onboarding.is_done_value("false"))
	assert_true(Onboarding.is_done_value("true"))
	assert_false(Onboarding.is_done_value(0.0))


func test_onboarding_side_rects() -> void:
	var bounds := Rect2(0, 0, 1000, 600)
	var hole := Rect2(200, 150, 300, 100)
	var rects: Array = Onboarding.side_rects(bounds, hole)
	assert_eq(rects.size(), 4)
	var area := 0.0
	for r_v in rects:
		var r: Rect2 = r_v
		area += r.size.x * r.size.y
		assert_false(r.intersects(hole), "no dim rect overlaps the hole")
	assert_near(area, 1000.0 * 600.0 - 300.0 * 100.0, 0.01, "rects tile bounds minus hole")
	var no_hole: Array = Onboarding.side_rects(bounds, Rect2())
	assert_eq(no_hole[0] as Rect2, bounds, "empty hole -> one full-screen dim rect")
	assert_near((no_hole[1] as Rect2).size.x, 0.0, 1e-9)
	var partial: Array = Onboarding.side_rects(bounds, Rect2(-50, -50, 100, 100))
	var partial_area := 0.0
	for p_v in partial:
		var p: Rect2 = p_v
		partial_area += p.size.x * p.size.y
	assert_near(partial_area, 1000.0 * 600.0 - 50.0 * 50.0, 0.01, "off-screen hole is clamped")


func test_target_registry() -> void:
	var reg = OnboardTargets.new()
	assert_false(reg.has_target("fix_button"))
	assert_eq(reg.rect("fix_button"), Rect2(), "unknown target -> zero rect")
	reg.register("fix_button", func() -> Rect2: return Rect2(10, 20, 30, 40))
	assert_true(reg.has_target("fix_button"))
	assert_eq(reg.rect("fix_button"), Rect2(10, 20, 30, 40))
	reg.register("bad", func() -> String: return "not a rect")
	assert_eq(reg.rect("bad"), Rect2(), "non-Rect2 provider result degrades to zero rect")
	reg.unregister("fix_button")
	assert_false(reg.has_target("fix_button"))
	assert_eq(reg.rect("fix_button"), Rect2())


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


func test_layout_mode_resolution() -> void:
	assert_true(Layout.is_portrait(Vector2(394, 844)), "phone portrait")
	assert_true(Layout.is_portrait(Vector2(800, 800)), "square counts as portrait (1.0 < 1.05)")
	assert_false(Layout.is_portrait(Vector2(844, 394)), "phone landscape")
	assert_false(Layout.is_portrait(Vector2(1280, 720)))
	assert_false(Layout.is_portrait(Vector2(0, 0)), "degenerate window is not portrait")
	assert_true(Layout.scale_size_for(Vector2(394, 844)) == Layout.SCALE_PORTRAIT)
	assert_true(Layout.scale_size_for(Vector2(1280, 720)) == Layout.SCALE_LANDSCAPE)
	assert_true(Layout.scale_size_for(Vector2(844, 394)) == Layout.SCALE_LANDSCAPE)
	assert_eq(Layout.resolve_mode(Vector2(394, 844)), Layout.MODE_MOBILE, "phone portrait -> MOBILE")
	assert_eq(Layout.resolve_mode(Vector2(768, 1024)), Layout.MODE_MOBILE, "tablet portrait -> MOBILE")
	assert_eq(Layout.resolve_mode(Vector2(1280, 720)), Layout.MODE_DESKTOP)
	assert_eq(Layout.resolve_mode(Vector2(844, 394)), Layout.MODE_DESKTOP, "phone landscape uses the desktop layout")
	assert_eq(Layout.resolve_mode(Vector2(1280, 800)), Layout.MODE_DESKTOP, "Steam Deck stays desktop")
	assert_eq(Layout.resolve_mode(Vector2(3440, 1440)), Layout.MODE_DESKTOP, "ultrawide stays desktop")


func test_layout_design_size() -> void:
	# Exact 16:9 on the landscape base: unchanged.
	var d: Vector2 = Layout.design_size(Vector2(1280, 720), Vector2(1280, 720))
	assert_near(d.x, 1280.0)
	assert_near(d.y, 720.0)
	# Phone portrait window on the portrait base: width pinned, height expands.
	d = Layout.design_size(Vector2(394, 844), Vector2(720, 1280))
	assert_near(d.x, 720.0)
	assert_near(d.y, 720.0 * 844.0 / 394.0, 0.01)
	# Wider than base: height pinned, width expands.
	d = Layout.design_size(Vector2(2560, 720), Vector2(1280, 720))
	assert_near(d.y, 720.0)
	assert_near(d.x, 2560.0)
	# Narrower landscape (4:3): width pinned to base, height expands.
	d = Layout.design_size(Vector2(1024, 768), Vector2(1280, 720))
	assert_near(d.x, 1280.0)
	assert_near(d.y, 960.0)
	# Degenerate input falls back to the base.
	d = Layout.design_size(Vector2.ZERO, Vector2(1280, 720))
	assert_near(d.x, 1280.0)
	assert_near(d.y, 720.0)


func test_camera_touch_math() -> void:
	assert_near(CameraRig.pinch_zoom(20.0, 100.0, 200.0), 10.0, 1e-6, "fingers apart = zoom in")
	assert_near(CameraRig.pinch_zoom(20.0, 100.0, 50.0), 40.0, 1e-6, "fingers together = zoom out")
	assert_near(CameraRig.pinch_zoom(20.0, 100.0, 10.0), 48.0, 1e-6, "clamped at wheel max")
	assert_near(CameraRig.pinch_zoom(20.0, 100.0, 100000.0), 6.0, 1e-6, "clamped at wheel min")
	assert_near(CameraRig.pinch_zoom(20.0, 0.0, 50.0), 20.0, 1e-6, "degenerate baseline = keep distance")
	assert_near(CameraRig.pinch_zoom(999.0, 0.0, 0.0), 48.0, 1e-6, "degenerate still clamps")
	assert_true(CameraRig.is_tap(5.0, 200))
	assert_false(CameraRig.is_tap(15.0, 200), "moved too far to be a tap")
	assert_false(CameraRig.is_tap(5.0, 400), "held too long to be a tap")
	assert_near(CameraRig.frame_dist_scale(16.0 / 9.0), 1.0, 1e-6, "landscape framing unchanged")
	assert_near(CameraRig.frame_dist_scale(1.6), 1.0, 1e-6)
	assert_true(CameraRig.frame_dist_scale(0.467) > 3.0, "portrait zooms out to fit the line")
	assert_near(CameraRig.frame_dist_scale(0.1), 4.0, 1e-6, "zoom-out factor capped")
	assert_near(CameraRig.frame_dist_scale(0.0), 1.0, 1e-6, "degenerate aspect ignored")


func test_onboarding_bubble_fit() -> void:
	assert_near(Onboarding.bubble_wrap_width(1280.0), 380.0, 1e-6, "desktop keeps the design width")
	assert_near(Onboarding.bubble_wrap_width(720.0), 380.0, 1e-6, "portrait design space still fits it")
	assert_near(Onboarding.bubble_wrap_width(360.0), 300.0, 1e-6, "narrow spaces shrink the wrap width")
	assert_near(Onboarding.bubble_wrap_width(50.0), 120.0, 1e-6, "wrap width floor")
	# The width-0 mismeasure that ballooned the bubble into a full-screen column must cap.
	var c: Vector2 = Onboarding.clamp_bubble_size(Vector2(412.0, 2356.0), Vector2(720.0, 1542.0))
	assert_near(c.x, 412.0)
	assert_near(c.y, 1542.0 - 16.0, 1e-6, "giant measurement capped to the viewport")
	c = Onboarding.clamp_bubble_size(Vector2(500.0, 200.0), Vector2(360.0, 640.0))
	assert_near(c.x, 360.0 - 16.0, 1e-6, "width capped on tiny spaces")
	assert_near(c.y, 200.0)


func test_pick_hint_exclusions() -> void:
	var hints := [
		{"id": "hint_gemba", "priority": 9, "cond": {"type": "always"}},
		{"id": "other", "priority": 1, "cond": {"type": "always"}},
	]
	var picked: Dictionary = Coach.pick_hint(hints, {}, {}, 0.0, ["hint_gemba"])
	assert_eq(str(picked.get("id")), "other", "excluded (keyboard-only) ids are skipped on touch")
	picked = Coach.pick_hint(hints, {}, {}, 0.0)
	assert_eq(str(picked.get("id")), "hint_gemba", "no exclusions by default")
	picked = Coach.pick_hint(hints, {}, {}, 0.0, ["hint_gemba", "other"])
	assert_true(picked.is_empty(), "everything excluded -> empty pick")


func test_theme_font_scale_and_mobile_chrome() -> void:
	var base: Theme = UiTheme.build()
	var big: Theme = UiTheme.build(UiTheme.MOBILE_FONT_SCALE)
	assert_eq(base.default_font_size, UiTheme.FONT_BODY)
	assert_eq(big.default_font_size, int(roundf(UiTheme.FONT_BODY * UiTheme.MOBILE_FONT_SCALE)))
	for variation in ["TitleLabel", "MoneyLabel", "TinyLabel", "DimLabel"]:
		assert_true(big.get_font_size("font_size", variation) > base.get_font_size("font_size", variation),
				variation + " scales up in MOBILE")
	assert_true(big.get_font_size("font_size", "Button") > base.get_font_size("font_size", "Button"))
	# MOBILE chrome variations exist in both themes.
	for t in [base, big]:
		assert_true(t.has_stylebox("panel", "SheetPanel"), "bottom sheet body style")
		assert_true(t.has_stylebox("panel", "SheetHandle"), "sheet handle style")
		assert_true(t.has_stylebox("panel", "NavPanel"), "bottom nav bar style")
	assert_eq(String(base.get_type_variation_base("NavButton")), "TabButton")


func test_theme_simple_mode_variations() -> void:
	var t: Theme = UiTheme.build()
	assert_eq(String(t.get_type_variation_base("FixButton")), "AccentButton", "FIX IT styles ride the accent CTA")
	assert_true(t.has_font_size("font_size", "FixButton"))
	assert_eq(String(t.get_type_variation_base("CardPanelBottleneck")), "PanelContainer")
	assert_true(t.has_stylebox("panel", "CardPanelBottleneck"), "promoted bottleneck card style exists")
	assert_true(t.has_stylebox("panel", "OrderPanel"), "rush-order bar style exists")
	assert_true(t.has_stylebox("panel", "OrderPanelGood"), "order green-flash style exists")
	assert_eq(String(t.get_type_variation_base("GhostButton")), "Button")
	assert_true(t.has_stylebox("normal", "GhostButton"))
