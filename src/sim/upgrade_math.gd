## UpgradeMath — closed-form cost curves for station upgrades: cost(level) = base * growth^level.
## Bulk pricing is the exact geometric-series sum; BUY_MAX solves the largest affordable count
## in O(1) (log-space) with a tiny float-slop adjustment. Pure statics, BigNum in/out.
extends RefCounted

const BigNum = preload("res://src/sim/big_num.gd")

const LN10 := 2.302585092994046
const GROWTH_FLAT_EPS := 1e-9
const MAX_BULK_COUNT := 1000000000


## Cost of the single upgrade level `level` (0-based). Returns BigNum.
static func level_cost(base_cost: float, growth: float, level: int, cost_mult: float = 1.0):
	var eff_base: float = max(base_cost * cost_mult, 0.0)
	if eff_base == 0.0:
		return BigNum.zero()
	return BigNum.from_pow(max(growth, GROWTH_FLAT_EPS), float(level)).mul_f(eff_base)


## Exact cost of buying `count` levels starting at `level`:
## sum_{i=0}^{count-1} base*growth^(level+i) = cost(level) * (growth^count - 1)/(growth - 1).
static func bulk_cost(base_cost: float, growth: float, level: int, count: int, cost_mult: float = 1.0):
	if count <= 0:
		return BigNum.zero()
	var c0 = level_cost(base_cost, growth, level, cost_mult)
	if absf(growth - 1.0) < GROWTH_FLAT_EPS:
		return c0.mul_f(float(count))
	var g_pow_n = BigNum.from_pow(growth, float(count))
	var factor = g_pow_n.sub(BigNum.from_float(1.0)).mul_f(1.0 / (growth - 1.0))
	return c0.mul(factor)


## Largest count of levels affordable with `money` starting at `level` (0 if none).
## Closed form: growth^n <= money*(growth-1)/cost(level) + 1, then +-1 slop verification
## against the exact bulk_cost so the answer is always the true maximum.
static func max_affordable(base_cost: float, growth: float, level: int, money, cost_mult: float = 1.0) -> int:
	var c0 = level_cost(base_cost, growth, level, cost_mult)
	if c0.is_zero():
		return MAX_BULK_COUNT
	if money.lt(c0):
		return 0
	var n: int = 1
	if absf(growth - 1.0) < GROWTH_FLAT_EPS:
		var ratio = money.div(c0)
		var f: float = ratio.to_float()
		if is_inf(f) or f > float(MAX_BULK_COUNT):
			return MAX_BULK_COUNT
		n = int(floor(f + 1e-9))
	else:
		# q = money*(g-1)/c0; n = floor(log_g(q + 1))
		var q = money.mul_f(growth - 1.0).div(c0)
		var q1 = q.add(BigNum.from_float(1.0))
		var log10_q1: float = log(q1.m) / LN10 + float(q1.e)
		var log10_g: float = log(growth) / LN10
		n = int(floor(log10_q1 / log10_g))
	n = clampi(n, 1, MAX_BULK_COUNT)
	# Float-slop adjustment: guarantee exactness against the closed-form price.
	# (money >= cost of one level is already established, so n = 1 is always safe.)
	var guard: int = 0
	while guard < 64 and n > 1 and bulk_cost(base_cost, growth, level, n, cost_mult).gt(money):
		n -= 1
		guard += 1
	guard = 0
	while guard < 64 and n < MAX_BULK_COUNT and bulk_cost(base_cost, growth, level, n + 1, cost_mult).le(money):
		n += 1
		guard += 1
	return n
