extends CanvasLayer

# Owns the MPEG datamosh effect (ui/datamosh_effect.gd): attaches it to whichever camera is
# current, and decides when to mosh from what the local player goes through. Local
# presentation only; nothing here is networked.
#   F8  effect on / off (on by default; the choice persists in user://mpeg_tweaks.cfg)
#   F7  cycle debug views (Y, Cb/Cr, motion vectors, residual, I/P)
#   F6  manual mosh burst
# Cutting a raider in half moshes (both halves fly apart dragging the old picture with them),
# dashes smear, and a respawn is the classic transition mosh: the I-frame of the cut is skipped,
# so the old view is dragged around by the new one's motion until the residual paints it over.
# Regular hits do not mosh.
# Every number below is live-tunable from the MPEG tweaks panel (ui/datamosh/tweaks_panel.gd,
# shown with the pause menu). See docs/datamosh.md.

const RESPAWN_JUMP: float = 3.0 # metres in one frame: a teleport, not movement
const TOGGLES: Array[Dictionary] = [
	{"name": "enabled", "label": "Effect on (F8)", "default": true},
	{"name": "always_mosh", "label": "Datamosh always (no I-frames)", "default": false},
	{"name": "mosh_through_cuts", "label": "Mosh through camera cuts", "default": false},
	{"name": "triggers", "label": "Gameplay triggers (bisect, dash, respawn)", "default": true},
]
const SPECS: Array[Dictionary] = [
	{"group": "Codec"},
	{"name": "internal_scale", "label": "Resolution", "min": 0.1, "max": 1.0, "step": 0.05, "default": 0.5},
	{"name": "quality", "label": "Quality", "min": 1.0, "max": 100.0, "step": 1.0, "default": 92.0},
	{"name": "gop_length", "label": "GOP length", "min": 1.0, "max": 600.0, "step": 1.0, "default": 100.0},
	{"name": "residual_gain", "label": "Residual gain", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.69},
	{"name": "mv_error", "label": "Motion error", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"group": "Bursts"},
	{"name": "burst_release_ms", "label": "Release (ms)", "min": 0.0, "max": 5000.0, "step": 50.0, "default": 350.0},
	{"name": "manual_burst_ms", "label": "Manual burst (ms)", "min": 50.0, "max": 5000.0, "step": 50.0, "default": 500.0},
	{"name": "manual_burst_gain", "label": "Manual burst gain", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.1},
	{"name": "bisect_burst_ms", "label": "Bisect burst (ms)", "min": 0.0, "max": 5000.0, "step": 10.0, "default": 210.0},
	{"name": "bisect_burst_gain", "label": "Bisect burst gain", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.08},
	{"name": "bisect_range", "label": "Bisect range (m)", "min": 1.0, "max": 100.0, "step": 1.0, "default": 17.0},
	{"name": "dash_burst_ms", "label": "Dash burst (ms)", "min": 0.0, "max": 3000.0, "step": 10.0, "default": 450.0},
	{"name": "dash_burst_gain", "label": "Dash burst gain", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.15},
	{"name": "respawn_burst_ms", "label": "Respawn burst (ms)", "min": 0.0, "max": 5000.0, "step": 10.0, "default": 700.0},
	{"name": "respawn_burst_gain", "label": "Respawn burst gain", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.04},
]

var effect: DatamoshEffect = DatamoshEffect.new()
var compositor: Compositor = Compositor.new()
var values: Dictionary[String, float] = {}
var flags: Dictionary[String, bool] = {}
var camera: Camera3D
var player: Node3D
var combat: CombatController
var last_phase: int = -1
var last_position: Vector3 = Vector3.ZERO
var burst_until: float = 0.0
var burst_gain: float = 0.1
var burst_through_cut: bool = false
var was_moshing: bool = false
var last_bisect: float = -1000.0
var label: Label = Label.new()
var label_until: float = 0.0
var tweaks: PanelContainer

func _init() -> void:
	reset_defaults()

func reset_defaults() -> void:
	for spec: Dictionary in SPECS:
		if spec.has("name"):
			values[spec["name"] as String] = spec["default"] as float
	for spec: Dictionary in TOGGLES:
		flags[spec["name"] as String] = spec["default"] as bool

func specs() -> Array[Dictionary]:
	return SPECS

func toggle_specs() -> Array[Dictionary]:
	return TOGGLES

func value(name: String) -> float:
	return values[name]

func _ready() -> void:
	layer = 3
	compositor.compositor_effects = [effect]
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	get_tree().node_added.connect(_on_node_added)
	tweaks = preload("res://ui/datamosh/tweaks_panel.gd").new(self)
	add_child(tweaks)
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--datamosh":
			flags["enabled"] = true
		elif arg.begins_with("--datamosh-view="):
			effect.debug_view = clampi(arg.get_slice("=", 1).to_int(), 0, DatamoshEffect.DEBUG_VIEWS.size() - 1)
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		flags["enabled"] = false
		set_process(false)
		set_process_input(false)
		tweaks.visible = false
	tweaks.call("refresh")

