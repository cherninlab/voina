"""Signal-boundary regression tests and validation of the shipped audio database.

Run with: python3 -m unittest discover -s tests -p test_audio_catalog.py -v
Requires the same numpy/ffmpeg dependencies as the builder.
"""
import importlib.util
import json
from pathlib import Path
import unittest
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('audio_builder', ROOT / 'scripts/build_audio_catalog.py')
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class SegmentationTest(unittest.TestCase):
    def test_separate_takes_and_retain_quiet_tail(self) -> None:
        audio = np.zeros((48000 * 3, 1), dtype=np.float32)
        audio[4800:9600] = .3
        audio[9600:16000] = .0005  # Below split gate, above trim gate.
        audio[96000:110000] = .2
        spec = {'id': 'fixture', 'mode': 'silence', 'split_gate_dbfs': -60,
                'split_gap_seconds': .3, 'trim_gate_dbfs': -70, 'expected_clips': 2}
        cuts = builder.source_segments(audio, spec)
        self.assertEqual(len(cuts), 2)
        self.assertLess(cuts[0][0], 4800)
        self.assertGreaterEqual(cuts[0][1], 16000)
        self.assertLess(cuts[0][1], cuts[1][0])

    def test_stereo_antiphase_is_not_silence(self) -> None:
        audio = np.zeros((48000, 2), dtype=np.float32)
        audio[10000:20000] = [.1, -.1]
        self.assertEqual(len(builder.activity_regions(audio, -60, .1)), 1)

    def test_short_pause_inside_take_is_not_a_new_sample(self) -> None:
        audio = np.zeros((48000, 1), dtype=np.float32)
        audio[2000:8000] = .1
        audio[10000:16000] = .1
        self.assertEqual(len(builder.activity_regions(audio, -60, .1)), 1)

    def test_silence_and_overlapping_windows_fail(self) -> None:
        with self.assertRaises(ValueError):
            builder.timing(np.zeros((48000, 1), dtype=np.float32))
        with self.assertRaises(ValueError):
            builder.source_segments(np.ones((48000, 1), dtype=np.float32),
                                    {'id': 'bad', 'mode': 'windows', 'windows_seconds': [[0,.6],[.5,1]]})


class ShippedCatalogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.output = ROOT / 'content/audio'
        cls.catalog = json.loads((cls.output / 'catalog.json').read_text())
        cls.manifest = json.loads((cls.output / 'sources.json').read_text())

    def test_counts_unique_ids_source_provenance_and_nonoverlap(self) -> None:
        clips = self.catalog['clips']
        self.assertEqual(len(clips), self.catalog['clip_count'])
        self.assertEqual(len({c['id'] for c in clips}), len(clips))
        self.assertEqual(len(self.manifest['sources']), 29)
        for source in self.manifest['sources']:
            variants = [c for c in clips if c['family'] == source['id']]
            self.assertEqual(len(variants), source['expected_clips'], source['id'])
            previous_end = 0
            for clip in variants:
                original = clip['source']
                self.assertEqual(original['sha256'], source['sha256'])
                self.assertEqual(original['relative_path'], source['relative_path'])
                self.assertGreaterEqual(original['start_frame'], previous_end)
                self.assertLess(original['start_frame'], original['end_frame'])
                self.assertLessEqual(original['end_frame'], original['decoded_frame_count'])
                self.assertEqual(original['end_frame'] - original['start_frame'], clip['frame_count'])
                previous_end = original['end_frame']

    def test_every_delivered_file_and_timing_marker(self) -> None:
        referenced = set()
        for c in self.catalog['clips']:
            with self.subTest(clip=c['id']):
                path = ROOT / c['path'].removeprefix('res://')
                referenced.add(path)
                self.assertEqual(builder.sha256(path), c['sha256'])
                audio = builder.decode(path, c['channels'])
                self.assertEqual(len(audio), c['frame_count'])
                self.assertTrue(np.isfinite(audio).all())
                self.assertLess(float(np.abs(audio).max()), .95, 'Keep headroom after codec decode')
                self.assertGreater(float(np.abs(audio).max()), .0001)
                t = c['timing']
                self.assertGreaterEqual(t['onset_frame'], 0)
                self.assertLessEqual(t['onset_frame'], t['energy_peak_frame'])
                self.assertLess(t['energy_peak_frame'], t['active_end_frame'])
                self.assertLessEqual(t['active_end_frame'], len(audio))
                self.assertEqual(t, builder.timing(audio))
                self.assertIsNone(t['contact_seconds'])
                self.assertFalse(c['loop_verified'])
                self.assertTrue(all(0 <= f < len(audio) for f in t['transient_frames']))
                self.assertEqual(len(c['waveform_preview']), 128)
                if path.suffix == '.wav':
                    with wave.open(str(path)) as wav:
                        self.assertEqual((wav.getframerate(), wav.getsampwidth(), wav.getnchannels()), (48000, 2, 1))
                    self.assertEqual(float(audio[0, 0]), 0)
                    self.assertEqual(float(audio[-1, 0]), 0)
        actual = {p for p in (self.output / 'clips').rglob('*') if p.suffix in ('.wav', '.ogg')}
        self.assertEqual(actual, referenced, 'No stale/orphan audio after regeneration')


if __name__ == '__main__':
    unittest.main()
