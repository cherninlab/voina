#!/usr/bin/env python3
"""Build the curated Sonniss clips. Requires numpy, ffmpeg, ffprobe and oggenc.

python3 scripts/build_audio_catalog.py --source-root /path/to/Sonniss-bundle
Source windows and review decisions live in content/audio/sources.json.
No inference model or external audio service is used.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
import wave
from pathlib import Path
from urllib.parse import quote

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
HOP = 240  # Non-overlapping 5 ms RMS windows; timing resolution is explicit.


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def probe(path: Path) -> dict:
    return json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries',
        'stream=sample_rate,channels:format=duration', '-of', 'json', str(path)]))


def decode(path: Path, channels: int) -> np.ndarray:
    data = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', str(path), '-map', '0:a:0',
        '-ac', str(channels), '-ar', str(RATE), '-f', 'f32le', '-'])
    return np.frombuffer(data, dtype='<f4').reshape(-1, channels).copy()


def rms_envelope(audio: np.ndarray) -> np.ndarray:
    """Maximum channel RMS avoids stereo phase cancellation in the detector."""
    padded = np.pad(audio, ((0, (-len(audio)) % HOP), (0, 0)))
    return np.sqrt(np.mean(padded.reshape(-1, HOP, audio.shape[1]) ** 2,
                           axis=1)).max(axis=1)


def dbfs(value: float | np.ndarray) -> float | np.ndarray:
    return 20.0 * np.log10(np.maximum(value, 1e-9))


def activity_regions(audio: np.ndarray, gate: float, gap: float) -> list[tuple[int, int]]:
    """Return half-open frame ranges; bridge only the configured silence gap."""
    active = np.flatnonzero(dbfs(rms_envelope(audio)) > gate)
    groups: list[list[int]] = []
    for index in active:
        start, end = int(index) * HOP, min((int(index) + 1) * HOP, len(audio))
        if groups and start - groups[-1][1] < round(gap * RATE):
            groups[-1][1] = end
        else:
            groups.append([start, end])
    # Reject isolated noise ticks, not quiet tails belonging to a real take.
    return [(a, b) for a, b in groups if b - a >= round(.025 * RATE)]


def trim_window(audio: np.ndarray, start: int, end: int, gate: float) -> tuple[int, int]:
    active = np.flatnonzero(dbfs(rms_envelope(audio[start:end])) > gate)
    if not len(active):
        raise ValueError(f'Empty/silent source window: {start}:{end}')
    # Pre-roll protects attacks, post-roll retains decays below the RMS gate.
    first = max(start, start + int(active[0]) * HOP - round(.015 * RATE))
    last = min(end, start + (int(active[-1]) + 1) * HOP + round(.060 * RATE))
    return first, last


def source_segments(audio: np.ndarray, spec: dict) -> list[tuple[int, int]]:
    mode = spec['mode']
    if mode == 'continuous':
        return [(0, len(audio))]
    if mode == 'windows':
        windows = [(round(a * RATE), min(round(b * RATE), len(audio)))
                   for a, b in spec['windows_seconds']]
    elif mode == 'silence':
        regions = activity_regions(audio, spec['split_gate_dbfs'], spec['split_gap_seconds'])
        # Bound every take at the midpoint of its quiet gap. A ringing tail may
        # extend beyond the segmentation gate, but must not reach the next take.
        cuts = [0] + [(a[1] + b[0]) // 2 for a, b in zip(regions, regions[1:])] + [len(audio)]
        windows = list(zip(cuts, cuts[1:])) if regions else []
    elif mode == 'single':
        windows = [(0, len(audio))]
    else:
        raise ValueError(f'Unknown segmentation mode: {mode}')
    previous_end = 0
    for start, end in windows:
        if not 0 <= previous_end <= start < end <= len(audio):
            raise ValueError(f'Overlapping/out-of-bounds windows for {spec["id"]}')
        previous_end = end
    result = [trim_window(audio, a, b, spec['trim_gate_dbfs']) for a, b in windows]
    if len(result) != spec['expected_clips']:
        raise ValueError(f'{spec["id"]}: expected {spec["expected_clips"]} clips, got {len(result)}')
    return result


def timing(audio: np.ndarray) -> dict:
    rms = rms_envelope(audio)
    levels = dbfs(rms)
    gate = max(-60.0, float(levels.max()) - 42.0)
    active = np.flatnonzero(levels > gate)
    if not len(active):
        raise ValueError('Silent output clip')
    onset = int(active[0]) * HOP
    end = min(len(audio), (int(active[-1]) + 1) * HOP)
    peak = min(len(audio) - 1, int(np.argmax(rms)) * HOP + HOP // 2)
    amplitude_peak = int(np.argmax(np.abs(audio).max(axis=1)))
    # Positive RMS changes over 10 ms. These are candidate transients, not
    # semantic annotations such as "blade contact" or "left foot".
    rises = levels - np.concatenate([levels[:2], levels[:-2]])
    candidates = [i for i in range(2, len(rms) - 1)
                  if rises[i] >= 6 and rises[i] >= rises[i-1] and rises[i] >= rises[i+1]
                  and levels[i] >= max(-55.0, float(levels.max()) - 30.0)]
    chosen: list[int] = []
    for i in sorted(candidates, key=lambda j: float(rises[j]), reverse=True):
        if all(abs(i-j) * HOP >= .1 * RATE for j in chosen):
            chosen.append(i)
    frames = sorted(i * HOP for i in chosen)
    return {'onset_frame': onset, 'active_end_frame': end,
            'energy_peak_frame': peak, 'amplitude_peak_frame': amplitude_peak,
            'onset_seconds': onset / RATE, 'active_end_seconds': end / RATE,
            'energy_peak_seconds': peak / RATE, 'amplitude_peak_seconds': amplitude_peak / RATE,
            'attack_seconds': (peak - onset) / RATE, 'decay_seconds': (end - peak) / RATE,
            'tail_seconds': (len(audio) - end) / RATE,
            'transient_frames': frames, 'transient_seconds': [f / RATE for f in frames],
            'activity_gate_dbfs': round(gate, 3), 'resolution_seconds': HOP / RATE,
            'contact_seconds': None}


def write_audio(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.rint(np.clip(audio, -1, 1) * 32767).astype('<i2')
    if path.suffix == '.wav':
        with wave.open(str(path), 'wb') as output:
            output.setnchannels(audio.shape[1])
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(pcm.tobytes())
        # Godot's default WAV import may apply QOA compression. Preserve PCM and
        # exact frame markers instead, while retaining any editor-generated UID.
        sidecar = path.with_suffix('.wav.import')
        config = sidecar.read_text() if sidecar.exists() else (
            '[remap]\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n'
            'edit/trim=false\nedit/normalize=false\ncompress/mode=0\n')
        config = re.sub(r'^compress/mode=.*$', 'compress/mode=0', config, flags=re.MULTILINE)
        sidecar.write_text(config)
    else:
        # Fix the Ogg serial number so repeated builds produce identical bytes.
        serial = int(hashlib.sha256(path.stem.encode()).hexdigest()[:7], 16)
        subprocess.run(['oggenc', '--quiet', '--raw', '--raw-bits', '16',
                        '--raw-chan', str(audio.shape[1]), '--raw-rate', str(RATE),
                        '--raw-endianness', '0', '--serial', str(serial),
                        '--quality', '5', '--output', str(path), '-'],
                       input=pcm.tobytes(), check=True)


def export_resource(output: Path, clips: list[dict]) -> None:
    """A .tres database references every audio asset for Godot export discovery."""
    q = json.dumps
    lines = [f'[gd_resource type="Resource" script_class="GameSoundCatalog" load_steps={len(clips)*2+3} format=3]',
             '', '[ext_resource type="Script" path="res://content/audio/sound_catalog.gd" id="1"]',
             '[ext_resource type="Script" path="res://content/audio/sound_clip.gd" id="2"]']
    for i, clip in enumerate(clips, 3):
        lines.append(f'[ext_resource type="AudioStream" path={q(clip["path"])} id="a{i}"]')
    for i, clip in enumerate(clips, 3):
        t = clip['timing']
        lines.extend(['', f'[sub_resource type="Resource" id="c{i}"]', 'script = ExtResource("2")'])
        values = {k: clip[k] for k in ('id', 'family', 'category', 'sample_rate', 'frame_count',
                                     'duration_seconds', 'source_gain_db', 'notes')}
        values.update({k: t[k] for k in ('onset_frame', 'energy_peak_frame', 'amplitude_peak_frame', 'active_end_frame')})
        values.update(source_path=clip['source']['relative_path'], source_sha256=clip['source']['sha256'],
                      source_start_frame=clip['source']['start_frame'], source_end_frame=clip['source']['end_frame'])
        lines.extend(f'{key} = {q(value)}' for key, value in values.items())
        lines.extend([f'stream = ExtResource("a{i}")',
                      'tags = PackedStringArray(' + ', '.join(q(tag) for tag in clip['tags']) + ')',
                      'transient_frames = PackedInt32Array(' + ', '.join(map(str, t['transient_frames'])) + ')'])
    lines.extend(['', '[resource]', 'script = ExtResource("1")',
                  'clips = Array[ExtResource("2")]([' + ', '.join(f'SubResource("c{i}")' for i in range(3, len(clips)+3)) + '])', ''])
    (output / 'catalog.tres').write_text('\n'.join(lines))


def export_audition(output: Path, clips: list[dict]) -> None:
    esc = html.escape
    parts = ['''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Game audio catalog</title>
<style>body{font:16px system-ui;background:#131a17;color:#dfe8e1;max-width:1000px;margin:36px auto;padding:0 20px}
p{line-height:1.5}article{background:#202c25;padding:18px;margin:14px 0;border-radius:12px}small{color:#b6c5bc}
audio,input{width:100%;box-sizing:border-box}audio{margin:12px 0}input{padding:12px;font:inherit}
svg{width:100%;height:70px;background:#111a15}h3{margin:0 0 8px}details{overflow-wrap:anywhere}a{color:#b9ddaf}</style>
<h1>Game audio catalog</h1><p>Separate variants with measured timing. Waveform-reviewed; listening and in-game mix acceptance remain pending.
Green: onset. Gold: strongest 5 ms energy window. Pink: end of measured activity. These are not verified weapon-contact markers.
Ambiences are not certified seamless loops. Footsteps are flip-flops, not boots.</p>
<input id="search" aria-label="Filter sounds" placeholder="Filter: sword, gore, footstep, ambience...">''']
    for c in clips:
        t = c['timing']; n = c['frame_count']
        points = ' '.join(f'{i*1000/127:.1f},{65-v*60:.1f}' for i, v in enumerate(c['waveform_preview']))
        markers = ''.join(f'<line x1="{t[key]/n*1000:.2f}" x2="{t[key]/n*1000:.2f}" y1="0" y2="70" stroke="{color}"/>'
                          for key, color in [('onset_frame','#76cf91'),('energy_peak_frame','#edc960'),('active_end_frame','#e18499')])
        url = quote(c['path'].removeprefix('res://content/audio/'))
        parts.append(f'''<article data-search="{esc(' '.join([c['id'], c['label'], *c['tags']]).lower())}">
<h3>{esc(c['id'])}</h3><small>{esc(c['label'])} · {c['duration_seconds']:.3f} s · {c['channels']} channel(s)</small>
<p>Onset {t['onset_seconds']:.3f}s · Energy peak {t['energy_peak_seconds']:.3f}s · Active end {t['active_end_seconds']:.3f}s</p>
<svg viewBox="0 0 1000 70" preserveAspectRatio="none" aria-label="Waveform envelope"><polyline fill="none" stroke="#829d8b" points="{points}"/>{markers}</svg>
<audio controls preload="none" src="{url}"></audio><p>{esc(c['notes'])}</p>
<details><summary>Original recording and cut</summary><p>{esc(c['source']['relative_path'])}<br>
Source interval: {c['source']['start_seconds']:.3f}–{c['source']['end_seconds']:.3f}s (end exclusive).</p></details></article>''')
    parts.append('''<script>document.querySelectorAll('audio').forEach(a=>a.addEventListener('play',()=>document.querySelectorAll('audio').forEach(b=>{if(a!==b)b.pause()})));
document.getElementById('search').addEventListener('input',e=>document.querySelectorAll('article').forEach(a=>{a.hidden=!a.dataset.search.includes(e.target.value.toLowerCase())}));</script></html>''')
    (output / 'audition.html').write_text('\n'.join(parts))


def build(source_root: Path, output: Path) -> None:
    manifest = json.loads((output / 'sources.json').read_text())
    clips: list[dict] = []
    for spec in manifest['sources']:
        path = source_root / spec['relative_path']
        if sha256(path) != spec['sha256']:
            raise ValueError(f'Source hash mismatch: {path}')
        info = probe(path)['streams'][0]
        channels = 2 if spec['mode'] == 'continuous' else 1
        audio = decode(path, channels)
        source_peak = float(np.abs(audio).max())
        gain_db = min(0.0, -3.0 - float(dbfs(source_peak)))
        segments = source_segments(audio, spec)
        for index, (start, end) in enumerate(segments, 1):
            clip_id = f'{spec["id"]}_{index:02d}'
            suffix = '.ogg' if spec['mode'] == 'continuous' else '.wav'
            relative = Path('clips') / spec['category'] / (clip_id + suffix)
            clip_audio = audio[start:end].copy() * (10 ** (gain_db / 20))
            fade_in = min(round(.001 * RATE), len(clip_audio) // 4)
            fade_out = min(round(.012 * RATE), len(clip_audio) // 4)
            clip_audio[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
            clip_audio[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
            write_audio(output / relative, clip_audio)
            # Analyze the delivered audio, including Vorbis decode differences.
            delivered = decode(output / relative, channels)
            if abs(len(delivered) - len(clip_audio)) > 1:
                raise ValueError(f'Encoder changed timeline: {clip_id}')
            rms = rms_envelope(delivered)
            preview = [round(float(chunk.max()) / max(float(rms.max()), 1e-9), 4)
                       for chunk in np.array_split(np.pad(rms, (0, max(0,128-len(rms)))), 128)]
            clips.append({'id': clip_id, 'family': spec['id'], 'label': spec['label'],
                          'category': spec['category'], 'tags': spec['tags'],
                          'path': 'res://content/audio/' + relative.as_posix(),
                          'sha256': sha256(output / relative), 'sample_rate': RATE,
                          'channels': channels, 'frame_count': len(delivered),
                          'duration_seconds': len(delivered) / RATE,
                          'source_gain_db': round(gain_db, 6),
                          'peak_dbfs': round(float(dbfs(float(np.abs(delivered).max()))), 3),
                          'rms_dbfs': round(float(dbfs(float(np.sqrt(np.mean(delivered**2))))), 3),
                          'fade_in_frames': fade_in, 'fade_out_frames': fade_out,
                          'loop_verified': False, 'audition_status': spec['audition_status'],
                          'notes': spec['notes'], 'timing': timing(delivered),
                          'waveform_preview': preview,
                          'source': {'relative_path': spec['relative_path'], 'sha256': spec['sha256'],
                                     'original_sample_rate': int(info['sample_rate']),
                                     'original_channels': int(info['channels']),
                                     'decoded_sample_rate': RATE, 'decoded_frame_count': len(audio),
                                     'start_frame': start, 'end_frame': end,
                                     'start_seconds': start / RATE, 'end_seconds': end / RATE,
                                     'original_start_frame': round(start * int(info['sample_rate']) / RATE),
                                     'original_end_frame': round(end * int(info['sample_rate']) / RATE)}})
        print(f'{spec["id"]}: {len(segments)} clip(s)', flush=True)
    catalog = {'schema_version': 1, 'sample_rate': RATE,
               'build_tools': {'numpy': np.__version__,
                               'ffmpeg': subprocess.check_output(['ffmpeg', '-version'], text=True).splitlines()[0],
                               'oggenc': subprocess.check_output(['oggenc', '--version'], text=True).strip()},
               'license': manifest['license'], 'source_url': manifest['source_url'],
               'timing_convention': 'Half-open frame intervals at 48000 Hz. Onset/active-end use 5ms RMS; peaks and rises are measurements, not semantic contact labels.',
               'source_count': len(manifest['sources']), 'clip_count': len(clips), 'clips': clips}
    (output / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
    export_resource(output, clips)
    export_audition(output, clips)
    print(f'Built {len(clips)} clips from {len(manifest["sources"])} recordings.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'content/audio')
    args = parser.parse_args()
    build(args.source_root, args.output)