func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F8:
			flags["enabled"] = not flags["enabled"]
			show_status("MPEG %s" % ("on" if flags["enabled"] else "off"))
		KEY_F7:
			effect.debug_view = (effect.debug_view + 1) % DatamoshEffect.DEBUG_VIEWS.size()
			show_status("MPEG view: %s" % DatamoshEffect.DEBUG_VIEWS[effect.debug_view])
		KEY_F6:
			manual_burst()
			show_status("MPEG mosh")
		_:
			return
	tweaks.call("refresh")
	tweaks.call("save")
	get_viewport().set_input_as_handled()

func show_status(text: String) -> void:
	label.text = text
	label.visible = true
	label_until = now_msec() + 1500.0

func now_msec() -> float:
	return Time.get_ticks_usec() / 1000.0

func manual_burst() -> void:
	mosh_burst(value("manual_burst_ms"), value("manual_burst_gain"))

## Datamosh for duration_msec: no I-frames and a starved residual. Afterwards the gain eases
## back over the release time with I-frames still off, so the smear is painted over rather
## than cut. Calling again extends the burst.
func mosh_burst(duration_msec: float, gain: float, through_cut: bool = false) -> void:
	var moshing: bool = is_moshing()
	var until: float = now_msec() + duration_msec
	if until > burst_until:
		burst_until = until
	burst_gain = minf(burst_gain, gain) if moshing else gain
	burst_through_cut = (burst_through_cut and moshing) or through_cut

# HostileMob.bisected runs on every peer and spawns the two halves as "RaiderHalf" nodes into
# the scene. Their transform is set right after add_child, so the range check waits a moment.
func _on_node_added(node: Node) -> void:
	if node is Node3D and String(node.name).begins_with("RaiderHalf"):
		_on_bisect.call_deferred(node)

func _on_bisect(half: Node3D) -> void:
	if not effect.enabled or not flags["triggers"] or not is_instance_valid(half) or camera == null:
		return
	var now: float = now_msec()
	if now - last_bisect < 100.0: # the second half of the same cut
		return
	if half.global_position.distance_to(camera.global_position) > value("bisect_range"):
		return
	last_bisect = now
	mosh_burst(value("bisect_burst_ms"), value("bisect_burst_gain"))

## A clean I-frame on the next frame (camera switch, teleport), unless a burst moshes through it.
func scene_cut() -> void:
	effect.cut_requested = true

func is_moshing() -> bool:
	return burst_until > 0.0 and now_msec() - burst_until < value("burst_release_ms")

func _process(_delta: float) -> void:
	var now: float = now_msec()
	if label.visible and now > label_until:
		label.visible = false
	var current: Camera3D = get_viewport().get_camera_3d()
	if current != camera:
		if camera != null and is_instance_valid(camera) and camera.compositor == compositor:
			camera.compositor = null
		camera = current
		if camera != null and camera.compositor == null:
			camera.compositor = compositor
		find_player()
		scene_cut()
	effect.enabled = flags["enabled"] and camera != null and camera.compositor == compositor
	if not effect.enabled:
		return
	if flags["triggers"]:
		watch_player()

	var residual_gain: float = value("residual_gain")
	var release: float = value("burst_release_ms")
	var since: float = now - burst_until
	var bursting: bool = since < 0.0
	var releasing: bool = not bursting and burst_until > 0.0 and since < release
	var moshing: bool = bursting or releasing
	# An I-frame the moment the release ends would be a visible pop: count the GOP from here.
	if was_moshing and not moshing:
		effect.gop_position = 0
		burst_through_cut = false
	was_moshing = moshing
	var gain: float = residual_gain
	if bursting:
		gain = burst_gain
	elif releasing:
		var t: float = since / maxf(release, 1.0)
		gain = lerpf(burst_gain, residual_gain, t * t)
	effect.suppress_iframes = moshing or flags["always_mosh"]
	effect.mosh_through_cuts = burst_through_cut or flags["mosh_through_cuts"]
	effect.residual_gain = minf(residual_gain, gain)
	effect.quality = value("quality")
	effect.gop_length = roundi(value("gop_length"))
	effect.mv_error = value("mv_error")
	effect.internal_scale = value("internal_scale")

func find_player() -> void:
	player = null
	combat = null
	var node: Node = camera
	while node != null:
		var candidate: CombatController = node.get("combat") as CombatController if "combat" in node else null
		if candidate != null and node is Node3D:
			player = node as Node3D
			combat = candidate
			last_phase = combat.phase
			last_position = player.global_position
			return
		node = node.get_parent()

func watch_player() -> void:
	if player == null or not is_instance_valid(player) or combat == null:
		return
	var position: Vector3 = player.global_position
	if position.distance_to(last_position) > RESPAWN_JUMP:
		# Respawn or teleport: skip the cut's I-frame and let the new view drag the old one.
		mosh_burst(value("respawn_burst_ms"), value("respawn_burst_gain"), true)
		scene_cut()
	if combat.phase == CombatController.Phase.DASHING and last_phase != CombatController.Phase.DASHING:
		mosh_burst(value("dash_burst_ms"), value("dash_burst_gain"))
	last_phase = combat.phase
	last_position = position
