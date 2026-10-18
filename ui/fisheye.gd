extends CanvasLayer

# Full-screen fisheye on the 3D frame, below the HUD. The local camera widens its field of view
# with the same setting (see PlayerCharacter), and this remaps that wide frame.
const SHADER: Shader = preload("res://ui/fisheye.gdshader")
const BASE_FOV: float = 75.0
const WIDE_FOV: float = 142.0
# Vertical field of view the frame centre shows at full strength. The gap to WIDE_FOV is what the
# remap squeezes toward the edges, so widening WIDE_FOV strengthens only the edge distortion.
const CENTRE_FOV: float = 100.0
var rect: ColorRect = ColorRect.new()
var material: ShaderMaterial = ShaderMaterial.new()

static func camera_fov(strength: float) -> float:
	return lerpf(BASE_FOV, WIDE_FOV, clampf(strength, 0.0, 1.0))

static func centre_fov(strength: float) -> float:
	return lerpf(BASE_FOV, CENTRE_FOV, clampf(strength, 0.0, 1.0))

func _ready() -> void:
	layer = 0
	material.shader = SHADER
	rect.material = material
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

func _process(_delta: float) -> void:
	var strength: float = InputSettings.fisheye
	rect.visible = strength > 0.001 and DisplayServer.get_name() != "headless"
	material.set_shader_parameter("source_half_fov", deg_to_rad(camera_fov(strength)) * 0.5)
	material.set_shader_parameter("centre_half_fov", deg_to_rad(centre_fov(strength)) * 0.5)
