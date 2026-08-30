## Tests for src/sim/big_num.gd — construction, arithmetic, comparison, formatting, serialization.
extends "res://tests/test_framework.gd"

const BigNum = preload("res://src/sim/big_num.gd")


func test_construction_and_normalization() -> void:
	var a = BigNum.from_float(1234.0)
	assert_near(a.m, 1.234, 1e-9, "from_float mantissa")
	assert_eq(a.e, 3, "from_float exponent")
	var b = BigNum.make(123.456, 2)
	assert_near(b.m, 1.23456, 1e-9, "make normalizes mantissa")
	assert_eq(b.e, 4, "make normalizes exponent")
	var c = BigNum.make(0.05, 3)
	assert_near(c.m, 5.0, 1e-9)
	assert_eq(c.e, 1)
	assert_true(BigNum.zero().is_zero())
	assert_true(BigNum.from_float(0.0).is_zero())
	assert_true(BigNum.from_float(NAN).is_zero(), "NaN collapses to zero")


func test_add_and_sub() -> void:
	var a = BigNum.make(5.0, 10).add(BigNum.make(5.0, 10))
	assert_near(a.m, 1.0, 1e-9)
	assert_eq(a.e, 11, "5e10 + 5e10 = 1e11")
	var huge = BigNum.make(1.0, 100)
	var tiny = BigNum.make(9.0, 2)
	assert_true(huge.add(tiny).eq(huge), "tiny value vanishes into huge value")
	var d = BigNum.from_float(5.0).sub(BigNum.from_float(3.0))
	assert_near(d.to_float(), 2.0, 1e-9)
	var neg = BigNum.from_float(3.0).sub(BigNum.from_float(5.0))
	assert_near(neg.to_float(), -2.0, 1e-9, "subtraction can go negative")
	assert_true(BigNum.zero().add(BigNum.from_float(7.0)).eq(BigNum.from_float(7.0)))


func test_mul_and_div() -> void:
	var p = BigNum.make(2.0, 5).mul(BigNum.make(3.0, 7))
	assert_near(p.m, 6.0, 1e-9)
	assert_eq(p.e, 12)
	var q = BigNum.make(2.0, 5).mul(BigNum.make(9.0, 7))
	assert_near(q.m, 1.8, 1e-9)
	assert_eq(q.e, 13, "mantissa overflow renormalizes")
	var r = BigNum.make(6.0, 12).div(BigNum.make(3.0, 7))
	assert_near(r.m, 2.0, 1e-9)
	assert_eq(r.e, 5)
	var s = BigNum.from_float(8.0).mul_f(2.5)
	assert_near(s.to_float(), 20.0, 1e-9)
	assert_true(BigNum.from_float(3.0).mul_f(0.0).is_zero())


func test_compare() -> void:
	assert_true(BigNum.from_float(5.0).lt(BigNum.from_float(6.0)))
	assert_true(BigNum.make(1.0, 10).gt(BigNum.make(9.9, 9)))
	assert_true(BigNum.from_float(5.0).eq(BigNum.from_float(5.0)))
	assert_true(BigNum.from_float(-5.0).lt(BigNum.from_float(2.0)))
	assert_true(BigNum.from_float(-5.0).lt(BigNum.from_float(-2.0)), "-5 < -2")
	assert_true(BigNum.make(-1.0, 10).lt(BigNum.make(-1.0, 5)), "-1e10 < -1e5")
	assert_true(BigNum.zero().lt(BigNum.from_float(1.0)))
	assert_true(BigNum.zero().eq(BigNum.zero()))
	assert_true(BigNum.from_float(3.0).ge(BigNum.from_float(3.0)))


func test_from_pow() -> void:
	# 1.15^100 = 1174313.45...
	var g = BigNum.from_pow(1.15, 100.0)
	assert_eq(g.e, 6, "1.15^100 magnitude")
	assert_near(g.m, 1.17431345, 1e-4, "1.15^100 mantissa")
	var one = BigNum.from_pow(1.07, 0.0)
	assert_near(one.to_float(), 1.0, 1e-9)
	var big = BigNum.from_pow(10.0, 500.0)
	assert_eq(big.e, 500, "exceeds double range fine")


func test_format_suffix() -> void:
	assert_eq(BigNum.zero().format(), "0")
	assert_eq(BigNum.from_float(1.0).format(), "1")
	assert_eq(BigNum.from_float(15.0).format(), "15")
	assert_eq(BigNum.from_float(3.5).format(), "3.5")
	assert_eq(BigNum.from_float(999.0).format(), "999")
	assert_eq(BigNum.from_float(1234.0).format(), "1.23K")
	assert_eq(BigNum.make(4.56, 6).format(), "4.56M")
	assert_eq(BigNum.make(7.89, 9).format(), "7.89B")
	assert_eq(BigNum.make(1.23, 12).format(), "1.23T")
	assert_eq(BigNum.make(1.0, 15).format(), "1aa", "first letter tier at 1e15")
	assert_eq(BigNum.make(2.5, 16).format(), "25aa")
	assert_eq(BigNum.make(1.5, 18).format(), "1.5ab")
	assert_eq(BigNum.from_float(-1234.0).format(), "-1.23K")


func test_format_scientific() -> void:
	assert_eq(BigNum.make(1.23, 45).format("scientific"), "1.23e45")
	assert_eq(BigNum.from_float(15.0).format("scientific"), "15", "small values stay plain")


func test_serialization_roundtrip() -> void:
	var a = BigNum.make(4.2, 77)
	var d: Dictionary = a.to_dict()
	assert_eq(d, {"m": 4.2, "e": 77})
	assert_true(BigNum.from_dict(d).eq(a))
	assert_true(BigNum.from_dict({}).is_zero(), "bad dict is safe")
	assert_true(BigNum.from_dict(null).is_zero(), "null is safe")
	assert_true(BigNum.from_dict({"m": NAN, "e": 2}).is_zero(), "NaN dict is safe")


func test_to_float_saturation() -> void:
	assert_true(is_inf(BigNum.make(1.0, 400).to_float()), "huge exponent saturates to INF")
	assert_near(BigNum.make(1.0, -400).to_float(), 0.0, 1e-12, "tiny exponent flushes to zero")
	assert_near(BigNum.from_float(123.456).to_float(), 123.456, 1e-9)
