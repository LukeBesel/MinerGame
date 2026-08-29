## BigNum — mantissa/exponent number type for values beyond double precision.
## Immutable: every operation returns a new BigNum. Serializes as {"m": float, "e": int}.
## Reference from other files via: const BigNum = preload("res://src/sim/big_num.gd")
## No class_name (headless-safe, see ARCHITECTURE.md §2); internals are duck-typed.
extends RefCounted

const LN10 := 2.302585092994046
const SUFFIXES := ["", "K", "M", "B", "T"]

var m: float = 0.0	# mantissa: 0.0, or 1 <= |m| < 10
var e: int = 0	# base-10 exponent


static func zero():
	return new()


static func make(mantissa: float, exponent: int):
	var b := new()
	b.m = mantissa
	b.e = exponent
	b._normalize()
	return b


static func from_float(x: float):
	if x == 0.0 or is_nan(x):
		return zero()
	if is_inf(x):
		return make(signf(x), 308)
	var ex := int(floor(log(absf(x)) / LN10))
	return make(x / pow(10.0, float(ex)), ex)


static func from_dict(d: Variant):
	if typeof(d) != TYPE_DICTIONARY:
		return zero()
	if not d.has("m") or not d.has("e"):
		return zero()
	var mv := float(d["m"])
	if is_nan(mv) or is_inf(mv):
		return zero()
	return make(mv, int(d["e"]))


## base ** exponent for positive float base — exact enough for cost curves at any level.
static func from_pow(base: float, exponent: float):
	if base <= 0.0:
		return zero()
	var t := exponent * (log(base) / LN10)
	var ex := int(floor(t))
	return make(pow(10.0, t - float(ex)), ex)


func _normalize() -> void:
	if m == 0.0 or is_nan(m):
		m = 0.0
		e = 0
		return
	var a := absf(m)
	while a >= 10.0:
		m /= 10.0
		e += 1
		a = absf(m)
	while a < 1.0:
		m *= 10.0
		e -= 1
		a = absf(m)


func clone():
	return make(m, e)


func is_zero() -> bool:
	return m == 0.0


func neg():
	return make(-m, e)


func add(o):
	if is_zero():
		return o.clone()
	if o.is_zero():
		return clone()
	var hi = self
	var lo = o
	if o.e > e:
		hi = o
		lo = self
	var de: int = hi.e - lo.e
	if de > 15:
		return hi.clone()
	return make(hi.m + lo.m * pow(10.0, -float(de)), hi.e)


func sub(o):
	return add(o.neg())


func mul(o):
	if is_zero() or o.is_zero():
		return zero()
	return make(m * o.m, e + o.e)


func mul_f(f: float):
	if f == 0.0 or is_zero():
		return zero()
	return mul(from_float(f))


func div(o):
	if o.is_zero():
		return make(signf(m), 308)	# division-by-zero guard: saturate
	if is_zero():
		return zero()
	return make(m / o.m, e - o.e)


## Returns -1, 0 or 1 comparing self to o (with a small mantissa epsilon).
func cmp(o) -> int:
	var sa := signf(m)
	var sb := signf(o.m)
	if is_zero() and o.is_zero():
		return 0
	if sa != sb:
		return -1 if sa < sb else 1
	if e != o.e:
		var bigger_abs := 1 if e > o.e else -1
		return bigger_abs if sa >= 0.0 else -bigger_abs
	if absf(m - o.m) < 1e-12:
		return 0
	return 1 if m > o.m else -1


func lt(o) -> bool:
	return cmp(o) < 0


func le(o) -> bool:
	return cmp(o) <= 0


func gt(o) -> bool:
	return cmp(o) > 0


func ge(o) -> bool:
	return cmp(o) >= 0


func eq(o) -> bool:
	return cmp(o) == 0


func to_float() -> float:
	if is_zero():
		return 0.0
	if e > 307:
		return INF * signf(m)
	if e < -307:
		return 0.0
	return m * pow(10.0, float(e))


func to_dict() -> Dictionary:
	return {"m": m, "e": e}


## Human formatting. mode "suffix": 1.23K / 4.56M / 7.89B / 1.23T then aa..zz;
## mode "scientific": 1.23e45. Values below 1000 print plainly.
func format(mode: String = "suffix", decimals: int = 2) -> String:
	if is_zero():
		return "0"
	var sign_prefix := "-" if m < 0.0 else ""
	var am := absf(m)
	if e < 3:
		return sign_prefix + _plain(am * pow(10.0, float(e)))
	if mode == "scientific":
		return "%s%.*fe%d" % [sign_prefix, decimals, am, e]
	var idx := int(floor(float(e) / 3.0))
	var rem := e - idx * 3
	var scaled := am * pow(10.0, float(rem))
	var suffix := ""
	if idx < SUFFIXES.size():
		suffix = SUFFIXES[idx]
	else:
		var n := idx - SUFFIXES.size()	# n = 0 => "aa" at 1e15
		if n >= 26 * 26:
			return "%s%.*fe%d" % [sign_prefix, decimals, am, e]
		suffix = char(97 + int(floor(float(n) / 26.0))) + char(97 + n % 26)
	return sign_prefix + _trim("%.*f" % [decimals, scaled]) + suffix


func _plain(v: float) -> String:
	if v >= 100.0 or absf(v - roundf(v)) < 0.005:
		return str(int(roundf(v)))
	return _trim("%.1f" % v)


func _trim(s: String) -> String:
	if not s.contains("."):
		return s
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s
