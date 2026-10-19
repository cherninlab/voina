# Prepared game audio

`content/audio/catalog.tres` is the Godot sound database. Each `GameSoundClip`
references its imported `AudioStream`, so the catalog and its audio dependencies
can be included in an exported game by referencing the resource. Gameplay plays it
through the `Audio` autoload (`core/game_audio.gd`, see [Playback](#playback)).

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

## Playback

`core/game_audio.gd` (class `GameAudio`, autoloaded as `/root/Audio`) maps gameplay
events to catalog families in `GameAudio.EVENTS`. Each event has one or more layers;
each layer plays a random variant (never the same clip twice in a row) from a pool of
24 positional `AudioStreamPlayer3D` voices, with ±1.5 dB and ±6 % pitch jitter (per-layer override). `max_db` is raised to
+24 dB because the sword-metal takes need large boosts. The
oldest voice is reused when all are busy.

| Event | Trigger | Layers |
| --- | --- | --- |
| `swing` | `attack_effect` (host-approved melee, every peer) | `blade_swing_scrape` with ±14 % pitch |
| `hit` / `block` / `parry` | `hit_feedback` on the defender | `body_punch` (from its first transient, low-passed at 700 Hz) / `sword_metal_slide` / `sword_metal_slide` + `metal_tap` |
| `dash` | `dash_effect` | `cloth_24` or `cloth_29` |
| `footstep` | `CharacterVisual` foot plant | `footstep_grass_flipflop_06`/`_07` only (others click), started 80 ms before the energy peak with a 20 ms fade-in, low-passed at 1.6 kHz |
| `mob_shove` / `mob_slash` | `HostileMob.kicked` with blade speed / `slashed` | `body_punch` / `gore_heavy` + `body_punch` |
| `mob_bisect` | `HostileMob.bisected` | `gore_heavy` + `blood_light` + `body_punch` |
| `death_female` | host-only `died` of the female-rig player | `death_female` |

Events that already run on every peer call `GameAudio.play(event, position)`.
Host-only events call `GameAudio.broadcast`, which plays on the host and relays an
authority-only RPC that clients accept only from peer 1. Sound never affects combat.
Punch, footstep and blood layers go through low-pass buses (`Lowpass700`, `Lowpass1600`, `Lowpass4000`),
created at runtime, because the takes are clicky in game. `meadow_01` (−6 dB) and
`forest_01` (−14 dB) play as non-positional beds, crossfaded over 4 s at the
end of each pass because no ambience is a verified loop.

The autoload is disabled headless and with `--server`, so tests and dedicated servers
stay silent; the static helpers are no-ops when it is absent or disabled (including
`--script` runs, which do not load autoloads). `tests/game_audio_test.gd` checks every
event family resolves, no-repeat picking, and pool reuse. Levels were retuned after one playtest:
punches lowered and low-passed, footsteps softened, sword metal raised, gore
added to bisection, ambience raised 10 dB, and the male creature vocal dropped (it
repeated on every raider death). Swings use the single blade-scrape take.
Punch takes open with 60–110 ms of handling noise, so they start 10 ms before their
first transient. Raiders hold their idle pose until `WINDUP - JAB_CONTACT` (0.31 s)
so `Punch_Jab`'s fist is fully extended (0.19 s into the clip) when the host strike
lands at 0.5 s; combat timing is unchanged.

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

## Menu music

The user-supplied `content/audio/music/secha-menu-theme.mp3` loops locally at -10 dB while offline in the title, host/join setup or Settings. It stops on hosting/joining and restarts on return to the lobby. It never runs on headless/dedicated servers. See the music directory README for source provenance. The original MP3 is preserved without transcoding.
