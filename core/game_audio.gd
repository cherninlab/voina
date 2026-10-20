class_name GameAudio
extends Node
## Plays catalog sounds for confirmed gameplay events. Autoloaded as /root/Audio; gameplay calls
## the static helpers, which do nothing when the autoload is absent (--script tests) or disabled
## (headless/dedicated). Sounds are presentation only and never feed back into combat.
##
## Events already replicated to every peer (attack_effect, hit_feedback, slashed...) call play().
## Host-only events (deaths) call broadcast(), which plays on the host and relays to clients.

const CATALOG: GameSoundCatalog = preload("res://content/audio/catalog.tres")
const POOL_SIZE: int = 24
const AMBIENCE_FADE: float = 4.0

## event -> layers. Each layer plays one random variant from its families (or its listed `clips`),
## at volume_db. `start` skips a clip's lead-in: "peak" starts just before its loudest instant (walk
## recordings lead into the footfall), "impact" just before its first transient (punch takes open
## with 60-110 ms of handling noise, which made hits trail the blow).
## `pitch` is the +/- random pitch spread (default 0.06); a wide spread varies a family with one take.
## `lowpass_hz` routes the layer through a low-pass bus; punch and flip-flop takes are clicky.
## Levels follow playtests: punches down, sword metal well up (its takes are quiet).
## Only the female death vocal is used: the male take is a long creature roar.
const EVENTS: Dictionary[StringName, Array] = {
	&"swing": [{"families": [&"blade_swing_scrape"], "volume_db": 0.0, "pitch": 0.14}],
	&"hit": [{"families": [&"body_punch"], "volume_db": -6.0, "lowpass_hz": 700.0, "start": "impact"}],
	&"block": [{"families": [&"sword_metal_slide"], "volume_db": 14.0}],
	&"parry": [{"families": [&"sword_metal_slide"], "volume_db": 16.0}, {"families": [&"metal_tap"], "volume_db": 4.0}],
	&"dash": [{"families": [&"cloth_24", &"cloth_29"], "volume_db": -8.0}],
	# Only takes 06 and 07: the other flip-flop footfalls carry extra sandal clicks.
	&"footstep": [{"families": [&"footstep_grass_flipflop"], "clips": [&"footstep_grass_flipflop_06", &"footstep_grass_flipflop_07"], "volume_db": -10.0, "start": "peak", "lowpass_hz": 1600.0}],
	&"mob_shove": [{"families": [&"body_punch"], "volume_db": -12.0, "lowpass_hz": 700.0, "start": "impact"}],
	&"mob_slash": [{"families": [&"gore_heavy"], "volume_db": -6.0}, {"families": [&"body_punch"], "volume_db": -10.0, "lowpass_hz": 700.0, "start": "impact"}],
	&"mob_bisect": [{"families": [&"gore_heavy"], "volume_db": 0.0, "pitch": 0.1}, {"families": [&"blood_light"], "volume_db": -4.0, "lowpass_hz": 4000.0}, {"families": [&"body_punch"], "volume_db": -8.0, "lowpass_hz": 700.0, "start": "impact"}],
	&"death_female": [{"families": [&"death_female"], "volume_db": -2.0}],
}
## Non-positional beds, crossfaded at their ends because no ambience is a verified loop.
const AMBIENCE: Dictionary[StringName, float] = {&"meadow_01": -6.0, &"forest_01": -14.0}
## Fade applied when a clip starts mid-recording (`from_peak`), so the cut does not click.
const OFFSET_FADE: float = 0.02
## Background playlist toggled with the `music_toggle` key (P): plays in order and wraps around.
## Paths, loaded on demand so headless runs never decode them.
const MUSIC: Array[String] = [
	"res://content/audio/music/beneath-my-own-design-track-1.ogg",
	"res://content/audio/music/beneath-my-own-design-track-2.ogg",
]
const MUSIC_DB: float = 0.0 # loud: Mike asked for the playlist at full level (T-114)

