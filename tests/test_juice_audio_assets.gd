## Juice module asset tests — verifies every generated WAV exists, is canonical
## 16-bit mono PCM, respects the size budget, and matches its pinned duration.
## Pure file inspection: no autoloads, no audio playback (hermetic + headless-safe).
extends "res://tests/test_framework.gd"

const AUDIO_DIR := "res://assets/audio/"
const BUDGET_BYTES := 150 * 1024

# name -> [min_seconds, max_seconds]
const EXPECTED := {
	"click": [0.04, 0.09],
	"buy_small": [0.10, 0.25],
	"buy_big": [0.25, 0.50],
	"unlock": [0.35, 0.70],
	"chime_clear": [0.70, 1.20],
	"milestone": [0.30, 0.55],
	"prestige": [1.00, 1.50],
	"scrap": [0.08, 0.20],
	"error": [0.10, 0.25],
	"tab": [0.05, 0.12],
	"amb_hum_1": [3.50, 4.50],
	"amb_hum_2": [3.50, 4.50],
	"amb_hum_3": [3.50, 4.50],
}


func test_all_wavs_exist_and_are_mono_16bit_pcm() -> void:
	for sfx_name: String in EXPECTED.keys():
		var path := AUDIO_DIR + sfx_name + ".wav"
		assert_true(FileAccess.file_exists(path), "missing " + path)
		if not FileAccess.file_exists(path):
			continue
		var info := _parse_wav(path)
		assert_eq(info.get("riff", ""), "RIFF", sfx_name + " RIFF magic")
		assert_eq(info.get("wave", ""), "WAVE", sfx_name + " WAVE magic")
		assert_eq(int(info.get("audio_format", -1)), 1, sfx_name + " must be PCM")
		assert_eq(int(info.get("channels", -1)), 1, sfx_name + " must be mono")
		assert_eq(int(info.get("bits", -1)), 16, sfx_name + " must be 16-bit")
		assert_true(int(info.get("sample_rate", 0)) >= 8000, sfx_name + " sample rate sane")


func test_durations_match_pinned_design() -> void:
	for sfx_name: String in EXPECTED.keys():
		var path := AUDIO_DIR + sfx_name + ".wav"
		if not FileAccess.file_exists(path):
			fail("missing " + path)
			continue
		var info := _parse_wav(path)
		var sr := int(info.get("sample_rate", 0))
		var data_size := int(info.get("data_size", 0))
		if sr <= 0:
			fail(sfx_name + ": unreadable sample rate")
			continue
		var seconds := float(data_size) / (float(sr) * 2.0)
		var lo := float(EXPECTED[sfx_name][0])
		var hi := float(EXPECTED[sfx_name][1])
		assert_true(seconds >= lo and seconds <= hi,
				"%s duration %.3fs outside [%.2f, %.2f]" % [sfx_name, seconds, lo, hi])


func test_size_budget_under_150kb_each() -> void:
	for sfx_name: String in EXPECTED.keys():
		var path := AUDIO_DIR + sfx_name + ".wav"
		if not FileAccess.file_exists(path):
			fail("missing " + path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		assert_true(f != null, "open " + path)
		if f == null:
			continue
		assert_true(f.get_length() < BUDGET_BYTES,
				"%s is %d bytes (budget %d)" % [sfx_name, f.get_length(), BUDGET_BYTES])


func test_generator_and_license_notes_present() -> void:
	assert_true(FileAccess.file_exists("res://tools/gen_audio.py"),
			"tools/gen_audio.py must ship with the repo")
	assert_true(FileAccess.file_exists("res://assets/audio/LICENSE_NOTES.md"),
			"assets/audio/LICENSE_NOTES.md must document CC0 + regeneration")


## Minimal RIFF/WAVE chunk walker (little-endian, matches FileAccess default).
func _parse_wav(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var hdr := f.get_buffer(12)
	if hdr.size() < 12:
		return out
	out["riff"] = hdr.slice(0, 4).get_string_from_ascii()
	out["wave"] = hdr.slice(8, 12).get_string_from_ascii()
	while f.get_position() + 8 <= f.get_length():
		var cid := f.get_buffer(4).get_string_from_ascii()
		var csize := f.get_32()
		if cid == "fmt " and csize >= 16:
			var fmt_buf := f.get_buffer(csize)
			out["audio_format"] = fmt_buf.decode_u16(0)
			out["channels"] = fmt_buf.decode_u16(2)
			out["sample_rate"] = fmt_buf.decode_u32(4)
			out["bits"] = fmt_buf.decode_u16(14)
		else:
			if cid == "data":
				out["data_size"] = csize
			f.seek(f.get_position() + csize)
	return out
