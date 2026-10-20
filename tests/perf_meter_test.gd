extends Node
## Perf meter (T-111): bottleneck classification from fake timings, the 1 % low, the rebindable
## key, and that a hidden meter does no per-frame work. Run as a scene so autoloads exist.

const PERF_METER: Script = preload("res://ui/perf_meter.gd")

var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition and not failed:
		failed = true
		printerr("PERF_METER_FAIL: " + message)

func run() -> void:
	var budget: float = 1000.0 / 60.0
	# classify(scripts, physics, render CPU, GPU, draw wait, frame, budget); GPU 0 = no timestamps.
	check(PERF_METER.classify(3.0, 1.0, 2.0, 4.0, 1.0, 16.7, budget) == "under budget (capped at 60)", "light frame is under budget")
	check(PERF_METER.classify(2.0, 1.0, 3.0, 15.5, 9.0, 16.7, budget) == "GPU-bound", "GPU near the budget at the cap is GPU-bound")
	check(PERF_METER.classify(14.0, 1.0, 2.0, 6.0, 0.0, 17.0, budget) == "CPU-bound (scripts)", "busy script is CPU-bound (scripts)")
	check(PERF_METER.classify(2.0, 12.0, 2.0, 6.0, 0.0, 16.7, budget) == "CPU-bound (physics)", "physics-heavy frame")
	check(PERF_METER.classify(2.0, 1.0, 13.0, 6.0, 0.0, 16.7, budget) == "CPU-bound (render)", "render-CPU-heavy frame")
	check(PERF_METER.classify(5.0, 5.0, 5.0, 14.0, 0.0, 16.7, budget) == "CPU-bound (scripts)", "CPU sum over GPU wins")
	check(PERF_METER.classify(2.0, 1.0, 2.0, 30.0, 0.0, 33.3, 1000.0 / 30.0) == "GPU-bound", "budget follows the cap")
	# Without GPU timestamps (Metal) the draw wait stands in for the GPU, only while frames miss the cap.
	check(PERF_METER.classify(3.0, 1.0, 2.0, 0.0, 40.0, 46.0, budget) == "GPU-bound", "long draw wait on a slow frame is GPU-bound")
	check(PERF_METER.classify(1.0, 0.5, 1.0, 0.0, 14.0, 16.7, budget) == "under budget (capped at 60)", "vsync wait at the cap is not GPU load")
	check(PERF_METER.classify(22.0, 1.0, 2.0, 0.0, 1.0, 26.0, budget) == "CPU-bound (scripts)", "slow frame without draw wait is CPU-bound")
	check(PERF_METER.classify(9.0, 0.0, 9.0, 0.0, 0.0, 18.0, budget) == "CPU-bound (scripts)", "no GPU timing still judges the CPU")
	check(PERF_METER.classify(2.0, 1.0, 2.0, 0.0, 1.0, 40.0, budget).begins_with("over budget"), "slow frame with no visible cause says so")
	var times: PackedFloat32Array = PackedFloat32Array()
	times.resize(300)
	for index: int in range(200):
		times[index] = 16.7
	times[17] = 50.0
	times[18] = 40.0
	check(is_equal_approx(PERF_METER.percentile_ms(times, 0.99), 40.0), "1 % low takes the 99th-percentile frame and skips unrecorded zeros")
	check(PERF_METER.percentile_ms(PackedFloat32Array([0.0, 0.0]), 0.99) == 0.0, "empty history")
	check(InputMap.has_action(&"perf_overlay"), "the perf overlay has a remappable key")
	check(InputSettings.DEFAULTS.has(&"perf_overlay"), "the perf overlay key is listed in Controls")

	var meter: CanvasLayer = PERF_METER.new() as CanvasLayer
	add_child(meter)
	check(not meter.visible and not meter.is_processing(), "hidden by default and not processing")
	for frame: int in range(5):
		await get_tree().process_frame
	check(int(meter.get("samples")) == 0, "a hidden meter samples nothing")
	check(not (meter.get("measured") as RID).is_valid(), "a hidden meter leaves render-time measurement off")
	var press: InputEventAction = InputEventAction.new()
	press.action = &"perf_overlay"
	press.pressed = true
	meter._unhandled_input(press)
	check(meter.visible and meter.is_processing(), "the key shows the meter")
	for frame: int in range(5):
		await get_tree().process_frame
	check(int(meter.get("samples")) > 0, "a shown meter samples frames")
	var lines: PackedStringArray = meter.call("report") as PackedStringArray
	check(lines.size() == 6 and lines[0].is_valid_int() and lines[1].begins_with("fps") and lines[2].begins_with("cpu") and lines[3].begins_with("gpu") and lines[4].contains("draws"), "compact report: big fps number, fps/cpu/gpu/draws captions and a verdict")
	meter._unhandled_input(press)
	check(not meter.visible and not meter.is_processing(), "the key hides it again and stops processing")
	check(not (meter.get("measured") as RID).is_valid(), "hiding switches measurement off")
	if failed:
		get_tree().quit(1)
		return
	print("PERF_METER_OK: classification, 1 % low, key binding, zero cost when hidden")
	get_tree().quit(0)
