extends CanvasLayer
## Perf meter overlay (T-111). The perf overlay key (F3 by default, rebindable in Controls) shows
## FPS with the 1 % low, frame time, the main-thread CPU split (scripts / physics / render CPU),
## GPU time, draw calls and which side limits the frame. Off by default; hidden it does no per-frame
## work and render-time measurement is switched off again. See docs/ui.md.
##
## Per frame the meter timestamps the main loop itself: its first physics callback, the first and
## last _process callbacks (lowest/highest process_priority) and RenderingServer's pre/post draw
## signals. Performance.TIME_PROCESS is not used: it is a once-per-second maximum that also
## includes drawing. Draw wall time minus render CPU is time the main thread waited inside draw,
## for the GPU or the swapchain; it stands in for GPU time where the driver gives no GPU
## timestamps (Metal in Godot 4.7.2 reports 0).

const REFRESH: float = 0.5
const HISTORY: int = 300 # frame times kept for the 1 % low (about 5 s at the 60 fps cap)
const NEAR_BUDGET: float = 0.85 # a side within 85 % of the frame budget is what holds the frame
const HOLDS_CAP: float = 1.05 # frames this close to the budget still make the fps cap

## Runs last in each process frame and first in each physics frame.
class Clock extends Node:
	var meter: Node
	func _process(_delta: float) -> void:
		meter.set("process_end", Time.get_ticks_usec())
	func _physics_process(_delta: float) -> void:
		if int(meter.get("physics_start")) == 0:
			meter.set("physics_start", Time.get_ticks_usec())

var big: Label = Label.new() # FPS, coloured by the verdict
var detail: Label = Label.new()
var column: VBoxContainer = VBoxContainer.new()
var clock: Clock = Clock.new()
var frame_times: PackedFloat32Array = PackedFloat32Array()
var frame_index: int = 0
var samples: int = 0
# scripts, physics, render CPU, GPU, draw wait, frame, idle (ms summed over the refresh window)
var sums: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var refreshed_at: float = 0.0
var measured: RID = RID()
var physics_start: int = 0
var process_start: int = 0
var process_end: int = 0
var draw_start: int = 0
var draw_end: int = 0

func _ready() -> void:
	layer = 51
	process_priority = -1000000
	clock.meter = self
	clock.process_priority = 1000000
	clock.process_physics_priority = -1000000
	add_child(clock)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.position += Vector2(-14, -12)
	column.add_theme_constant_override("separation", -4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	for label: Label in [big, detail]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 30 if label == big else 11)
		label.add_theme_constant_override("outline_size", 5 if label == big else 3)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("line_spacing", -2)
		column.add_child(label)
	frame_times.resize(HISTORY)
	set_shown(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"perf_overlay"):
		set_shown(not visible)

func set_shown(shown: bool) -> void:
	visible = shown
	set_process(shown)
	clock.set_process(shown)
	clock.set_physics_process(shown)
	if shown:
		measured = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(measured, true)
		RenderingServer.frame_pre_draw.connect(on_pre_draw)
		RenderingServer.frame_post_draw.connect(on_post_draw)
		frame_times.fill(0.0)
		frame_index = 0
		samples = 0
		sums.fill(0.0)
		refreshed_at = 0.0
		physics_start = 0
		process_start = 0
		big.text = "…"
		detail.text = "fps"
	elif measured.is_valid():
		RenderingServer.viewport_set_measure_render_time(measured, false)
		RenderingServer.frame_pre_draw.disconnect(on_pre_draw)
		RenderingServer.frame_post_draw.disconnect(on_post_draw)
		measured = RID()

func on_pre_draw() -> void:
	draw_start = Time.get_ticks_usec()

func on_post_draw() -> void:
	draw_end = Time.get_ticks_usec()

# Runs first in each process frame, so it closes the books on the previous frame. Frame times are
# wall clock: the process delta is smoothed (application/run/delta_smoothing) and hides spikes.
func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	if process_start > 0:
		var frame_ms: float = (now_usec - process_start) / 1000.0
		var drew: bool = draw_start >= process_start and draw_end >= draw_start
		var render_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(measured) + RenderingServer.get_frame_setup_time_cpu()
		# Scripts include the deferred-call flush between the last _process and drawing.
		sums[0] += (maxi((draw_start if drew else process_end) - process_start, 0)) / 1000.0
		sums[2] += render_ms
		sums[3] += RenderingServer.viewport_get_measured_render_time_gpu(measured)
		if drew:
			sums[4] += maxf((draw_end - draw_start) / 1000.0 - render_ms, 0.0)
		# Physics steps run before _process in the same main-loop iteration.
		var loop_start: int = physics_start if physics_start > 0 else now_usec
		sums[1] += (now_usec - loop_start) / 1000.0
		# From the end of drawing to the next iteration's work: the fps-cap sleep, input and audio.
		sums[6] += maxi(loop_start - (draw_end if drew else process_end), 0) / 1000.0
		sums[5] += frame_ms
		frame_times[frame_index] = frame_ms
		frame_index = (frame_index + 1) % HISTORY
		samples += 1
	physics_start = 0
	process_start = now_usec
	var now: float = now_usec / 1000000.0
	if now - refreshed_at >= REFRESH and samples > 0:
		refreshed_at = now
		var lines: PackedStringArray = report()
		big.text = lines[0]
		big.add_theme_color_override("font_color", verdict_color(lines[lines.size() - 1]))
		detail.text = "\n".join(lines.slice(1))
		# Same viewport-height UI scale as game_ui.gd, pivoting on the bottom-right corner.
		column.pivot_offset = column.size
		column.scale = Vector2.ONE * clampf(get_viewport().get_visible_rect().size.y / 900.0, 1.0, 2.5)
		sums.fill(0.0)
		samples = 0

