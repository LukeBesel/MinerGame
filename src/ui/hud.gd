## HUD — root CanvasLayer for the whole 2D interface. Builds the entire control tree in
## code (no other scenes) and owns the responsive layout: on every viewport resize it
## sets the orientation-aware content scale (720×1280 portrait / 1280×720 landscape),
## resolves DESKTOP vs MOBILE (src/ui/layout.gd) and re-places everything live.
## DESKTOP: top bar, coach/Andon board, rush-order bar, station column (left), tabbed
## side panel (right). MOBILE: two-row top bar, full-width coach/order strips, bottom
## sheet hosting the station list + FIX IT, bottom nav opening the tabs full-screen.
## Renders from EventBus.sim_stats; commands go through Game (guards in each panel).
extends CanvasLayer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const Layout = preload("res://src/ui/layout.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")
const OnboardTargets = preload("res://src/ui/onboard_targets.gd")

# Panel scripts are loaded at runtime (not preload): hud.gd itself references no autoloads,
# so under --check-only Godot would fully compile preloaded dependencies and report their
# (filtered-elsewhere) autoload identifiers as a hard "depended scripts" failure.
const TOP_BAR_PATH := "res://src/ui/top_bar.gd"
const COACH_PATH := "res://src/ui/coach.gd"
const ORDER_WIDGET_PATH := "res://src/ui/order_widget.gd"
const STATION_PANEL_PATH := "res://src/ui/station_panel.gd"
const RIGHT_PANEL_PATH := "res://src/ui/right_panel.gd"
const OFFLINE_POPUP_PATH := "res://src/ui/offline_popup.gd"
const TOASTS_PATH := "res://src/ui/toasts.gd"
const ONBOARDING_PATH := "res://src/ui/onboarding.gd"
const BOTTOM_SHEET_PATH := "res://src/ui/bottom_sheet.gd"
const BOTTOM_NAV_PATH := "res://src/ui/bottom_nav.gd"
const MOBILE_OVERLAY_PATH := "res://src/ui/mobile_overlay.gd"

const MARGIN := 8.0
const TOP_H := 56.0				# DESKTOP top-bar strip height
const TOP_H_MOBILE := 112.0		# MOBILE two-row top bar
const LEFT_W := 372.0
const RIGHT_W := 436.0
const COACH_CLEAR := 64.0		# rush-order bar sits this far below the coach anchor
const NAV_H := 64.0				# MOBILE bottom nav bar

var _root: Control
var _tooltip = null
var _coach = null
var _targets = null				# OnboardTargets registry shared by the panels
var _top_bar = null
var _orders = null
var _stations = null
var _station_slot: Control		# DESKTOP home of the station panel (left column)
var _right = null
var _sheet = null
var _nav = null
var _mobile_overlay = null
var _toasts = null
var _onboarding = null

var _mode := -1					# Layout.MODE_*; -1 = not applied yet
var _themes: Dictionary = {}	# font-scale -> Theme cache
var _borrowed_tab := -1			# right-panel tab currently hosted by the mobile overlay
var _relayouting := false


