## TestCase base — minimal assertion collector for headless tests.
## Extend with: extends "res://tests/test_framework.gd" and write methods named test_*.
## Tests are synchronous; a fresh instance is created per test method.
extends RefCounted

var _failures: Array[String] = []
var _assert_count: int = 0


func assert_true(cond: bool, msg: String = "") -> void:
	_assert_count += 1
	if not cond:
		_failures.append(_msg("assert_true failed", msg))


func assert_false(cond: bool, msg: String = "") -> void:
	_assert_count += 1
	if cond:
		_failures.append(_msg("assert_false failed", msg))


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	_assert_count += 1
	if not _loose_eq(a, b):
		_failures.append(_msg("expected `%s` got `%s`" % [str(b), str(a)], msg))


func assert_near(a: float, b: float, eps: float = 1e-6, msg: String = "") -> void:
	_assert_count += 1
	if absf(a - b) > eps:
		_failures.append(_msg("expected %s ~= %s (eps %s)" % [str(a), str(b), str(eps)], msg))


func fail(msg: String) -> void:
	_assert_count += 1
	_failures.append(msg)


func _loose_eq(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return absf(float(a) - float(b)) < 1e-9
	return a == b


func _msg(base: String, msg: String) -> String:
	return base + (" — " + msg if msg != "" else "")
