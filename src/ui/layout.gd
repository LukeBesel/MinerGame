## Layout — pure responsive-layout helpers for the HUD: portrait detection, the
## orientation-aware content-scale base, effective design-space math (stretch
## canvas_items + expand) and DESKTOP/MOBILE mode resolution. Statics only, no autoloads,
## hermetically testable. No class_name (ARCHITECTURE §2).
extends RefCounted

const MODE_DESKTOP := 0
const MODE_MOBILE := 1

const PORTRAIT_ASPECT_MAX := 1.05		# window w/h below this = portrait
const MOBILE_MAX_DESIGN_W := 1000.0		# design-space width below this = MOBILE even in landscape
const SCALE_LANDSCAPE := Vector2i(1280, 720)
const SCALE_PORTRAIT := Vector2i(720, 1280)


## True when the physical window is portrait-ish (aspect < 1.05).
static func is_portrait(win: Vector2) -> bool:
	if win.x <= 0.0 or win.y <= 0.0:
		return false
	return (win.x / win.y) < PORTRAIT_ASPECT_MAX


## The content_scale_size base for a physical window size: rotating the 1280×720 design
## base to 720×1280 in portrait makes the UI ~1.4× larger instead of 0.77× smaller.
static func scale_size_for(win: Vector2) -> Vector2i:
	return SCALE_PORTRAIT if is_portrait(win) else SCALE_LANDSCAPE


## Effective design-space (viewport) size produced by stretch mode canvas_items with
## aspect "expand" for a physical window and a content-scale base: one axis equals the
## base, the other expands to match the window aspect.
static func design_size(win: Vector2, base: Vector2) -> Vector2:
	if win.x <= 0.0 or win.y <= 0.0 or base.x <= 0.0 or base.y <= 0.0:
		return base
	var win_aspect := win.x / win.y
	var base_aspect := base.x / base.y
	if win_aspect > base_aspect:
		return Vector2(base.y * win_aspect, base.y)
	return Vector2(base.x, base.x / win_aspect)


## DESKTOP / MOBILE from the physical window size (assuming scale_size_for is applied):
## MOBILE = portrait OR the effective design-space width < 1000.
static func resolve_mode(win: Vector2) -> int:
	if is_portrait(win):
		return MODE_MOBILE
	var design := design_size(win, Vector2(scale_size_for(win)))
	if design.x < MOBILE_MAX_DESIGN_W:
		return MODE_MOBILE
	return MODE_DESKTOP
