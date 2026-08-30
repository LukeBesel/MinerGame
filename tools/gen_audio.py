#!/usr/bin/env python3
"""gen_audio.py — generates every Bottleneck SFX + ambience loop into assets/audio/.

Python 3 stdlib only (wave, math, struct, random). Deterministic: fixed seeds, so
re-running reproduces byte-identical files. All output is CC0 (see LICENSE_NOTES.md).

Design rules (docs/ARCHITECTURE.md §11 + juice brief):
  - One-shot SFX: 44.1 kHz, 16-bit, mono, soft attacks, exponential decay, peak <= 0.7.
  - Ambience: three additive layers, EXACT 4.0 s seamless loops. Built only from
    (a) sines whose frequency is an integer multiple of 1/4 Hz (whole cycles per loop)
    and (b) percussive events that fully decay before the loop wraps — so sample[0]
    continues sample[-1] with no click. Ambience is written at 16 kHz so a full
    4-second loop stays under the 150 KB per-file budget (content is < 8 kHz anyway).

Run from anywhere:  python3 tools/gen_audio.py
"""

import math
import os
import random
import struct
import wave

SR = 44100          # one-shot SFX sample rate
AMB_SR = 16000      # ambience sample rate (loops must fit < 150 KB)
LOOP_S = 4.0        # ambience loop length, seconds
TAU = 2.0 * math.pi

