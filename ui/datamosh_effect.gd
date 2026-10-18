class_name DatamoshEffect
extends CompositorEffect

# MPEG-style compression of the 3D frame, ported from VANSCANS (js/vfx/mpeg/): the picture
# really goes through an encoder and decoder every frame on the GPU. YCbCr 4:2:0, 8x8 DCT
# with the JPEG quantization tables, motion-compensated P-frames on 16x16 macroblocks and a
# GOP with I-frames. Datamosh is what the maths does when I-frames are suppressed and the
# residual is starved: the old picture is dragged along by the new motion vectors.
#
# Runs after transparents, before tonemapping, so the HUD and the fisheye stay outside the
# codec. ui/datamosh.gd owns the policy (when to mosh); this class owns the GPU work and the
# I/P decision for the frame actually being rendered. Fields below are written from the main
# thread and read on the render thread, one value at a time.
# See docs/datamosh.md.

const MB: int = 16
const DEBUG_VIEWS: PackedStringArray = ["off", "Y", "Cb/Cr", "motion vectors", "residual", "I/P"]
const STALE_USEC: int = 250000

## Codec resolution as a share of the 3D frame (padded up to whole macroblocks).
var internal_scale: float = 0.5
## libjpeg quality, 1 (mush) to 100 (quantizer off).
var quality: float = 20.0
## An I-frame every N frames; 1 = intra only.
var gop_length: int = 220
## P-frame residual multiplier: 1 = correct picture, towards 0 the old picture smears.
var residual_gain: float = 0.92
## Suppress scheduled I-frames.
var suppress_iframes: bool = false
## While suppressing, also skip the I-frame of a scene cut (the classic transition mosh).
var mosh_through_cuts: bool = false
## 0..1 share of macroblocks with a wrong or jittered motion vector.
var mv_error: float = 0.1
## Index into DEBUG_VIEWS.
var debug_view: int = 0
## Set by the main thread; the next rendered frame consumes it.
var cut_requested: bool = false
## Frames since the last I-frame (render thread), and whether the last frame was intra.
var gop_position: int = 0
var last_intra: bool = true
## What the renderer handed over last frame (for checks and docs).
var last_color_format: int = -1
var last_has_depth: bool = false
var frames_coded: int = 0

var rd: RenderingDevice
var ycbcr_shader: RID
var motion_shader: RID
var block_shader: RID
var display_shaders: Dictionary[int, RID] = {}
var pipelines: Dictionary[RID, RID] = {}
var linear_sampler: RID
var nearest_sampler: RID
var camera_buffer: RID
var fallback_depth: RID

var size: Vector2i = Vector2i.ZERO
var source_size: Vector2i = Vector2i.ZERO
var applied_scale: float = 0.0
var cur: Array[RID] = [RID(), RID()]
var refs: Array[RID] = [RID(), RID()]
var mv: RID
var residual: RID
# The scene colour is not storage-writable on Mobile: the display pass writes this texture
# (same size and format) and it is copied over the colour.
var output: RID
var output_format: int = -1
var output_size: Vector2i = Vector2i.ZERO
var index: int = 0
var frame: int = 0
var first: bool = true
var last_usec: int = 0
var prev_view_proj: Projection = Projection.IDENTITY
var has_previous_camera: bool = false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()
	if rd != null:
		RenderingServer.call_on_render_thread(_init_compute)

func _notification(what: int) -> void:
	# Script methods are unavailable this late: free everything inline.
	if what == NOTIFICATION_PREDELETE and rd != null:
		var owned: Array[RID] = [cur[0], cur[1], refs[0], refs[1], mv, residual, output, ycbcr_shader, motion_shader, block_shader, linear_sampler, nearest_sampler, camera_buffer, fallback_depth]
		owned.append_array(display_shaders.values())
		for rid: RID in owned:
			if rid.is_valid():
				rd.free_rid(rid)

## Forget the reference: the next frame is an I-frame whatever the mode.
func reset_gop() -> void:
	first = true

