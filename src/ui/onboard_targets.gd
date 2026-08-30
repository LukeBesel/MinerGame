## OnboardTargets — tiny named-rect registry for the onboarding spotlight. Panels register
## a provider Callable per pinned target name (bottleneck_card, fix_button, top_bar_money,
## coach, skills_tab, world_bottleneck); rect() re-resolves lazily so moving targets (the
## promoted bottleneck card) stay tracked. Pure RefCounted: no autoloads, hermetically testable.
extends RefCounted

var _providers: Dictionary = {}		# name -> Callable() -> Rect2 (zero-size = missing)


## Register/replace the provider for one target name. Providers must tolerate being called
## any frame and return Rect2() while their control is hidden or gone.
func register(target_name: String, provider: Callable) -> void:
	if target_name != "" and provider.is_valid():
		_providers[target_name] = provider


func unregister(target_name: String) -> void:
	_providers.erase(target_name)


func has_target(target_name: String) -> bool:
	return _providers.has(target_name)


## Global-space rect for a target; Rect2() (zero size) when unknown/hidden/invalid.
func rect(target_name: String) -> Rect2:
	var p: Variant = _providers.get(target_name)
	if p is Callable:
		var c: Callable = p
		if c.is_valid():
			var r: Variant = c.call()
			if r is Rect2:
				return r
	return Rect2()
