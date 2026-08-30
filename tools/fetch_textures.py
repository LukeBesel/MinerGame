#!/usr/bin/env python3
"""Fetch the pinned CC0 PBR texture sets for Bottleneck's 3D factory and generate the
small procedural decal textures (hazard stripes, oil stain, tire skid).

Downloads (ambientCG, all CC0 1.0 Universal — no attribution required,
https://docs.ambientcg.com/license/):
  https://ambientcg.com/get?file=Concrete034_1K-JPG.zip        (worn concrete floor)
  https://ambientcg.com/get?file=CorrugatedSteel005_1K-JPG.zip (hall walls)
  https://ambientcg.com/get?file=PaintedMetal012_1K-JPG.zip    (painted machine bodies; desaturated for tinting)
  https://ambientcg.com/get?file=MetalPlates006_1K-JPG.zip     (machine frames / steel plate)
  https://ambientcg.com/get?file=Metal032_1K-JPG.zip           (galvanized trim, rails, legs)
  https://ambientcg.com/get?file=Rubber004_1K-JPG.zip          (conveyor belt rubber)
  https://ambientcg.com/get?file=DiamondPlate005A_1K-JPG.zip   (walkways / mezzanine deck)

Only the Color + NormalGL + Roughness maps are kept, recompressed with PIL so the whole
committed payload stays well under 10 MB (color/normal 1K JPG, roughness 512 grayscale JPG).

Fallback chain if ambientCG is unreachable through the proxy: try again later, fetch the
equivalent CC0 sets from Poly Haven (https://api.polyhaven.com) by hand, or run this script
with --procedural to synthesize stand-in maps with PIL (layered noise; clearly worse, but
the game degrades gracefully — world_lib.gd falls back to flat materials when maps are
missing entirely).

Idempotent: existing complete sets are skipped (use --force to re-download/regenerate).
Run from anywhere: paths are resolved relative to this file's repo.
"""

import argparse
import io
import math
import os
import random
import ssl
import sys
import time
import urllib.request
import zipfile

try:
	from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
	print("ERROR: PIL (pillow) is required: pip3 install pillow", file=sys.stderr)
	sys.exit(1)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(REPO, "assets", "textures")

# (set name, desaturate color map for runtime tinting, brighten target)
SETS = [
	("Concrete034", False, None),
	("CorrugatedSteel005", False, None),
	("PaintedMetal012", True, 0.72),
	("MetalPlates006", False, None),
	("Metal032", False, None),
	("Rubber004", False, None),
	("DiamondPlate005A", True, 0.52),	# painted blue in the source — desaturate; relief is in the normal map
]

MAPS = ("Color", "NormalGL", "Roughness")
URL_FMT = "https://ambientcg.com/get?file={name}_1K-JPG.zip"


def _ssl_context():
	ctx = ssl.create_default_context()
	# The sandbox proxy's CA may live outside the system store.
	for cand in (os.environ.get("SSL_CERT_FILE"), "/root/.ccr/ca-bundle.crt"):
		if cand and os.path.isfile(cand):
			try:
				ctx.load_verify_locations(cafile=cand)
			except ssl.SSLError:
				pass
	return ctx


def download(url, attempts=4):
	last = None
	for i in range(attempts):
		try:
			req = urllib.request.Request(url, headers={"User-Agent": "bottleneck-fetch/1.0"})
			with urllib.request.urlopen(req, timeout=120, context=_ssl_context()) as r:
				return r.read()
		except Exception as e:  # transient proxy resets happen; back off and retry
			last = e
			time.sleep(1.5 * (i + 1))
	raise last


def set_dir(name):
	return os.path.join(OUT_ROOT, name)


def out_path(name, map_name):
	return os.path.join(set_dir(name), "%s_%s.jpg" % (name, map_name))


def set_complete(name):
	return all(os.path.isfile(out_path(name, m)) and os.path.getsize(out_path(name, m)) > 0 for m in MAPS)