func _ready() -> void:
	layer = 10

	_root = Control.new()
	_root.name = "Root"
	UiUtil.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme_for(1.0)
	add_child(_root)

	# Shared tooltip service (added to the tree last so it draws on top).
	_tooltip = TooltipScript.new()
	# Named-rect registry for the onboarding spotlight. The HUD registers layout-mode
	# aware dispatchers for the targets whose home moves between DESKTOP and MOBILE.
	_targets = OnboardTargets.new()
	_targets.register("world_bottleneck", _world_bottleneck_rect)
	_targets.register("fix_button", _target_fix_button)
	_targets.register("bottleneck_card", _target_bottleneck_card)
	_targets.register("skills_tab", _target_skills_tab)

	_top_bar = _make(TOP_BAR_PATH)
	_top_bar.setup(_tooltip, _targets)
	_root.add_child(_top_bar)

	_coach = _make(COACH_PATH)
	_coach.setup(_targets)
	_root.add_child(_coach)

	_orders = _make(ORDER_WIDGET_PATH)
	_root.add_child(_orders)

	# The production line list. Its DESKTOP home is a left-column slot; in MOBILE the
	# panel is reparented into the bottom sheet's expanded list slot.
	_station_slot = Control.new()
	_station_slot.name = "StationSlot"
	_station_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_station_slot)
	_stations = _make(STATION_PANEL_PATH)
	_stations.setup(_tooltip, _targets)
	_station_slot.add_child(_stations)
	UiUtil.full_rect(_stations)

	# Overlay layer for modal popups (offline report, save export/import).
	var overlay := Control.new()
	overlay.name = "Overlay"
	UiUtil.full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_right = _make(RIGHT_PANEL_PATH)
	_right.setup(_tooltip, overlay, _targets)
	_root.add_child(_right)

	# MOBILE chrome (hidden in DESKTOP): bottom sheet + bottom nav + full-screen tab host.
	_sheet = _make(BOTTOM_SHEET_PATH)
	_sheet.visible = false
	if _sheet.has_signal("sheet_toggled"):
		_sheet.sheet_toggled.connect(_on_sheet_toggled)
	_root.add_child(_sheet)
	_nav = _make(BOTTOM_NAV_PATH)
	_nav.visible = false
	if _nav.has_signal("tab_selected"):
		_nav.tab_selected.connect(_on_nav_tab)
	_root.add_child(_nav)
	_mobile_overlay = _make(MOBILE_OVERLAY_PATH)
	if _mobile_overlay.has_signal("closed"):
		_mobile_overlay.closed.connect(_on_mobile_overlay_closed)
	_root.add_child(_mobile_overlay)

	_root.add_child(overlay)
	var offline = _make(OFFLINE_POPUP_PATH)
	overlay.add_child(offline)

	# Toasts above modals so "save failed" stays visible; onboarding dim above those;
	# tooltip on the very top (it suppresses itself while the dim is up).
	_toasts = _make(TOASTS_PATH)
	_root.add_child(_toasts)
	_onboarding = _make(ONBOARDING_PATH)
	_onboarding.setup(_targets)
	if _onboarding.has_signal("active_changed"):
		_onboarding.active_changed.connect(_on_onboarding_active)
	_root.add_child(_onboarding)
	_root.add_child(_tooltip)

	get_viewport().size_changed.connect(_relayout)
	_relayout()


# ---------------------------------------------------------------- responsive layout

## One theme per font scale, built lazily (MOBILE bumps every themed font size ~1.15×).
func _theme_for(font_scale: float) -> Theme:
	if not _themes.has(font_scale):
		_themes[font_scale] = UiTheme.build(font_scale)
	return _themes[font_scale]


## The responsive heart: called on ready and on every viewport size change. Sets the
## orientation-aware content scale, resolves the layout mode, re-places everything.
func _relayout() -> void:
	if _relayouting:
		return	# content_scale_size writes re-fire size_changed synchronously
	_relayouting = true
	var win := get_window()
	if win != null:
		var win_size := Vector2(win.size)
		var want_scale := Layout.scale_size_for(win_size)
		if win.content_scale_size != want_scale:
			win.content_scale_size = want_scale
		var mode := Layout.resolve_mode(win_size)
		if mode != _mode:
			_mode = mode
			_apply_mode(mode)
		_place_all()
	_relayouting = false


