## EventBus — global signal hub decoupling simulation, world, UI, audio, and juice.
## One-way notifications only: systems emit facts here; commands go through Game methods.
## The signal registry is pinned in docs/ARCHITECTURE.md §5 — do not rename or remove.
extends Node

# 10 Hz simulation snapshot (see ARCHITECTURE.md §6 for the dictionary shape).
signal sim_stats(stats: Dictionary)

# Simulation transitions (BigNum-valued params are intentionally untyped).
signal part_completed(station: int)
signal part_sold(count: float, revenue)
signal scrap_produced(station: int, amount: float)
signal bottleneck_changed(new_index: int, old_index: int)
signal bottleneck_cleared(station: int)
signal station_status_changed(station: int, status: int)
signal station_upgraded(station: int, upgrade_id: String, levels: int, new_level: int)
signal station_unlocked(station: int)
signal money_spent(amount, context: String)
signal milestone_reached(id: String, kp_gained: int)
signal kaizen_points_changed(total: float)
signal skill_purchased(node_id: String)
signal prestige_performed(cip_gained: int, new_multiplier: float)
signal offline_report(report: Dictionary)

# Interaction / UI.
signal station_selected(station: int)
signal buy_multiplier_changed(mult: int)
signal coach_hint(text: String)
signal camera_mode_changed(mode: int)
signal request_toast(text: String)

# Meta.
signal achievement_unlocked(id: String)
signal save_completed(slot: String)
signal save_failed(reason: String)
signal load_completed()
signal settings_changed(key: String, value: Variant)
signal game_reset()
