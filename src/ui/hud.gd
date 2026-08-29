## HUD — root CanvasLayer for the whole 2D interface. Builds the entire control tree in
## code (no other scenes): top bar, coach/Andon board, production-line list (left),
## tabbed side panel (right), toasts, offline popup, and the shared tooltip layer.
## Renders from EventBus.sim_stats; commands go through Game (guards in each panel).
extends CanvasLayer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

# Panel scripts are loaded at runtime (not preload): hud.gd itself references no autoloads,
# so under --check-only Godot would fully compile preloaded dependencies and report their
# (filtered-elsewhere) autoload identifiers as a hard "depended scripts" failure.
const TOP_BAR_PATH := "res://src/ui/top_bar.gd"
const COACH_PATH := "res://src/ui/coach.gd"
const STATION_PANEL_PATH := "res://src/ui/station_panel.gd"
const RIGHT_PANEL_PATH := "res://src/ui/right_panel.gd"
const OFFLINE_POPUP_PATH := "res://src/ui/offline_popup.gd"
const TOASTS_PATH := "res://src/ui/toasts.gd"

const MARGIN := 8.0
const TOP_H := 56.0
const LEFT_W := 372.0
const RIGHT_W := 436.0

var _root: Control
var _tooltip = null


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

	# Top bar.
	var top_bar = _make(TOP_BAR_PATH)
	top_bar.setup(_tooltip)
	_root.add_child(top_bar)
	_place(top_bar, 0.0, 0.0, 1.0, 0.0, MARGIN, MARGIN, -MARGIN, MARGIN + TOP_H)

	var content_top := MARGIN + TOP_H + 8.0

	# Coach / Andon board, centered under the top bar (it centers its own panel on x).
	var coach = _make(COACH_PATH)
	_root.add_child(coach)
	_place(coach, 0.5, 0.0, 0.5, 0.0, 0.0, content_top, 0.0, content_top)

	# Left: the production line.
	var stations = _make(STATION_PANEL_PATH)
	stations.setup(_tooltip)
	_root.add_child(stations)
	_place(stations, 0.0, 0.0, 0.0, 1.0, MARGIN, content_top, MARGIN + LEFT_W, -MARGIN)

	# Overlay layer for modal popups (offline report, save export/import).
	var overlay := Control.new()
	overlay.name = "Overlay"
	UiUtil.full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Right: tabbed panel (needs the overlay for the settings save-modal).
	var right = _make(RIGHT_PANEL_PATH)
	right.setup(_tooltip, overlay)
	_root.add_child(right)
	_place(right, 1.0, 0.0, 1.0, 1.0, -MARGIN - RIGHT_W, content_top, -MARGIN, -MARGIN)

	_root.add_child(overlay)
	var offline = _make(OFFLINE_POPUP_PATH)
	overlay.add_child(offline)

	# Toasts above modals so "save failed" stays visible; tooltip on the very top.
	var toasts = _make(TOASTS_PATH)
	_root.add_child(toasts)
	_root.add_child(_tooltip)


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