## Mode-switch housekeeping: theme scale, panel broadcasts, reparenting, chrome visibility.
func _apply_mode(mode: int) -> void:
	var mobile := mode == Layout.MODE_MOBILE
	_root.theme = _theme_for(UiTheme.MOBILE_FONT_SCALE if mobile else 1.0)

	if not mobile and _mobile_overlay != null and _mobile_overlay.visible:
		_mobile_overlay.close()	# returns the borrowed tab via the closed signal

	for panel in [_top_bar, _coach, _orders, _toasts, _tooltip]:
		if panel != null and panel.has_method("set_layout_mode"):
			panel.set_layout_mode(mode)

	if _stations.has_method("set_external_fix"):
		_stations.set_external_fix(mobile)	# the sheet pins the one FIX IT in MOBILE
	if mobile:
		_sheet.attach_station_list(_stations)
	else:
		_sheet.detach_station_list(_stations)
		if _stations.get_parent() != _station_slot:
			if _stations.get_parent() != null:
				_stations.get_parent().remove_child(_stations)
			_station_slot.add_child(_stations)
		UiUtil.full_rect(_stations)

	_station_slot.visible = not mobile
	_right.visible = not mobile
	_sheet.visible = mobile
	_nav.visible = mobile
	if _nav.has_method("set_active"):
		_nav.set_active(_borrowed_tab if mobile else -1)
	if _onboarding != null and _onboarding.has_method("relayout"):
		_onboarding.relayout()


## Idempotent placement pass for the current mode (also re-run when the sheet toggles).
func _place_all() -> void:
	var design := _design_size()
	if _mode == Layout.MODE_MOBILE:
		_place(_top_bar, 0.0, 0.0, 1.0, 0.0, MARGIN, MARGIN, -MARGIN, MARGIN + TOP_H_MOBILE)
		var content_top := MARGIN + TOP_H_MOBILE + 8.0
		_place(_coach, 0.0, 0.0, 1.0, 0.0, MARGIN, content_top, -MARGIN, content_top)
		_place(_orders, 0.0, 0.0, 1.0, 0.0, MARGIN, content_top + COACH_CLEAR, -MARGIN, content_top + COACH_CLEAR)
		_place(_nav, 0.0, 1.0, 1.0, 1.0, 0.0, -NAV_H, 0.0, 0.0)
		var sheet_h: float = _sheet.current_height(design.y)
		_place(_sheet, 0.0, 1.0, 1.0, 1.0, MARGIN, -NAV_H - 4.0 - sheet_h, -MARGIN, -NAV_H - 4.0)
		if _toasts.has_method("set_bottom_clearance"):
			_toasts.set_bottom_clearance(NAV_H + 4.0 + sheet_h + 10.0)
	else:
		_place(_top_bar, 0.0, 0.0, 1.0, 0.0, MARGIN, MARGIN, -MARGIN, MARGIN + TOP_H)
		var content_top := MARGIN + TOP_H + 8.0
		_place(_coach, 0.5, 0.0, 0.5, 0.0, 0.0, content_top, 0.0, content_top)
		_place(_orders, 0.5, 0.0, 0.5, 0.0, 0.0, content_top + COACH_CLEAR, 0.0, content_top + COACH_CLEAR)
		_place(_station_slot, 0.0, 0.0, 0.0, 1.0, MARGIN, content_top, MARGIN + LEFT_W, -MARGIN)
		_place(_right, 1.0, 0.0, 1.0, 1.0, -MARGIN - RIGHT_W, content_top, -MARGIN, -MARGIN)


func _design_size() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		return vp.get_visible_rect().size
	return Vector2(1280, 720)


func _on_sheet_toggled(_expanded: bool) -> void:
	_place_all()
	if _onboarding != null and _onboarding.has_method("relayout"):
		_onboarding.relayout()


# ---------------------------------------------------------------- mobile tab overlay

func _on_nav_tab(i: int) -> void:
	if _mobile_overlay == null or _right == null or not _right.has_method("borrow_panel"):
		return
	if _borrowed_tab == i and _mobile_overlay.visible:
		_mobile_overlay.close()	# tapping the open tab again closes it
		return
	if _mobile_overlay.visible:
		_return_borrowed()
	var panel: Control = _right.borrow_panel(i)
	if panel == null:
		return
	_borrowed_tab = i
	_mobile_overlay.open(panel, str(_right.tab_title(i)))
	if _nav.has_method("set_active"):
		_nav.set_active(i)


func _on_mobile_overlay_closed() -> void:
	_return_borrowed()
	if _nav != null and _nav.has_method("set_active"):
		_nav.set_active(-1)