var enabled: bool = false
var pool: Array[AudioStreamPlayer3D] = []
var next_voice: int = 0
var last_pick: Dictionary[StringName, StringName] = {}
var beds: Array[Dictionary] = []
var fades: Dictionary[AudioStreamPlayer3D, Tween] = {}
var music: AudioStreamPlayer
var music_track: int = 0

static func instance() -> GameAudio:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var node: GameAudio = tree.root.get_node_or_null(^"Audio") as GameAudio
	return node if node != null and node.enabled else null

## Plays locally; call from code that already runs on every peer.
static func play(event: StringName, at: Vector3) -> void:
	var audio: GameAudio = instance()
	if audio != null:
		audio.play_event(event, at)

## Host-only events: plays on the host and relays to every client.
static func broadcast(event: StringName, at: Vector3) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var node: GameAudio = tree.root.get_node_or_null(^"Audio") as GameAudio if tree != null else null
	if node == null or not node.multiplayer.is_server():
		return
	if node.enabled:
		node.play_event(event, at)
	if node.multiplayer.has_multiplayer_peer() and node.multiplayer.get_peers().size() > 0:
		node.relay.rpc(event, at)

## True while the P-key playlist is playing; the title menu keeps its own theme quiet then.
static func music_playing() -> bool:
	var audio: GameAudio = instance()
	return audio != null and audio.music.playing

func _ready() -> void:
	set_multiplayer_authority(1)
	enabled = DisplayServer.get_name() != "headless" and not "--server" in OS.get_cmdline_user_args()
	if enabled:
		setup()
		for id: StringName in AMBIENCE:
			start_bed(id, AMBIENCE[id])

func setup() -> void:
	enabled = true
	for index: int in range(POOL_SIZE):
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.unit_size = 6.0
		voice.max_distance = 60.0
		voice.max_db = 24.0 # the default +3 dB cap would clip the quiet sword-metal boosts
		voice.attenuation_filter_cutoff_hz = 9000.0
		add_child(voice)
		pool.append(voice)
	music = AudioStreamPlayer.new()
	music.volume_db = MUSIC_DB
	music.finished.connect(next_track)
	add_child(music)

func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed(&"music_toggle"):
		toggle_music()
		get_viewport().set_input_as_handled()

## Starts the current track from the top, or stops it (stop() does not emit `finished`).
func toggle_music() -> void:
	if music.playing:
		music.stop()
		return
	music.stream = load(MUSIC[music_track]) as AudioStream
	music.play()

func next_track() -> void:
	music_track = (music_track + 1) % MUSIC.size()
	music.stream = load(MUSIC[music_track]) as AudioStream
	music.play()