OUT_DIR = os.path.normpath(os.path.join(
	os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio"))


# ---------------------------------------------------------------- synth helpers

def buf(seconds, sr=SR):
	return [0.0] * int(round(seconds * sr))


def add_tone(b, sr, start, dur, freq, amp, partials=((1.0, 1.0),),
			tau=0.12, attack=0.004, freq_end=None, phase=0.0):
	"""Additive tone: soft linear attack, exponential decay, optional pitch bend.

	partials: tuple of (ratio, relative_amp); higher partials decay faster for warmth.
	"""
	n0 = int(start * sr)
	n = int(dur * sr)
	f1 = freq if freq_end is None else freq_end
	phases = [phase] * len(partials)
	last = max(n - 1, 1)
	for i in range(n):
		idx = n0 + i
		if idx >= len(b):
			break
		t = i / sr
		u = i / last
		f = freq + (f1 - freq) * u
		a = min(1.0, t / attack) if attack > 0 else 1.0
		e = a * math.exp(-t / tau)
		s = 0.0
		for k, (ratio, pamp) in enumerate(partials):
			phases[k] += TAU * f * ratio / sr
			bright_decay = math.exp(-t * (ratio - 1.0) * 2.0 / max(tau, 1e-6))
			s += pamp * bright_decay * math.sin(phases[k])
		b[idx] += amp * e * s


def add_noise(b, sr, start, dur, amp, lp=3000.0, hp=200.0,
			tau=0.05, attack=0.002, seed=1):
	"""Band-limited noise burst (one-pole LP, minus a lower LP => soft bandpass)."""
	rng = random.Random(seed)
	n0 = int(start * sr)
	n = int(dur * sr)
	lp_a = 1.0 - math.exp(-TAU * min(lp, sr * 0.45) / sr)
	hp_a = 1.0 - math.exp(-TAU * min(hp, sr * 0.45) / sr)
	lp_y = 0.0
	hp_y = 0.0
	for i in range(n):
		idx = n0 + i
		if idx >= len(b):
			break
		t = i / sr
		a = min(1.0, t / attack) if attack > 0 else 1.0
		e = a * math.exp(-t / tau)
		x = rng.uniform(-1.0, 1.0)
		lp_y += lp_a * (x - lp_y)
		hp_y += hp_a * (lp_y - hp_y)
		b[idx] += amp * e * (lp_y - hp_y)


# Music-box / glockenspiel-ish bell: detuned fundamental pair + sparse upper partials.
BELL_PARTIALS = ((1.0, 1.0), (1.003, 0.35), (3.01, 0.20), (4.96, 0.08))


def add_bell(b, sr, start, freq, amp, tau=0.28):
	add_tone(b, sr, start, tau * 6.0, freq, amp, BELL_PARTIALS,
			tau=tau, attack=0.002)


# ------------------------------------------------------------ seamless helpers

def q(freq):
	"""Quantize to a whole number of cycles per LOOP_S (multiples of 0.25 Hz)."""
	return max(round(freq * LOOP_S), 1) / LOOP_S


def add_loop_sine(b, sr, freq, amp, phase=0.0):
	f = q(freq)
	w = TAU * f / sr
	for i in range(len(b)):
		b[i] += amp * math.sin(w * i + phase)


def add_periodic_noise(b, sr, f_lo, f_hi, n_sines, amp, seed, slope=1.0):
	"""'Noise' that is perfectly loop-periodic: many exact-cycle sines, random
	phase/frequency, 1/f^slope amplitude tilt. Seamless by construction."""
	rng = random.Random(seed)
	for _ in range(n_sines):
		f = q(rng.uniform(f_lo, f_hi))
		a = amp / max(f / f_lo, 1.0) ** slope
		add_loop_sine(b, sr, f, a, rng.uniform(0.0, TAU))


def apply_loop_am(b, sr, rate_hz, depth):
	"""Slow amplitude wobble; rate quantized so it completes whole cycles per loop."""
	f = q(rate_hz)
	w = TAU * f / sr
	for i in range(len(b)):
		b[i] *= 1.0 + depth * math.sin(w * i)


# ------------------------------------------------------------------ file output

MANIFEST = []


def write_wav(name, b, sr=SR, peak=0.65, fade_out=0.03):
	if fade_out > 0.0:
		nf = min(int(fade_out * sr), len(b))
		for i in range(nf):
			g = 0.5 * (1.0 + math.cos(math.pi * (i + 1) / nf))
			b[len(b) - nf + i] *= g
	m = max(abs(x) for x in b)
	gain = (peak / m) if m > 1e-12 else 0.0
	path = os.path.join(OUT_DIR, name)
	frames = bytearray()
	for x in b:
		v = max(-1.0, min(1.0, x * gain))
		frames += struct.pack("<h", int(v * 32767))
	with wave.open(path, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(sr)
		w.writeframes(bytes(frames))
	kb = os.path.getsize(path) / 1024.0
	secs = len(b) / sr
	MANIFEST.append((name, secs, kb, sr))
	assert kb < 150.0, "%s is %.1f KB (budget 150 KB)" % (name, kb)
	print("  %-18s %6.3f s  %7.1f KB  %d Hz" % (name, secs, kb, sr))


# ----------------------------------------------------------------- one-shot SFX

def gen_click():
	"""Short filtered UI tick (~60 ms)."""
	b = buf(0.06)
	add_tone(b, SR, 0.0, 0.05, 1900.0, 0.7, ((1.0, 1.0), (2.4, 0.22)),
			tau=0.010, attack=0.001)
	add_noise(b, SR, 0.0, 0.03, 0.45, lp=4500.0, hp=900.0, tau=0.008, seed=11)
	write_wav("click.wav", b, peak=0.5, fade_out=0.012)


def gen_buy_small():
	"""Two-note coin blip B5 -> E6 (~150 ms)."""
	b = buf(0.16)
	p = ((1.0, 1.0), (2.0, 0.28), (3.0, 0.10))
	add_tone(b, SR, 0.000, 0.070, 987.77, 0.60, p, tau=0.030, attack=0.002)
	add_tone(b, SR, 0.045, 0.115, 1318.51, 0.70, p, tau=0.045, attack=0.002)
	write_wav("buy_small.wav", b, peak=0.62, fade_out=0.02)


def gen_buy_big():
	"""Richer three-note rising arpeggio (A major) + low thump (~350 ms)."""
	b = buf(0.36)
	add_tone(b, SR, 0.0, 0.30, 96.0, 0.85, ((1.0, 1.0), (2.0, 0.18)),
			tau=0.070, attack=0.003, freq_end=52.0)
	p = ((1.0, 1.0), (2.0, 0.30), (3.0, 0.12))
	arp = ((0.00, 440.00), (0.07, 554.37), (0.14, 659.26))
	for i, (t0, f) in enumerate(arp):
		add_tone(b, SR, t0, 0.22, f, 0.42 + 0.08 * i, p,
				tau=0.060 + 0.025 * i, attack=0.003)
	add_bell(b, SR, 0.14, 1318.51, 0.22, tau=0.10)
	write_wav("buy_big.wav", b, peak=0.66, fade_out=0.03)


def gen_unlock():
	"""Warm A-major chord swell with a soft top bell (~500 ms)."""
	b = buf(0.50)
	chord = (220.00, 277.18, 329.63, 440.00)
	for j, f in enumerate(chord):
		add_tone(b, SR, 0.0, 0.50, f * (1.0 + 0.0006 * j), 0.30,
				((1.0, 1.0), (2.0, 0.35), (3.0, 0.12), (4.0, 0.05)),
				tau=0.55, attack=0.12)
	add_bell(b, SR, 0.16, 880.0, 0.16, tau=0.16)
	write_wav("unlock.wav", b, peak=0.60, fade_out=0.06)


def gen_chime_clear():
	"""THE signature: bright bell arpeggio D6-F#6-A6-D7 + shimmer tail (~900 ms)."""
	b = buf(0.90)
	notes = ((0.00, 1174.66), (0.09, 1479.98), (0.18, 1760.00), (0.30, 2349.32))
	for i, (t0, f) in enumerate(notes):
		add_bell(b, SR, t0, f, 0.55 - 0.06 * i, tau=0.30 + 0.05 * i)
	add_tone(b, SR, 0.0, 0.5, 587.33, 0.16, ((1.0, 1.0), (2.0, 0.2)),
			tau=0.28, attack=0.010)  # warm root under the bells
	rng = random.Random(7)
	for _ in range(24):  # shimmer sprinkles fading down the tail
		t0 = 0.30 + 0.52 * rng.random()
		f = rng.choice((2349.32, 2793.83, 3520.00, 4698.64))
		f *= 1.0 + rng.uniform(-0.004, 0.004)
		a = 0.055 * (1.0 - (t0 - 0.30) / 0.62)
		add_tone(b, SR, t0, 0.20, f, a, ((1.0, 1.0),), tau=0.06, attack=0.004)
	write_wav("chime_clear.wav", b, peak=0.68, fade_out=0.08)


def gen_milestone():
	"""Short triumphant two-chord sting: D major -> G major (~400 ms)."""
	b = buf(0.42)
	p = ((1.0, 1.0), (2.0, 0.45), (3.0, 0.20), (4.0, 0.09), (5.0, 0.04))
	for f in (293.66, 369.99, 440.00):
		add_tone(b, SR, 0.0, 0.16, f, 0.30, p, tau=0.090, attack=0.006)
	for f in (392.00, 493.88, 587.33, 783.99):
		add_tone(b, SR, 0.13, 0.29, f, 0.30, p, tau=0.160, attack=0.006)
	add_bell(b, SR, 0.13, 1567.98, 0.14, tau=0.12)
	write_wav("milestone.wav", b, peak=0.65, fade_out=0.04)


def gen_prestige():
	"""Big warm swell (A2 stack, slow attack) cresting into bells (~1.2 s)."""
	b = buf(1.20)
	chord = (110.00, 220.00, 329.63, 440.00, 554.37)
	for j, f in enumerate(chord):
		add_tone(b, SR, 0.0, 1.20, f, 0.26,
				((1.0, 1.0), (2.0, 0.40), (3.0, 0.16), (4.0, 0.07)),
				tau=0.90, attack=0.32 + 0.04 * j)
	add_bell(b, SR, 0.55, 880.00, 0.38, tau=0.34)
	add_bell(b, SR, 0.72, 1318.51, 0.26, tau=0.30)
	rng = random.Random(21)
	for k in range(16):  # rising sparkle over the crest
		t0 = 0.50 + 0.50 * (k / 16.0)
		f = 1760.0 * (1.0 + 0.5 * rng.random())
		add_tone(b, SR, t0, 0.15, f, 0.040, ((1.0, 1.0),), tau=0.05, attack=0.004)
	write_wav("prestige.wav", b, peak=0.68, fade_out=0.10)


def gen_scrap():
	"""Dull clunk: fast pitch-drop thud + heavily lowpassed knock (~120 ms)."""
	b = buf(0.12)
	add_tone(b, SR, 0.0, 0.10, 150.0, 0.9, ((1.0, 1.0), (1.58, 0.35), (2.24, 0.15)),
			tau=0.035, attack=0.002, freq_end=55.0)
	add_noise(b, SR, 0.0, 0.07, 0.5, lp=900.0, hp=90.0, tau=0.020, seed=5)
	write_wav("scrap.wav", b, peak=0.5, fade_out=0.02)


def gen_error():
	"""Soft low double-blip, descending (Bb3 then G3), never punishing (~150 ms)."""
	b = buf(0.16)
	p = ((1.0, 1.0), (2.0, 0.12))
	add_tone(b, SR, 0.000, 0.060, 233.08, 0.6, p, tau=0.030, attack=0.005)
	add_tone(b, SR, 0.075, 0.080, 185.00, 0.6, p, tau=0.035, attack=0.005)
	write_wav("error.wav", b, peak=0.48, fade_out=0.02)


def gen_tab():
	"""Tiny swish for tab switches: two overlapping soft noise bands (~80 ms)."""
	b = buf(0.08)
	add_noise(b, SR, 0.00, 0.05, 0.50, lp=2600.0, hp=900.0,
			tau=0.030, attack=0.012, seed=3)
	add_noise(b, SR, 0.02, 0.05, 0.35, lp=5200.0, hp=1800.0,
			tau=0.025, attack=0.010, seed=4)
	write_wav("tab.wav", b, peak=0.38, fade_out=0.015)


# ------------------------------------------------------------------- ambience
# Layer files are ADDITIVE: AudioDirector plays all three simultaneously and
# fades each in as intensity rises. Layer 1 = base room tone; layer 2 = rhythmic
# thrum only; layer 3 = clatter texture only. Stacking them builds the factory.

def gen_amb_1():
	"""Low room tone + ~50 Hz transformer hum with slow beating. 4.0 s seamless."""
	b = buf(LOOP_S, AMB_SR)
	add_loop_sine(b, AMB_SR, 50.00, 0.30, 0.0)
	add_loop_sine(b, AMB_SR, 50.25, 0.16, 1.3)   # 0.25 Hz beat = 1 cycle/loop
	add_loop_sine(b, AMB_SR, 100.00, 0.12, 0.7)
	add_loop_sine(b, AMB_SR, 150.00, 0.05, 2.1)
	add_periodic_noise(b, AMB_SR, 60.0, 500.0, 60, 0.055, seed=101, slope=1.1)
	add_periodic_noise(b, AMB_SR, 500.0, 2200.0, 40, 0.010, seed=102, slope=0.8)
	apply_loop_am(b, AMB_SR, 0.25, 0.10)
	write_wav("amb_hum_1.wav", b, sr=AMB_SR, peak=0.34, fade_out=0.0)


def gen_amb_2():
	"""Adds rhythmic mechanical thrum: 8 soft press strokes per loop + undertone."""
	b = buf(LOOP_S, AMB_SR)
	period = 0.5  # exactly 8 thumps per 4 s loop
	n_thumps = int(round(LOOP_S / period))
	rng = random.Random(55)
	for k in range(n_thumps):
		t0 = k * period
		amp = 0.55 * (0.9 + 0.2 * rng.random())
		add_tone(b, AMB_SR, t0, period * 0.9, 84.0, amp,
				((1.0, 1.0), (1.5, 0.25), (2.0, 0.12)),
				tau=0.055, attack=0.006, freq_end=58.0)
		add_noise(b, AMB_SR, t0 + 0.012, 0.10, 0.16, lp=1200.0, hp=150.0,
				tau=0.030, attack=0.004, seed=1000 + k)
	add_loop_sine(b, AMB_SR, 62.50, 0.10, 0.4)   # motor undertone
	apply_loop_am(b, AMB_SR, 0.50, 0.06)
	write_wav("amb_hum_2.wav", b, sr=AMB_SR, peak=0.36, fade_out=0.0)


def gen_amb_3():
	"""Adds busier clatter texture: sparse ticks + small clanks, low level."""
	b = buf(LOOP_S, AMB_SR)
	rng = random.Random(99)
	t = 0.05
	while t < LOOP_S - 0.25:  # keep the loop tail clear so events fully decay
		roll = rng.random()
		if roll < 0.55:
			add_noise(b, AMB_SR, t, 0.05, 0.22 * rng.uniform(0.4, 1.0),
					lp=rng.uniform(2500.0, 6000.0), hp=1100.0,
					tau=0.012, attack=0.001, seed=rng.randrange(1 << 30))
		elif roll < 0.85:
			add_tone(b, AMB_SR, t, 0.12, rng.uniform(520.0, 950.0),
					0.16 * rng.uniform(0.4, 1.0),
					((1.0, 1.0), (2.7, 0.30), (4.1, 0.12)),
					tau=0.030, attack=0.001)
		t += rng.uniform(0.09, 0.26)
	add_periodic_noise(b, AMB_SR, 900.0, 3800.0, 30, 0.012, seed=103, slope=0.7)
	apply_loop_am(b, AMB_SR, 0.75, 0.08)
	write_wav("amb_hum_3.wav", b, sr=AMB_SR, peak=0.34, fade_out=0.0)


# ---------------------------------------------------------------------- driver

def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	print("Generating Bottleneck audio into %s" % OUT_DIR)
	gen_click()
	gen_buy_small()
	gen_buy_big()
	gen_unlock()
	gen_chime_clear()
	gen_milestone()
	gen_prestige()
	gen_scrap()
	gen_error()
	gen_tab()
	gen_amb_1()
	gen_amb_2()
	gen_amb_3()
	total_kb = sum(kb for _, _, kb, _ in MANIFEST)
	print("Done: %d files, %.1f KB total." % (len(MANIFEST), total_kb))


if __name__ == "__main__":
	main()