func _return_borrowed() -> void:
	if _borrowed_tab >= 0 and _right != null and _right.has_method("return_panel"):
		_right.return_panel(_borrowed_tab)
	_borrowed_tab = -1


# ---------------------------------------------------------------- onboarding plumbing

## While the onboarding dim is up: no coach hints, no tooltips above the dim.
func _on_onboarding_active(active: bool) -> void:
	if _coach != null and _coach.has_method("set_suppressed"):
		_coach.set_suppressed(active)
	if _tooltip != null and _tooltip.has_method("set_suppressed"):
		_tooltip.set_suppressed(active)


## Onboarding target for "world_bottleneck": a box in the visible 3D area — between the
## side panels on DESKTOP, between the top strips and the bottom sheet on MOBILE.
func _world_bottleneck_rect() -> Rect2:
	if _root == null:
		return Rect2()
	var sz := _design_size()
	var left_edge := MARGIN + LEFT_W + 24.0
	var right_edge := sz.x - MARGIN - RIGHT_W - 24.0
	var top_edge := MARGIN + TOP_H + 48.0
	var bottom_edge := sz.y * 0.72
	if _mode == Layout.MODE_MOBILE and _sheet != null:
		left_edge = MARGIN + 16.0
		right_edge = sz.x - MARGIN - 16.0
		top_edge = MARGIN + TOP_H_MOBILE + 8.0 + COACH_CLEAR + 70.0
		bottom_edge = sz.y - NAV_H - 4.0 - float(_sheet.current_height(sz.y)) - 16.0
	if right_edge <= left_edge or bottom_edge <= top_edge:
		return Rect2()
	var center := Vector2((left_edge + right_edge) * 0.5, (top_edge + bottom_edge) * 0.5)
	var box := Vector2(minf(340.0, right_edge - left_edge), minf(240.0, bottom_edge - top_edge))
	return Rect2(center - box * 0.5, box)


## MOBILE: the sheet's persistent FIX IT; DESKTOP: the promoted card's FIX IT.
func _target_fix_button() -> Rect2:
	if _mode == Layout.MODE_MOBILE and _sheet != null and _sheet.has_method("fix_button_rect"):
		return _sheet.fix_button_rect()
	if _stations != null and _stations.has_method("fix_button_rect"):
		return _stations.fix_button_rect()
	return Rect2()


## MOBILE: the promoted card when the sheet list shows it, else the collapsed summary.
func _target_bottleneck_card() -> Rect2:
	if _mode == Layout.MODE_MOBILE:
		var r: Rect2 = Rect2()
		if _stations != null and _stations.has_method("bottleneck_card_rect"):
			r = _stations.bottleneck_card_rect()
		if r.size.x <= 0.0 and _sheet != null and _sheet.has_method("summary_rect"):
			r = _sheet.summary_rect()
		return r
	if _stations != null and _stations.has_method("bottleneck_card_rect"):
		return _stations.bottleneck_card_rect()
	return Rect2()


## MOBILE: the bottom-nav Skills button; DESKTOP: the right panel's Skills tab.
func _target_skills_tab() -> Rect2:
	if _mode == Layout.MODE_MOBILE and _nav != null and _nav.has_method("skills_rect"):
		return _nav.skills_rect()
	if _right != null and _right.has_method("skills_tab_rect"):
		return _right.skills_tab_rect()
	return Rect2()


# ---------------------------------------------------------------- helpers

## Explicit anchor+offset placement (see UiUtil.anchor_box: set_anchors_preset silently
## rewrites offsets to preserve the pre-call rect, so presets are never used in-tree).
func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	UiUtil.anchor_box(c, al, at, ar, ab, ol, ot, orr, ob)


## Instantiate one of this module's panel scripts by path (see note on the *_PATH consts).
func _make(path: String) -> Control:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		push_error("HUD: cannot load %s" % path)
		return Control.new()
	var node: Variant = script.new()
	return node as Control
