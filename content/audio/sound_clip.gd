class_name GameSoundClip
extends Resource
## A prepared audio variant. Frame markers use the 48 kHz decoded timeline.
## Energy peaks are waveform measurements, not verified weapon contact times.

@export var id: StringName
@export var family: StringName
@export var category: StringName
@export var tags: PackedStringArray
@export var stream: AudioStream
@export var sample_rate: int = 48000
@export var frame_count: int
@export var duration_seconds: float
@export var onset_frame: int
@export var energy_peak_frame: int
@export var amplitude_peak_frame: int
@export var active_end_frame: int
@export var transient_frames: PackedInt32Array
@export var source_path: String
@export var source_sha256: String
@export var source_start_frame: int
@export var source_end_frame: int
@export var source_gain_db: float
@export var loop_verified: bool = false
@export var notes: String

func energy_peak_seconds() -> float:
	return float(energy_peak_frame) / float(sample_rate)