@rpc("authority", "call_remote", "reliable")
func relay(event: StringName, at: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not at.is_finite():
		return
	if enabled:
		play_event(event, at)

func play_event(event: StringName, at: Vector3) -> int:
	if not EVENTS.has(event) or not at.is_finite():
		return 0
	var started: int = 0
	for layer: Dictionary in EVENTS[event]:
		var clip: GameSoundClip = pick(layer["families"] as Array, layer.get("clips", []) as Array)
		if clip == null:
			continue
		var voice: AudioStreamPlayer3D = take_voice()
		voice.stream = clip.stream
		voice.global_position = at
		voice.bus = lowpass_bus(float(layer["lowpass_hz"])) if layer.has("lowpass_hz") else &"Master"
		var volume_db: float = float(layer["volume_db"]) + randf_range(-1.5, 1.5)
		var spread: float = float(layer.get("pitch", 0.06))
		voice.pitch_scale = randf_range(1.0 - spread, 1.0 + spread)
		var offset: float = start_offset(clip, String(layer.get("start", "")))
		if fades.has(voice):
			fades[voice].kill()
			fades.erase(voice)
		voice.volume_db = volume_db if offset <= 0.0 else -40.0
		voice.play(offset)
		if offset > 0.0:
			fades[voice] = create_tween()
			fades[voice].tween_property(voice, "volume_db", volume_db, OFFSET_FADE)
		started += 1
	return started

## A bus named after its cutoff, created on first use and sent to Master.
func lowpass_bus(cutoff_hz: float) -> StringName:
	var bus_name: StringName = StringName("Lowpass%d" % int(cutoff_hz))
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")
		var filter: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		filter.cutoff_hz = cutoff_hz
		AudioServer.add_bus_effect(index, filter)
	return bus_name

func start_offset(clip: GameSoundClip, start: String) -> float:
	var sample_rate: float = float(clip.sample_rate)
	if start == "peak":
		return maxf(0.0, clip.energy_peak_seconds() - 0.08)
	if start == "impact" and not clip.transient_frames.is_empty():
		return maxf(0.0, float(clip.transient_frames[0]) / sample_rate - 0.01)
	return 0.0

## Random variant across the families (or only the listed clip ids), never the same clip twice
## in a row for one layer.
func pick(families: Array, ids: Array = []) -> GameSoundClip:
	var choices: Array[GameSoundClip] = []
	for id: StringName in ids:
		var listed: GameSoundClip = CATALOG.find_clip(id)
		if listed != null:
			choices.append(listed)
	if ids.is_empty():
		for family: StringName in families:
			choices.append_array(CATALOG.variants(family))
	if choices.is_empty():
		return null
	var key: StringName = families[0]
	var clip: GameSoundClip = choices.pick_random()
	if choices.size() > 1 and last_pick.get(key, &"") == clip.id:
		clip = choices[(choices.find(clip) + randi_range(1, choices.size() - 1)) % choices.size()]
	last_pick[key] = clip.id
	return clip

## The first idle voice, otherwise the one started longest ago.
func take_voice() -> AudioStreamPlayer3D:
	for offset: int in range(pool.size()):
		var voice: AudioStreamPlayer3D = pool[(next_voice + offset) % pool.size()]
		if not voice.playing:
			next_voice = (next_voice + offset + 1) % pool.size()
			return voice
	var oldest: AudioStreamPlayer3D = pool[next_voice]
	next_voice = (next_voice + 1) % pool.size()
	oldest.stop()
	return oldest

func start_bed(id: StringName, volume_db: float) -> void:
	var clip: GameSoundClip = CATALOG.find_clip(id)
	if clip == null:
		return
	var players: Array[AudioStreamPlayer] = []
	for index: int in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = clip.stream
		player.volume_db = -80.0
		add_child(player)
		players.append(player)
	var bed: Dictionary = {"players": players, "volume_db": volume_db, "active": 0, "length": clip.duration_seconds}
	beds.append(bed)
	# Start each bed somewhere inside the recording so sessions do not all open identically.
	fade_in(players[0], volume_db, randf_range(0.0, maxf(0.0, clip.duration_seconds - AMBIENCE_FADE * 4.0)))

func fade_in(player: AudioStreamPlayer, volume_db: float, from: float) -> void:
	player.volume_db = -60.0
	player.play(from)
	create_tween().tween_property(player, "volume_db", volume_db, AMBIENCE_FADE)

func _process(_delta: float) -> void:
	for bed: Dictionary in beds:
		var players: Array[AudioStreamPlayer] = bed["players"]
		var current: AudioStreamPlayer = players[int(bed["active"])]
		if current.playing and current.get_playback_position() < float(bed["length"]) - AMBIENCE_FADE:
			continue
		var next: int = 1 - int(bed["active"])
		bed["active"] = next
		fade_in(players[next], float(bed["volume_db"]), 0.0)
		if current.playing:
			var fade: Tween = create_tween()
			fade.tween_property(current, "volume_db", -60.0, AMBIENCE_FADE)
			fade.tween_callback(current.stop)
