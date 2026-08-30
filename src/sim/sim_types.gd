## SimTypes — shared simulation constants. Pure data, safe to preload anywhere.
## Reference via: const SimTypes = preload("res://src/sim/sim_types.gd")
extends RefCounted

# Station status (station view "status" field).
const STATUS_IDLE := 0
const STATUS_RUNNING := 1
const STATUS_STARVED := 2
const STATUS_BLOCKED := 3

# Camera modes (EventBus.camera_mode_changed).
const CAMERA_ORBIT := 0
const CAMERA_WALK := 1

# Buy multiplier sentinel for "max affordable".
const BUY_MAX := -1

# Fixed simulation timestep in seconds (10 Hz).
const TICK_DT := 0.1