func _init_compute() -> void:
	ycbcr_shader = _load_shader("res://ui/datamosh/ycbcr.glsl", "")
	motion_shader = _load_shader("res://ui/datamosh/motion.glsl", "")
	block_shader = _load_shader("res://ui/datamosh/block.glsl", "")
	display_shaders[RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT] = _load_shader("res://ui/datamosh/display.glsl", "rgba16f")
	display_shaders[RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32] = _load_shader("res://ui/datamosh/display.glsl", "rgb10a2")
	var sampler: RDSamplerState = RDSamplerState.new()
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler = rd.sampler_create(sampler)
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	nearest_sampler = rd.sampler_create(sampler)
	camera_buffer = rd.uniform_buffer_create(_camera_bytes(Transform3D.IDENTITY, Projection.IDENTITY, 0.05, 100.0, false).size())
	# Bound in place of the scene depth when the renderer exposes none: reads as far (rotation only).
	var format: RDTextureFormat = RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.width = 1
	format.height = 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	fallback_depth = rd.texture_create(format, RDTextureView.new(), [PackedByteArray([0, 0, 0, 0])])

func _load_shader(path: String, version: String) -> RID:
	var file: RDShaderFile = load(path) as RDShaderFile
	var spirv: RDShaderSPIRV = file.get_spirv(StringName(version))
	if spirv.compile_error_compute != "":
		push_error("Datamosh shader %s [%s]: %s" % [path, version, spirv.compile_error_compute])
		return RID()
	var shader: RID = rd.shader_create_from_spirv(spirv)
	if shader.is_valid():
		pipelines[shader] = rd.compute_pipeline_create(shader)
	return shader

func _free_targets() -> void:
	for rid: RID in [cur[0], cur[1], refs[0], refs[1], mv, residual, output]:
		if rid.is_valid():
			rd.free_rid(rid)
	output = RID()
	output_format = -1
	cur = [RID(), RID()]
	refs = [RID(), RID()]
	mv = RID()
	residual = RID()

func _target(width: int, height: int) -> RID:
	var format: RDTextureFormat = RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.width = width
	format.height = height
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return rd.texture_create(format, RDTextureView.new())

## (Re)allocates the targets for this source size and scale. Returns true if the reference was lost.
func _ensure_targets(source: Vector2i, scale: float) -> bool:
	scale = clampf(scale, 0.05, 1.0)
	var width: int = maxi(MB, ceili(source.x * scale / MB) * MB)
	var height: int = maxi(MB, ceili(source.y * scale / MB) * MB)
	source_size = source
	applied_scale = scale
	if Vector2i(width, height) == size and refs[0].is_valid():
		return false
	_free_targets()
	size = Vector2i(width, height)
	for i: int in 2:
		cur[i] = _target(width, height)
		refs[i] = _target(width, height)
	mv = _target(width / MB, height / MB)
	residual = _target(width, height)
	return true

func _quality_to_scale(q: float) -> float:
	q = clampf(q, 1.0, 100.0)
	return 50.0 / q if q < 50.0 else 2.0 - q / 50.0

## GOP policy: the first frame; every gop_length-th frame unless suppressing; any cut unless
## suppressing with mosh_through_cuts.
func _next_intra(cut: bool) -> bool:
	var scheduled: bool = gop_position + 1 >= maxi(1, gop_length)
	var intra: bool = first or (cut and not (suppress_iframes and mosh_through_cuts)) or (scheduled and not suppress_iframes)
	first = false
	gop_position = 0 if intra else gop_position + 1
	return intra

func _camera_bytes(cam: Transform3D, proj: Projection, near: float, far: float, has_depth: bool) -> PackedByteArray:
	var data: PackedFloat32Array = PackedFloat32Array()
	var to_world: Projection = Projection(cam)
	for m: Projection in [to_world, prev_view_proj]:
		for column: Vector4 in [m.x, m.y, m.z, m.w]:
			data.append_array([column.x, column.y, column.z, column.w])
	data.append_array([proj.x.x, proj.y.y, proj.z.x, proj.z.y])
	data.append_array([near, far, 1.0 if has_depth else 0.0, 1.0 if has_previous_camera else 0.0])
	return data.to_byte_array()

func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id: RID in ids:
		uniform.add_id(id)
	return uniform

func _image(binding: int, id: RID) -> RDUniform:
	return _uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, binding, [id])

