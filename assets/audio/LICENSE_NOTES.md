# Audio License Notes

Every `.wav` in this directory is **procedurally generated** by `tools/gen_audio.py`
(Python 3 stdlib only — no samples, no third-party material of any kind involved).

## License

**CC0 1.0 Universal (public domain dedication).** No attribution required.
These files contain no recorded, licensed, or sampled audio.

## Regeneration

From the repository root:

```bash
python3 tools/gen_audio.py
```

The script is deterministic (fixed random seeds): re-running it reproduces
byte-identical files. Never hand-edit the WAVs; edit the generator and re-run.

## Format

| Kind | Files | Format |
|---|---|---|
| One-shot SFX | `click, buy_small, buy_big, unlock, chime_clear, milestone, prestige, scrap, error, tab` | 44.1 kHz, 16-bit PCM, mono |
| Ambience loops | `amb_hum_1, amb_hum_2, amb_hum_3` | 16 kHz, 16-bit PCM, mono, exact 4.000 s seamless loops |

Ambience is written at 16 kHz (content is band-limited factory hum/thrum/clatter)
so a full 4-second loop stays under the 150 KB per-file budget. Loops are seamless
by construction: only exact-cycle sines (whole cycles per loop) plus percussive
events that fully decay before the loop wraps. `AudioDirector` sets
`AudioStreamWAV.loop_mode = LOOP_FORWARD` on them at load time — loop points are
not baked into the file header on purpose (the generator writes canonical PCM).

All peaks are normalized ≤ 0.68 (no clipping headroom rule: ≤ 0.7).
The three ambience files are **additive layers** (1 = room tone + 50 Hz hum,
2 = rhythmic press thrum, 3 = clatter texture); `AudioDirector.set_intensity()`
plays them simultaneously and fades layers in as the line speeds up.