def save_color(img, path, desat=False, brighten=None, quality=78):
	img = img.convert("RGB")
	if img.width > 1024:
		img = img.resize((1024, 1024), Image.LANCZOS)
	if desat:
		grey = img.convert("L").convert("RGB")
		img = Image.blend(img, grey, 0.85)
	if brighten is not None:
		# Normalize mean luma toward `brighten` so albedo_color tinting reads predictably.
		small = img.convert("L").resize((64, 64))
		mean = sum(small.point(lambda v: v).histogram()[i] * i for i in range(256)) / (64.0 * 64.0 * 255.0)
		if mean > 0.01:
			img = img.point(lambda v: min(255, int(v * (brighten / mean))))
	img.save(path, "JPEG", quality=quality, optimize=True)


def save_normal(img, path):
	img = img.convert("RGB")
	if img.width > 1024:
		img = img.resize((1024, 1024), Image.LANCZOS)
	# 4:4:4 chroma keeps normal vectors from smearing.
	img.save(path, "JPEG", quality=86, optimize=True, subsampling=0)


def save_rough(img, path):
	img = img.convert("L")
	if img.width > 512:
		img = img.resize((512, 512), Image.LANCZOS)
	img.save(path, "JPEG", quality=72, optimize=True)


def process_zip(name, blob, desat, brighten):
	os.makedirs(set_dir(name), exist_ok=True)
	zf = zipfile.ZipFile(io.BytesIO(blob))
	found = {}
	for info in zf.infolist():
		base = os.path.basename(info.filename)
		for m in MAPS:
			if base.endswith("_%s.jpg" % m) or base.endswith("_%s.png" % m):
				found[m] = info
	missing = [m for m in MAPS if m not in found]
	if missing:
		raise RuntimeError("%s: maps missing from zip: %s" % (name, missing))
	for m in MAPS:
		img = Image.open(io.BytesIO(zf.read(found[m])))
		dst = out_path(name, m)
		if m == "Color":
			save_color(img, dst, desat=desat, brighten=brighten)
		elif m == "NormalGL":
			save_normal(img, dst)
		else:
			save_rough(img, dst)


# ---------------------------------------------------------------- procedural fallbacks

def _noise_img(size, scales, seed):
	rng = random.Random(seed)
	acc = Image.new("L", (size, size), 128)
	for scale, weight in scales:
		small = Image.new("L", (scale, scale))
		small.putdata([rng.randint(0, 255) for _ in range(scale * scale)])
		layer = small.resize((size, size), Image.BICUBIC)
		acc = Image.blend(acc, layer, weight)
	return acc


