## UiTheme — the single dark-industrial Theme resource for the HUD, built entirely in code.
## Palette pinned in docs/ARCHITECTURE.md §14; only visual constants live here.
## Preload via: const UiTheme = preload("res://src/ui/ui_theme.gd")
extends RefCounted

# ---- Palette (§14) ----
const COL_BG := Color("#17191D")
const COL_PANEL := Color("#1E2126")
const COL_PANEL_2 := Color("#1B1E22")
const COL_CARD := Color("#22252B")
const COL_INPUT := Color("#121418")
const COL_BTN := Color("#2A2E35")
const COL_BTN_HOVER := Color("#333842")
const COL_BTN_PRESS := Color("#1E2126")
const COL_BORDER := Color("#2E3238")
const COL_BORDER_LIGHT := Color("#3A404A")
const COL_TEXT := Color("#E8EAED")
const COL_TEXT_DIM := Color("#9AA0A6")
const COL_TEXT_DISABLED := Color("#6E747C")
const COL_AMBER := Color("#F4B942")
const COL_AMBER_BG := Color("#2C2820")
const COL_GREEN := Color("#3FA34D")
const COL_GREEN_BG := Color("#1F2922")
const COL_RED := Color("#E4572E")
const COL_GREY := Color("#9AA0A6")

# ---- Type scale / metrics ----
const FONT_TINY := 12
const FONT_SMALL := 13
const FONT_BODY := 15
const FONT_TITLE := 16
const FONT_BIG := 21
const TOUCH_MIN := 36.0
const RADIUS := 6