func _dispatch(list: int, shader: RID, uniforms: Array[RDUniform], push: PackedByteArray, groups: Vector2i) -> void:
	rd.compute_list_bind_compute_pipeline(list, pipelines[shader])
	rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(shader, 0, uniforms), 0)
	rd.compute_list_set_push_constant(list, push, push.size())
	rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	rd.compute_list_add_barrier(list)

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if rd == null or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not block_shader.is_valid():
		return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene: RenderSceneDataRD = render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or scene == null:
		return
	var source: Vector2i = buffers.get_internal_size()
	if source.x <= 0 or source.y <= 0:
		return
	var color: RID = buffers.get_color_layer(0)
	var color_format: int = rd.texture_get_format(color).format
	var display_shader: RID = display_shaders.get(color_format, RID())
	if not display_shader.is_valid():
		return
	# Mobile stores colour at half scale in RGB10A2 so it reaches 2.0.
	var luminance_multiplier: float = 2.0 if color_format == RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32 else 1.0
	var depth: RID = buffers.get_depth_layer(0)
	var has_depth: bool = depth.is_valid()
	last_color_format = color_format
	last_has_depth = has_depth
	if not has_depth:
		depth = fallback_depth

	if _ensure_targets(source, internal_scale):
		reset_gop()
	if output_format != color_format or output_size != source or not output.is_valid():
		if output.is_valid():
			rd.free_rid(output)
		var format: RDTextureFormat = RDTextureFormat.new()
		format.format = color_format as RenderingDevice.DataFormat
		format.width = source.x
		format.height = source.y
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		output = rd.texture_create(format, RDTextureView.new())
		output_format = color_format
		output_size = source
	var now: int = Time.get_ticks_usec()
	# Effect switched off for a while, or the window was hidden: the reference is too old.
	if now - last_usec > STALE_USEC:
		reset_gop()
		has_previous_camera = false
	last_usec = now
	var cut: bool = cut_requested
	cut_requested = false
	var intra: bool = _next_intra(cut)
	last_intra = intra
	frame += 1

	var cam: Transform3D = scene.get_cam_transform()
	var proj: Projection = scene.get_cam_projection()
	var near: float = proj.get_z_near()
	var far: float = proj.get_z_far()
	var bytes: PackedByteArray = _camera_bytes(cam, proj, near, far, has_depth)
	rd.buffer_update(camera_buffer, 0, bytes.size(), bytes)
	prev_view_proj = proj * Projection(cam.affine_inverse())
	has_previous_camera = true

	var uv: Vector2 = Vector2(1.0 / (applied_scale * source.x), 1.0 / (applied_scale * source.y))
	var cur_now: RID = cur[index]
	var cur_prev: RID = cur[1 - index]
	var ref_prev: RID = refs[index]
	var ref_next: RID = refs[1 - index]
	var groups: Vector2i = Vector2i(size.x / 8, size.y / 8)
	var intra_flag: int = 1 if intra else 0

	var list: int = rd.compute_list_begin()
	_dispatch(list, ycbcr_shader, [
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [linear_sampler, color]),
		_image(1, cur_now),
	], _pack([size.x, size.y, uv.x, uv.y, luminance_multiplier, 0.0, 0.0, 0.0]), groups)
	_dispatch(list, motion_shader, [
		_image(0, cur_now),
		_image(1, cur_prev),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [nearest_sampler, depth]),
		_image(3, mv),
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 4, [camera_buffer]),
	], _pack([size.x, size.y, uv.x, uv.y, mv_error, frame & 0xffff, intra_flag, 0.0]),
		Vector2i(ceili(size.x / float(MB * 8)), ceili(size.y / float(MB * 8))))
	_dispatch(list, block_shader, [
		_image(0, cur_now),
		_image(1, ref_prev),
		_image(2, mv),
		_image(3, ref_next),
		_image(4, residual),
	], _pack([size.x, size.y, _quality_to_scale(quality), residual_gain, intra_flag, 0.0, 0.0, 0.0]), groups)
	_dispatch(list, display_shader, [
		_image(0, output),
		_image(1, ref_next),
		_image(2, mv),
		_image(3, residual),
	], _pack([source.x, source.y, size.x, size.y, applied_scale, luminance_multiplier, _gop_fraction(),
		debug_view, intra_flag, 0.0, 0.0, 0.0]), Vector2i(ceili(source.x / 8.0), ceili(source.y / 8.0)))
	rd.compute_list_end()
	rd.texture_copy(output, color, Vector3.ZERO, Vector3.ZERO, Vector3(source.x, source.y, 1), 0, 0, 0, 0)
	index = 1 - index
	frames_coded += 1

func _gop_fraction() -> float:
	if suppress_iframes:
		return 1.0
	return minf(1.0, float(gop_position) / float(maxi(1, gop_length - 1)))

## Push constants: ints are written as 32-bit integers, floats as 32-bit floats, in order.
func _pack(values: Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(values.size() * 4)
	for i: int in values.size():
		if values[i] is int:
			bytes.encode_s32(i * 4, values[i] as int)
		else:
			bytes.encode_float(i * 4, values[i] as float)
	return bytes