def procedural_set(name, desat, brighten):
	os.makedirs(set_dir(name), exist_ok=True)
	base = {
		"Concrete034": (118, 116, 112),
		"CorrugatedSteel005": (128, 132, 136),
		"PaintedMetal017": (150, 150, 152),
		"MetalPlates006": (110, 112, 116),
		"Metal032": (140, 144, 148),
		"Rubber004": (38, 38, 40),
		"DiamondPlate005A": (120, 124, 128),
	}.get(name, (120, 120, 120))
	n = _noise_img(1024, [(8, 0.35), (32, 0.3), (128, 0.2)], hash(name) & 0xFFFF)
	col = Image.merge("RGB", [n.point(lambda v, c=c: max(0, min(255, c + (v - 128)))) for c in base])
	save_color(col, out_path(name, "Color"), desat=desat, brighten=brighten)
	flat = Image.new("RGB", (1024, 1024), (128, 128, 255))
	save_normal(flat, out_path(name, "NormalGL"))
	save_rough(n.point(lambda v: 140 + (v - 128) // 3), out_path(name, "Roughness"))


# ---------------------------------------------------------------- generated decals (original, CC0)

def gen_hazard(path):
	"""Safety-yellow / near-black diagonal stripes with light grunge."""
	s = 256
	img = Image.new("RGB", (s, s))
	d = ImageDraw.Draw(img)
	period = 64
	for x in range(-s, s * 2, period):
		d.polygon([(x, 0), (x + period // 2, 0), (x + period // 2 - s, s), (x - s, s)], fill=(224, 174, 62))
		d.polygon([(x + period // 2, 0), (x + period, 0), (x + period - s, s), (x + period // 2 - s, s)], fill=(26, 26, 28))
	grunge = _noise_img(s, [(16, 0.5), (64, 0.35)], 77)
	img = Image.composite(img.point(lambda v: int(v * 0.72)), img, grunge.point(lambda v: 255 if v > 176 else 0))
	img = img.filter(ImageFilter.GaussianBlur(0.6))
	img.save(path, "JPEG", quality=82, optimize=True)


def gen_oil(path):
	"""Dark oil stain decal with an alpha falloff (RGBA PNG)."""
	s = 256
	rng = random.Random(4242)
	alpha = Image.new("L", (s, s), 0)
	d = ImageDraw.Draw(alpha)
	for _ in range(9):
		cx, cy = rng.randint(70, s - 70), rng.randint(70, s - 70)
		r = rng.randint(28, 78)
		d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rng.randint(110, 185))
	alpha = alpha.filter(ImageFilter.GaussianBlur(18))
	speck = _noise_img(s, [(32, 0.6), (128, 0.4)], 9)
	alpha = Image.composite(alpha.point(lambda v: int(v * 0.55)), alpha, speck.point(lambda v: 255 if v > 168 else 0))
	rgb = Image.new("RGB", (s, s), (10, 10, 12))
	rgb.putalpha(alpha)
	rgb.save(path, "PNG", optimize=True)


def gen_skid(path):
	"""Pair of curved tire skid marks (RGBA PNG)."""
	s = 256
	img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	for off in (-16, 16):
		pts = []
		for i in range(40):
			t = i / 39.0
			x = s * 0.5 + off + math.sin(t * 1.9 + 0.4) * 26
			y = 16 + t * (s - 32)
			pts.append((x, y))
		for i in range(len(pts) - 1):
			w = int(9 + 5 * math.sin(i * 0.35))
			a = int(120 * (0.35 + 0.65 * math.sin(math.pi * i / len(pts))))
			d.line([pts[i], pts[i + 1]], fill=(14, 14, 16, a), width=w)
	img = img.filter(ImageFilter.GaussianBlur(2.2))
	img.save(path, "PNG", optimize=True)


def gen_decals(force):
	gdir = os.path.join(OUT_ROOT, "generated")
	os.makedirs(gdir, exist_ok=True)
	jobs = [
		("hazard_stripes.jpg", gen_hazard),
		("oil_stain.png", gen_oil),
		("skid_marks.png", gen_skid),
	]
	for fname, fn in jobs:
		dst = os.path.join(gdir, fname)
		if os.path.isfile(dst) and os.path.getsize(dst) > 0 and not force:
			print("  generated/%-22s up to date" % fname)
			continue
		fn(dst)
		print("  generated/%-22s %6.1f KB" % (fname, os.path.getsize(dst) / 1024.0))


# ---------------------------------------------------------------- main

def main():
	ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	ap.add_argument("--force", action="store_true", help="re-download / regenerate everything")
	ap.add_argument("--procedural", action="store_true", help="skip network, synthesize all maps with PIL")
	args = ap.parse_args()

	os.makedirs(OUT_ROOT, exist_ok=True)
	failures = []
	for name, desat, brighten in SETS:
		if set_complete(name) and not args.force:
			print("  %-20s up to date" % name)
			continue
		if args.procedural:
			procedural_set(name, desat, brighten)
			print("  %-20s procedural stand-in written" % name)
			continue
		url = URL_FMT.format(name=name)
		try:
			print("  %-20s downloading %s" % (name, url))
			blob = download(url)
			process_zip(name, blob, desat, brighten)
			kb = sum(os.path.getsize(out_path(name, m)) for m in MAPS) / 1024.0
			print("  %-20s ok (%.0f KB kept of %.0f KB zip)" % (name, kb, len(blob) / 1024.0))
		except Exception as e:  # noqa: BLE001 — report and fall back per set
			print("  %-20s FAILED (%s) — writing procedural stand-in" % (name, e), file=sys.stderr)
			try:
				procedural_set(name, desat, brighten)
			except Exception as e2:  # pragma: no cover
				failures.append("%s: %s / %s" % (name, e, e2))

	gen_decals(args.force)

	total = 0
	for root, _dirs, files in os.walk(OUT_ROOT):
		for f in files:
			if not f.endswith(".import"):
				total += os.path.getsize(os.path.join(root, f))
	print("TOTAL texture payload: %.2f MB (budget 10 MB)" % (total / 1024.0 / 1024.0))
	if failures:
		print("FAILURES: %s" % failures, file=sys.stderr)
		return 1
	if total > 10 * 1024 * 1024:
		print("ERROR: payload over budget", file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