## Rounded StyleBoxFlat helper. border_w 0 = no border.
static func flat(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := RADIUS, margin_h := 10.0, margin_v := 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = true
	return sb


## Amber keyboard-focus outline (draw_center off so it overlays any state box).
static func focus_box(radius := RADIUS) -> StyleBoxFlat:
	var sb := flat(Color(0, 0, 0, 0), COL_AMBER, 2, radius, 0.0, 0.0)
	sb.draw_center = false
	sb.expand_margin_left = 1.0
	sb.expand_margin_right = 1.0
	sb.expand_margin_top = 1.0
	sb.expand_margin_bottom = 1.0
	return sb


static func with_shadow(sb: StyleBoxFlat, size := 8) -> StyleBoxFlat:
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = size
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func bold_font() -> FontVariation:
	var f := FontVariation.new()
	var base: Font = ThemeDB.fallback_font
	if base != null:
		f.base_font = base
	f.variation_embolden = 0.65
	return f


## Build the full HUD theme. Called once by hud.gd and assigned to the root Control.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	var bold := bold_font()

	# ---- Panels ----
	var panel_box := flat(COL_PANEL, COL_BORDER, 1, 8, 10.0, 10.0)
	t.set_stylebox("panel", "PanelContainer", panel_box)
	t.set_stylebox("panel", "Panel", flat(COL_PANEL, COL_BORDER, 1, 8, 0.0, 0.0))

	_panel_variation(t, "TopBarPanel", flat(COL_PANEL_2, COL_BORDER, 1, 8, 14.0, 4.0))
	_panel_variation(t, "CardPanel", flat(COL_CARD, COL_BORDER, 1, 8, 9.0, 8.0))
	_panel_variation(t, "CardPanelSelected", flat(COL_CARD, COL_AMBER, 1, 8, 9.0, 8.0))
	# Simple mode: the current bottleneck's card is promoted (amber edge, a bit taller).
	_panel_variation(t, "CardPanelBottleneck", flat(Color("#26241E"), COL_AMBER, 2, 8, 9.0, 12.0))
	_panel_variation(t, "ChipPanel", flat(COL_CARD, COL_BORDER, 1, 8, 9.0, 4.0))
	_panel_variation(t, "InsetPanel", flat(COL_INPUT, COL_BORDER, 1, RADIUS, 10.0, 8.0))
	_panel_variation(t, "CoachPanel", with_shadow(flat(COL_AMBER_BG, Color(COL_AMBER, 0.85), 1, 8, 12.0, 8.0)))
	_panel_variation(t, "TooltipPanel", with_shadow(flat(Color("#14161A", 0.98), COL_BORDER_LIGHT, 1, RADIUS, 10.0, 8.0), 10))
	_panel_variation(t, "ToastPanel", with_shadow(flat(COL_CARD, COL_BORDER_LIGHT, 1, 8, 12.0, 8.0)))
	_panel_variation(t, "ToastPanelGood", with_shadow(flat(COL_AMBER_BG, COL_AMBER, 1, 8, 12.0, 8.0)))
	_panel_variation(t, "ModalPanel", with_shadow(flat(COL_PANEL, COL_BORDER_LIGHT, 1, 10, 16.0, 14.0), 16))
	# Rush-order widget bar (+ green flash state on completion).
	_panel_variation(t, "OrderPanel", with_shadow(flat(COL_CARD, COL_BORDER_LIGHT, 1, 8, 12.0, 8.0)))
	_panel_variation(t, "OrderPanelGood", with_shadow(flat(COL_GREEN_BG, COL_GREEN, 1, 8, 12.0, 8.0)))

	# ---- Labels ----
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_font_size("font_size", "Label", FONT_BODY)
	_label_variation(t, "TitleLabel", FONT_TITLE, COL_TEXT, bold)
	_label_variation(t, "MoneyLabel", FONT_BIG, COL_TEXT, bold)
	_label_variation(t, "BigValueLabel", 24, COL_AMBER, bold)
	_label_variation(t, "ValueLabel", FONT_BODY, COL_TEXT, bold)
	_label_variation(t, "DimLabel", FONT_SMALL, COL_TEXT_DIM, null)
	_label_variation(t, "TinyLabel", FONT_TINY, COL_TEXT_DIM, null)
	_label_variation(t, "AccentLabel", FONT_BODY, COL_AMBER, bold)
	_label_variation(t, "GoodLabel", FONT_BODY, COL_GREEN, bold)
	_label_variation(t, "BadLabel", FONT_BODY, COL_RED, bold)
	_label_variation(t, "GlyphLabel", FONT_TITLE, COL_TEXT, bold)

	# ---- Buttons ----
	t.set_stylebox("normal", "Button", flat(COL_BTN, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("hover", "Button", flat(COL_BTN_HOVER, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("pressed", "Button", flat(COL_BTN_PRESS, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("hover_pressed", "Button", flat(COL_BTN_PRESS, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("disabled", "Button", flat(Color("#20232A"), COL_BORDER, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("focus", "Button", focus_box())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color("#FFFFFF"))
	t.set_color("font_pressed_color", "Button", COL_TEXT)
	t.set_color("font_hover_pressed_color", "Button", COL_TEXT)
	t.set_color("font_focus_color", "Button", COL_TEXT)
	t.set_color("font_disabled_color", "Button", COL_TEXT_DISABLED)
	t.set_font_size("font_size", "Button", FONT_BODY)

	# Big amber call-to-action.
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", flat(COL_AMBER, Color(0, 0, 0, 0), 0, RADIUS, 14.0, 8.0))
	t.set_stylebox("hover", "AccentButton", flat(Color("#FFCB5C"), Color(0, 0, 0, 0), 0, RADIUS, 14.0, 8.0))
	t.set_stylebox("pressed", "AccentButton", flat(Color("#D9A32F"), Color(0, 0, 0, 0), 0, RADIUS, 14.0, 8.0))
	t.set_stylebox("disabled", "AccentButton", flat(Color("#4A4433"), Color(0, 0, 0, 0), 0, RADIUS, 14.0, 8.0))
	t.set_color("font_color", "AccentButton", Color("#17191D"))
	t.set_color("font_hover_color", "AccentButton", Color("#17191D"))
	t.set_color("font_pressed_color", "AccentButton", Color("#17191D"))
	t.set_color("font_focus_color", "AccentButton", Color("#17191D"))
	t.set_color("font_disabled_color", "AccentButton", Color("#8A8578"))
	t.set_font("font", "AccentButton", bold)

	# Simple mode's big FIX IT call-to-action (amber, two-line capable).
	t.set_type_variation("FixButton", "AccentButton")
	t.set_font_size("font_size", "FixButton", 17)

	# Low-key text button (mode toggle): transparent until hovered.
	t.set_type_variation("GhostButton", "Button")
	t.set_font_size("font_size", "GhostButton", FONT_SMALL)
	t.set_stylebox("normal", "GhostButton", flat(Color(0, 0, 0, 0), COL_BORDER, 1, RADIUS, 10.0, 4.0))
	t.set_stylebox("hover", "GhostButton", flat(COL_BTN_HOVER, COL_BORDER_LIGHT, 1, RADIUS, 10.0, 4.0))
	t.set_stylebox("pressed", "GhostButton", flat(COL_BTN_PRESS, COL_BORDER_LIGHT, 1, RADIUS, 10.0, 4.0))
	t.set_color("font_color", "GhostButton", COL_TEXT_DIM)
	t.set_color("font_hover_color", "GhostButton", COL_TEXT)

	# Tab strip buttons (toggle_mode; "pressed" = active tab, amber underline).
	var tab_off := flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, RADIUS, 12.0, 8.0)
	var tab_hover := flat(Color(COL_BTN, 0.6), Color(0, 0, 0, 0), 0, RADIUS, 12.0, 8.0)
	var tab_on := flat(COL_CARD, COL_AMBER, 0, RADIUS, 12.0, 8.0)
	tab_on.border_width_bottom = 2
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", tab_off)
	t.set_stylebox("hover", "TabButton", tab_hover)
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_color("font_color", "TabButton", COL_TEXT_DIM)
	t.set_color("font_pressed_color", "TabButton", COL_TEXT)
	t.set_color("font_hover_pressed_color", "TabButton", COL_TEXT)
	t.set_type_variation("TabButtonAlert", "TabButton")
	t.set_color("font_color", "TabButtonAlert", COL_AMBER)
	t.set_color("font_hover_color", "TabButtonAlert", COL_AMBER)

	# Buy-multiplier segment buttons (small toggles).
	t.set_type_variation("MultButton", "TabButton")
	t.set_font_size("font_size", "MultButton", FONT_SMALL)

	# Station upgrade buttons (two-line: name+level / cost).
	t.set_type_variation("UpgradeButton", "Button")
	t.set_font_size("font_size", "UpgradeButton", FONT_SMALL)
	t.set_stylebox("normal", "UpgradeButton", flat(COL_BTN, COL_BORDER_LIGHT, 1, RADIUS, 9.0, 5.0))
	t.set_stylebox("hover", "UpgradeButton", flat(COL_BTN_HOVER, COL_BORDER_LIGHT, 1, RADIUS, 9.0, 5.0))
	t.set_stylebox("pressed", "UpgradeButton", flat(COL_BTN_PRESS, COL_BORDER_LIGHT, 1, RADIUS, 9.0, 5.0))
	t.set_stylebox("disabled", "UpgradeButton", flat(Color("#20232A"), COL_BORDER, 1, RADIUS, 9.0, 5.0))
	# The "this helps the bottleneck and you can afford it" glow (pillar #1).
	t.set_type_variation("UpgradeButtonHot", "UpgradeButton")
	t.set_stylebox("normal", "UpgradeButtonHot", flat(COL_AMBER_BG, COL_AMBER, 1, RADIUS, 9.0, 5.0))
	t.set_stylebox("hover", "UpgradeButtonHot", flat(Color("#363023"), COL_AMBER, 1, RADIUS, 9.0, 5.0))
	t.set_stylebox("pressed", "UpgradeButtonHot", flat(COL_BTN_PRESS, COL_AMBER, 1, RADIUS, 9.0, 5.0))
	t.set_color("font_color", "UpgradeButtonHot", Color("#FFE1A1"))

	# Skill tree nodes.
	t.set_type_variation("SkillNode", "Button")
	t.set_font_size("font_size", "SkillNode", FONT_TINY)
	t.set_stylebox("normal", "SkillNode", flat(COL_BTN, COL_BORDER_LIGHT, 1, RADIUS, 6.0, 4.0))
	t.set_stylebox("hover", "SkillNode", flat(COL_BTN_HOVER, COL_BORDER_LIGHT, 1, RADIUS, 6.0, 4.0))
	t.set_stylebox("pressed", "SkillNode", flat(COL_BTN_PRESS, COL_BORDER_LIGHT, 1, RADIUS, 6.0, 4.0))
	t.set_type_variation("SkillNodeOwned", "SkillNode")
	t.set_stylebox("normal", "SkillNodeOwned", flat(COL_GREEN_BG, COL_GREEN, 1, RADIUS, 6.0, 4.0))
	t.set_stylebox("hover", "SkillNodeOwned", flat(COL_GREEN_BG, COL_GREEN, 1, RADIUS, 6.0, 4.0))
	t.set_stylebox("pressed", "SkillNodeOwned", flat(COL_GREEN_BG, COL_GREEN, 1, RADIUS, 6.0, 4.0))
	t.set_type_variation("SkillNodeReady", "SkillNode")
	t.set_stylebox("normal", "SkillNodeReady", flat(COL_AMBER_BG, COL_AMBER, 1, RADIUS, 6.0, 4.0))
	t.set_stylebox("hover", "SkillNodeReady", flat(Color("#363023"), COL_AMBER, 1, RADIUS, 6.0, 4.0))
	t.set_color("font_color", "SkillNodeReady", Color("#FFE1A1"))
	t.set_type_variation("SkillNodeLocked", "SkillNode")
	t.set_stylebox("normal", "SkillNodeLocked", flat(COL_PANEL_2, COL_BORDER, 1, RADIUS, 6.0, 4.0))
	t.set_stylebox("hover", "SkillNodeLocked", flat(COL_PANEL_2, COL_BORDER, 1, RADIUS, 6.0, 4.0))
	t.set_color("font_color", "SkillNodeLocked", COL_TEXT_DISABLED)

	# Small flat close ("×") buttons.
	t.set_type_variation("CloseButton", "Button")
	t.set_stylebox("normal", "CloseButton", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, RADIUS, 6.0, 2.0))
	t.set_stylebox("hover", "CloseButton", flat(COL_BTN_HOVER, Color(0, 0, 0, 0), 0, RADIUS, 6.0, 2.0))
	t.set_stylebox("pressed", "CloseButton", flat(COL_BTN_PRESS, Color(0, 0, 0, 0), 0, RADIUS, 6.0, 2.0))
	t.set_color("font_color", "CloseButton", COL_TEXT_DIM)

	# ---- CheckButton / OptionButton ----
	t.set_color("font_color", "CheckButton", COL_TEXT)
	t.set_color("font_hover_color", "CheckButton", Color("#FFFFFF"))
	t.set_stylebox("focus", "CheckButton", focus_box())
	t.set_stylebox("normal", "CheckButton", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, RADIUS, 4.0, 4.0))
	t.set_stylebox("normal", "OptionButton", flat(COL_BTN, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("hover", "OptionButton", flat(COL_BTN_HOVER, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("pressed", "OptionButton", flat(COL_BTN_PRESS, COL_BORDER_LIGHT, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("disabled", "OptionButton", flat(Color("#20232A"), COL_BORDER, 1, RADIUS, 12.0, 6.0))
	t.set_stylebox("focus", "OptionButton", focus_box())
	t.set_color("font_color", "OptionButton", COL_TEXT)
	t.set_color("font_hover_color", "OptionButton", Color("#FFFFFF"))

	# ---- PopupMenu (OptionButton dropdown) ----
	t.set_stylebox("panel", "PopupMenu", with_shadow(flat(COL_PANEL_2, COL_BORDER_LIGHT, 1, RADIUS, 4.0, 4.0)))
	t.set_stylebox("hover", "PopupMenu", flat(COL_BTN_HOVER, Color(0, 0, 0, 0), 0, 4, 6.0, 4.0))
	t.set_color("font_color", "PopupMenu", COL_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color("#FFFFFF"))

	# ---- Sliders ----
	var groove := flat(COL_INPUT, COL_BORDER, 1, 3, 0.0, 2.0)
	var groove_fill := flat(COL_AMBER, Color(0, 0, 0, 0), 0, 3, 0.0, 2.0)
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", groove_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", groove_fill)

	# ---- ProgressBar ----
	t.set_stylebox("background", "ProgressBar", flat(COL_INPUT, COL_BORDER, 1, 3, 2.0, 2.0))
	t.set_stylebox("fill", "ProgressBar", flat(COL_AMBER, Color(0, 0, 0, 0), 0, 3, 0.0, 0.0))
	t.set_color("font_color", "ProgressBar", COL_TEXT)
	t.set_font_size("font_size", "ProgressBar", FONT_TINY)

	# ---- LineEdit / TextEdit ----
	for edit_type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", edit_type, flat(COL_INPUT, COL_BORDER, 1, RADIUS, 8.0, 6.0))
		t.set_stylebox("focus", edit_type, flat(COL_INPUT, COL_AMBER, 1, RADIUS, 8.0, 6.0))
		t.set_color("font_color", edit_type, COL_TEXT)
		t.set_color("caret_color", edit_type, COL_AMBER)
		t.set_color("selection_color", edit_type, Color(COL_AMBER, 0.35))
		t.set_color("font_placeholder_color", edit_type, COL_TEXT_DISABLED)

	# ---- Scrollbars ----
	for bar_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar_type, flat(Color(COL_INPUT, 0.6), Color(0, 0, 0, 0), 0, 3, 0.0, 0.0))
		t.set_stylebox("grabber", bar_type, flat(COL_BORDER_LIGHT, Color(0, 0, 0, 0), 0, 3, 0.0, 0.0))
		t.set_stylebox("grabber_highlight", bar_type, flat(Color("#4A515C"), Color(0, 0, 0, 0), 0, 3, 0.0, 0.0))
		t.set_stylebox("grabber_pressed", bar_type, flat(COL_AMBER, Color(0, 0, 0, 0), 0, 3, 0.0, 0.0))

	# ---- Separators / containers ----
	var sep_line := StyleBoxLine.new()
	sep_line.color = COL_BORDER
	sep_line.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep_line)
	var vsep_line := StyleBoxLine.new()
	vsep_line.color = COL_BORDER
	vsep_line.thickness = 1
	vsep_line.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep_line)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("h_separation", "GridContainer", 6)
	t.set_constant("v_separation", "GridContainer", 6)

	# ScrollContainer background stays transparent (panels provide their own).
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", empty)

	return t


static func _panel_variation(t: Theme, variation: String, sb: StyleBox) -> void:
	t.set_type_variation(variation, "PanelContainer")
	t.set_stylebox("panel", variation, sb)


static func _label_variation(t: Theme, variation: String, size: int, color: Color, font: Font) -> void:
	t.set_type_variation(variation, "Label")
	t.set_font_size("font_size", variation, size)
	t.set_color("font_color", variation, color)
	if font != null:
		t.set_font("font", variation, font)