## Compact readout: the FPS number, then short caption lines, the verdict last.
func report() -> PackedStringArray:
	var count: float = maxf(float(samples), 1.0)
	var scripts_ms: float = sums[0] / count
	var physics_ms: float = sums[1] / count
	var render_ms: float = sums[2] / count
	var gpu_ms: float = sums[3] / count
	var wait_ms: float = sums[4] / count
	var frame_ms: float = sums[5] / count
	var idle_ms: float = sums[6] / count
	var budget: float = budget_ms()
	var worst: float = percentile_ms(frame_times, 0.99)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(roundi(1000.0 / frame_ms)) if frame_ms > 0.0 else "0")
	lines.append("fps · 1%% %d · %.1f/%.1f ms" % [roundi(1000.0 / worst) if worst > 0.0 else 0, frame_ms, budget])
	lines.append("cpu %.1f  scr %.1f phy %.1f rnd %.1f" % [scripts_ms + physics_ms + render_ms, scripts_ms, physics_ms, render_ms])
	lines.append(("gpu %.1f" % gpu_ms if gpu_ms > 0.0 else "gpu n/a") + "  wait %.1f idle %.1f" % [wait_ms, idle_ms])
	lines.append("%d draws · %d obj · %.1fM tris" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0])
	lines.append(classify(scripts_ms, physics_ms, render_ms, gpu_ms, wait_ms, frame_ms, budget))
	return lines

static func verdict_color(verdict: String) -> Color:
	if verdict.begins_with("under"):
		return Color("9fd39a")
	if verdict.begins_with("GPU"):
		return Color("e6b35a")
	if verdict.begins_with("CPU"):
		return Color("e8796a")
	return Color("d8d0c0")

## Frame budget from the fps cap; uncapped falls back to the display refresh rate, then 60.
static func budget_ms() -> float:
	var fps: float = float(Engine.max_fps)
	if fps <= 0.0:
		fps = DisplayServer.screen_get_refresh_rate()
	return 1000.0 / (fps if fps > 0.0 else 60.0)

## The 99th-percentile frame time in ms over the history (zeros are frames not yet recorded).
static func percentile_ms(times: PackedFloat32Array, fraction: float) -> float:
	var recorded: PackedFloat32Array = PackedFloat32Array()
	for time: float in times:
		if time > 0.0:
			recorded.append(time)
	if recorded.is_empty():
		return 0.0
	recorded.sort()
	return recorded[mini(int(fraction * recorded.size()), recorded.size() - 1)]

## Which side holds the frame. The main thread runs physics, scripts and render CPU in sequence, so
## their sum is the CPU cost; the GPU works in parallel. Whichever is near the budget and larger is
## the bottleneck; if neither is, the frame waits for the fps cap. gpu_ms <= 0 means no GPU
## timestamps: then time spent waiting inside draw stands for the GPU, but only while frames miss
## the cap, because at the cap that wait can be vsync rather than GPU work.
static func classify(scripts_ms: float, physics_ms: float, render_ms: float, gpu_ms: float, wait_ms: float, frame_ms: float, budget: float) -> String:
	var cpu_ms: float = scripts_ms + physics_ms + render_ms
	var gpu_side: float = gpu_ms
	if gpu_side <= 0.0 and frame_ms > budget * HOLDS_CAP:
		gpu_side = wait_ms
	if maxf(cpu_ms, gpu_side) < budget * NEAR_BUDGET:
		if frame_ms > budget * HOLDS_CAP:
			return "over budget, cause unclear (OS / sync)"
		return "under budget (capped at %d)" % roundi(1000.0 / budget)
	if gpu_side >= cpu_ms:
		return "GPU-bound"
	var part: String = "scripts"
	if physics_ms > scripts_ms and physics_ms >= render_ms:
		part = "physics"
	elif render_ms > scripts_ms and render_ms > physics_ms:
		part = "render"
	return "CPU-bound (%s)" % part
