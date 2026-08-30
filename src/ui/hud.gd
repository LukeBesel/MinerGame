## HUD — root CanvasLayer for the whole 2D interface. Builds the entire control tree in
## code (no other scenes): top bar, coach/Andon board, rush-order bar, production-line
## list (left), tabbed side panel (right), toasts, offline popup, first-run onboarding
## overlay, and the shared tooltip layer. Renders from EventBus.sim_stats; commands go
## through Game (guards in each panel).
extends CanvasLayer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
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

const MARGIN := 8.0
const TOP_H := 56.0
const LEFT_W := 372.0
const RIGHT_W := 436.0
const COACH_CLEAR := 64.0		# rush-order bar sits this far below the coach anchor

var _root: Control
var _tooltip = null
var _coach = null
var _targets = null				# OnboardTargets registry shared by the panels


func _ready() -> void:
	layer = 10

	_root = Control.new()
	_root.name = "Root"
	UiUtil.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)

	# Shared tooltip service (added to the tree last so it draws on top).
	_tooltip = TooltipScript.new()
	# Named-rect registry for the onboarding spotlight; panels register their own targets,
	# the HUD itself provides the 3D gap between the panels.
	_targets = OnboardTargets.new()
	_targets.register("world_bottleneck", _world_bottleneck_rect)

	# Top bar.
	var top_bar = _make(TOP_BAR_PATH)
	top_bar.setup(_tooltip, _targets)
	_root.add_child(top_bar)
	_place(top_bar, 0.0, 0.0, 1.0, 0.0, MARGIN, MARGIN, -MARGIN, MARGIN + TOP_H)

	var content_top := MARGIN + TOP_H + 8.0

	# Coach / Andon board, centered under the top bar (it centers its own panel on x).
	_coach = _make(COACH_PATH)
	_coach.setup(_targets)
	_root.add_child(_coach)
	_place(_coach, 0.5, 0.0, 0.5, 0.0, 0.0, content_top, 0.0, content_top)

	# Rush-order bar, under the coach (also centers its own panel on x).
	var orders = _make(ORDER_WIDGET_PATH)
	_root.add_child(orders)
	_place(orders, 0.5, 0.0, 0.5, 0.0, 0.0, content_top + COACH_CLEAR, 0.0, content_top + COACH_CLEAR)

	# Left: the production line.
	var stations = _make(STATION_PANEL_PATH)
	stations.setup(_tooltip, _targets)
	_root.add_child(stations)
	_place(stations, 0.0, 0.0, 0.0, 1.0, MARGIN, content_top, MARGIN + LEFT_W, -MARGIN)

	# Overlay layer for modal popups (offline report, save export/import).
	var overlay := Control.new()
	overlay.name = "Overlay"
	UiUtil.full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Right: tabbed panel (needs the overlay for the settings save-modal).
	var right = _make(RIGHT_PANEL_PATH)
	right.setup(_tooltip, overlay, _targets)
	_root.add_child(right)
	_place(right, 1.0, 0.0, 1.0, 1.0, -MARGIN - RIGHT_W, content_top, -MARGIN, -MARGIN)

	_root.add_child(overlay)
	var offline = _make(OFFLINE_POPUP_PATH)
	overlay.add_child(offline)

	# Toasts above modals so "save failed" stays visible; onboarding dim above those;
	# tooltip on the very top (it suppresses itself while the dim is up).
	var toasts = _make(TOASTS_PATH)
	_root.add_child(toasts)
	var onboarding = _make(ONBOARDING_PATH)
	onboarding.setup(_targets)
	if onboarding.has_signal("active_changed"):
		onboarding.active_changed.connect(_on_onboarding_active)
	_root.add_child(onboarding)
	_root.add_child(_tooltip)


## While the onboarding dim is up: no coach hints, no tooltips above the dim.
func _on_onboarding_active(active: bool) -> void:
	if _coach != null and _coach.has_method("set_suppressed"):
		_coach.set_suppressed(active)
	if _tooltip != null and _tooltip.has_method("set_suppressed"):
		_tooltip.set_suppressed(active)


## Onboarding target for "world_bottleneck": a box centered in the 3D gap between the
## left/right panels, below the top bar (where the factory line is visible).
func _world_bottleneck_rect() -> Rect2:
	if _root == null:
		return Rect2()
	var sz := _root.size
	var left_edge := MARGIN + LEFT_W + 24.0
	var right_edge := sz.x - MARGIN - RIGHT_W - 24.0
	var top_edge := MARGIN + TOP_H + 48.0
	var bottom_edge := sz.y * 0.72
	if right_edge <= left_edge or bottom_edge <= top_edge:
		return Rect2()
	var center := Vector2((left_edge + right_edge) * 0.5, (top_edge + bottom_edge) * 0.5)
	var box := Vector2(minf(340.0, right_edge - left_edge), minf(240.0, bottom_edge - top_edge))
	return Rect2(center - box * 0.5, box)


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
