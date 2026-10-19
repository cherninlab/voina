# Prepared game audio

`content/audio/catalog.tres` is the Godot sound database. Each `GameSoundClip`
references its imported `AudioStream`, so the catalog and its audio dependencies
can be included in an exported game by referencing the resource. No autoload or
combat/network behavior is added. Playback hooks are a separate integration step.

`content/audio/catalog.json` contains the same clips plus detailed processing,
provenance and timing metadata. `content/audio/audition.html` is a local browser
audition page with filtering, waveforms, playback and source intervals.

## Selection and processing

The source is the user's Sonniss GameAudioGDC 2026 / Part 9 download, narrowed to
29 recordings, producing 88 clips (about 36 MB including metadata). `sources.json` records exact source filenames, SHA-256 hashes,
segmentation settings, reviewed windows and expected variant counts. The original
recordings are not duplicated in the game repository.

- Six sword slide/cut takes, 21 heavy swing/thud takes, 16 wooden weapon impacts,
  three complete buckler drop/spin performances and four body punches are separated.
- Single swing, gore and vocal effects keep their internal action intact. A swing
  already combined with an impact is still combined; this is documented in notes.
- Eight representative flip-flop steps per surface (grass and wood) are extracted
  from continuous walks. These are provisional surface layers, not boot recordings.
- Full breathing phrases and long outdoor/weather recordings retain their context.
  Additional transient candidates are available inside each clip's timing metadata.

Short effects are mono 48 kHz / 16-bit PCM WAV for positioned playback. Continuous
ambience/weather is stereo 48 kHz Ogg Vorbis quality 5. Effects are trimmed with
15 ms pre-roll and up to 60 ms post-roll around activity above the source's trim
threshold; split detection uses a separate gate to avoid chopping quiet tails.
Explicit windows keep shield spins and footfalls together. All clips receive a
1 ms fade-in and 12 ms fade-out. Gain is attenuated only when needed to keep the
whole source at or below -3 dBFS before encoding; variation levels are preserved.
There is no loudness boost, denoising, pitch shifting or model-based processing.

Waveforms and cut boundaries were inspected. Listening acceptance and game mixing
remain pending. Ambiences are **not** marked as seamless loops: edge fades prevent
hard edge clicks but do not make a convincing repeating soundscape. Use crossfaded
ambience playback or review/edit a loop before enabling looping.

## Timing convention

All decoded frame indices use 48,000 frames/second. Intervals are half-open:
`[start_frame, end_frame)`. A frame contains all channels at one time instant.

| Field | Meaning |
| --- | --- |
| `source.start_frame`, `source.end_frame` | Extracted interval in the source after decoding/resampling to 48 kHz, before fades/gain |
| `source.original_start_frame`, `source.original_end_frame` | Rounded corresponding positions at the original recording's sample rate |
| `frame_count`, `duration_seconds` | Delivered clip length, including pre-roll/tail |
| `timing.onset_frame` | Start of first active 5 ms RMS window |
| `timing.energy_peak_frame` | Centre of strongest 5 ms RMS window; useful audition/sync candidate |
| `timing.amplitude_peak_frame` | Exact decoded frame with the largest absolute sample |
| `timing.active_end_frame` | Exclusive end of last active RMS window |
| `timing.attack_seconds` | Time from measured onset to strongest RMS window; not a combat windup duration |
| `timing.decay_seconds` | Time from strongest RMS window to measured activity end; not necessarily a monotonic decay |
| `timing.tail_seconds` | Remaining clip time after measured activity ends |
| `timing.transient_frames` | Candidate positive RMS rises, at least 100 ms apart; not semantic contacts |
| `timing.contact_seconds` | `null`: actual sword/body contact has not been listening/animation annotated |

Activity uses the maximum channel RMS with a threshold of the louder of -60 dBFS
and 42 dB below the clip's loudest RMS window. The active window resolution is
5 ms. This relative definition allows comparison across quiet and loud recordings;
it is not a guarantee that everything below the threshold is inaudible. Metadata
is measured on delivered audio after PCM quantization or Vorbis decoding.

## Godot use

```gdscript
const SOUND_CATALOG: GameSoundCatalog = preload("res://content/audio/catalog.tres")

func assign_sword_sound(player: AudioStreamPlayer3D) -> void:
    var choices: Array[GameSoundClip] = SOUND_CATALOG.variants(&"sword_metal_slide")
    var clip: GameSoundClip = choices[randi_range(0, choices.size() - 1)]
    player.stream = clip.stream
    player.play()
```

`find_clip(&"sword_metal_slide_01")` provides stable-ID lookup. Use confirmed gameplay
events to choose when to play. Do not treat an audio peak as authoritative hit timing.
The example is usage guidance; gameplay does not yet play these sounds.

## Regeneration and verification

Install `numpy` in your Python environment and `ffmpeg` and `vorbis-tools` (`oggenc`)
on PATH. Build from the original downloaded bundle, not the local symlink shortlist:

```sh
python3 scripts/build_audio_catalog.py --source-root "/path/to/Sonniss.com-GDC2026-GameAudioBundle"
python3 -m unittest discover -s tests -p test_audio_catalog.py -v
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script tests/audio_catalog_test.gd
python3 scripts/smoke_test.py "$GODOT"
```

The builder verifies source hashes and expected split counts before accepting
clips. Fixed Vorbis serial numbers allow repeat builds to reproduce output bytes
with the same tool versions. The Python check validates every delivered audio file,
hash, source range, headroom and timing marker, and rejects orphan clips. Godot checks
actual imported streams, lengths, disabled loops and variant lookup. Keep generated
`.import` sidecars and script `.uid` files; never commit `.godot/`.

## Provenance

The original bundled license is preserved at
`content/audio/licenses/License - GDC Game Audio.pdf`, with the vendor README beside
it. The source collection is [Sonniss GameAudioGDC](https://gdc.sonniss.com/). Its license permits personal
and commercial project use and modification without attribution, retains creators'
copyright, disallows selling the effects as standalone sounds, and prohibits using
them to develop/train/enhance AI technologies. These files are curated assets for
this game, not a standalone sound-pack release. WAV/OGG files use the repository's
existing Git LFS rules.
