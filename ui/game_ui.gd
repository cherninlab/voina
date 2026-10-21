extends CanvasLayer
## Local presentation only: menus release input; network and host simulation continue.

var menu_backdrop: ColorRect = ColorRect.new()
var world_image_effects: Array[CanvasLayer] = []
var menu_music: AudioStreamPlayer = AudioStreamPlayer.new()
var world: Node3D
var screen: Control = Control.new()
var shade: ColorRect = ColorRect.new()
var lobby_panel: PanelContainer
var logo: TextureRect = TextureRect.new()
var title_screen: Control = Control.new()
var title_choices: VBoxContainer = VBoxContainer.new()
var setup_mode: String = ""
var setup_heading: Label
var address_heading: Label
var title_host: Button
var ui_font: SystemFont = SystemFont.new()
var caps_font: FontVariation = FontVariation.new() # ui_font tracked about 105 % at menu sizes
var menu_buttons: Array[Button] = [] # menu items, kept in capitals by refresh()
var pause_panel: PanelContainer
var loader_panel: PanelContainer
var pause_column: VBoxContainer
var status_label: Label = Label.new()
var loading_label: Label = Label.new()
var pause_status: Label
var session_label: Label = Label.new()
var resources: VBoxContainer = VBoxContainer.new()
var values: Array[Label] = []
var bars: Array[ProgressBar] = []
var controls_center: CenterContainer = CenterContainer.new()
var paused: bool = false
var resume_button: Button
var cancel_button: Button
var tweaks: PanelContainer
var tweaks_wrapper: ScrollContainer = ScrollContainer.new()
var tweaks_list: VBoxContainer = VBoxContainer.new()
const TWEAKS_WIDTH: float = 360.0 # the tweaks column's width at the right edge (px)
const MENU_RED: Color = Color("e0262b") # menu buttons and the title logo; buttons fade to white under the mouse
const HOVER_FADE: float = 0.2 # seconds
const DIM_WHITE: Color = Color(1, 1, 1, 0.4) # disabled and placeholder text
# Menu type scale (logical px): capitals for headings, items and field captions; body copy stays as written.
const HEADING_SIZE: int = 20
const ITEM_SIZE: int = 13
const CAPTION_SIZE: int = 11
const BODY_SIZE: int = 13
var perf_meter: CanvasLayer = preload("res://ui/perf_meter.gd").new()
var graphics_panel: PanelContainer = preload("res://ui/graphics_panel.gd").new() # beside the controls, shown with them

func _ready() -> void:
	name = "GameUI"
	var soundtrack: AudioStreamMP3 = preload("res://content/audio/music/secha-menu-theme.mp3").duplicate() as AudioStreamMP3
	soundtrack.loop = true
	menu_music.stream = soundtrack
	menu_music.volume_db = -10.0
	add_child(menu_music)
	layer = 2
	world = get_parent() as Node3D
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_font.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
	caps_font.base_font = ui_font
	caps_font.spacing_glyph = 1 # 5 % of 13-20 px type, rounded to whole pixels
	screen.theme = make_theme()
	add_child(screen)
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_backdrop.color = Color.BLACK
	menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(menu_backdrop)
	# Plain black behind the title; the world's image effects are hidden while it covers the 3D view.
	for child: Node in world.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path in ["res://ui/shading.gd", "res://ui/fisheye.gd"]:
			world_image_effects.append(child as CanvasLayer)
	screen.add_child(shade)
	var menu: VBoxContainer = world.get("menu") as VBoxContainer
	lobby_panel = centered_panel(menu)
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(title_screen)
	logo.texture = preload("res://content/ui/secha_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.self_modulate = MENU_RED # the white artwork, tinted
	title_screen.add_child(logo)
	title_choices.add_theme_constant_override("separation", 0)
	title_screen.add_child(title_choices)
	title_host = title_button("Host game", func() -> void: show_setup("host"))
	title_button("Join game", func() -> void: show_setup("join"))
	title_button("Settings", show_controls)
	title_button("Quit", func() -> void: get_tree().quit())
	setup_heading = heading(menu, "Host game")
	menu.add_theme_constant_override("separation", 10)
	menu.add_child(HSeparator.new())
	var address: LineEdit = world.get("address") as LineEdit
	address_heading = caption(menu, "Host address")
	address.text = "127.0.0.1"
	address.placeholder_text = "IP address or Tailscale hostname"
	address.custom_minimum_size = Vector2(320, 36)
	menu.add_child(address)
	address.text_submitted.connect(func(_text: String) -> void: (world.get("join_button") as Button).pressed.emit())
	var host: Button = world.get("host_button") as Button
	host.text = "Start game"
	host.pressed.connect(func() -> void: NetworkManager.host_game(NetworkManager.port))
	var join: Button = world.get("join_button") as Button
	join.text = "Join game"
	join.pressed.connect(func() -> void: NetworkManager.join_game(address.text, NetworkManager.port))
	var village_raiders: CheckButton = world.get("village_raiders_toggle") as CheckButton
	village_raiders.text = "Raiders in the village"
	menu.add_child(village_raiders)
	var forest_raiders: CheckButton = world.get("forest_raiders_toggle") as CheckButton
	forest_raiders.text = "Raiders in the woods"
	menu.add_child(forest_raiders)
	var pve: CheckButton = world.get("pve_toggle") as CheckButton
	pve.text = "Possessed villagers at the church"
	menu.add_child(pve)
	var match_button: CheckButton = world.get("match_toggle") as CheckButton
	match_button.text = "Rounds · first to 3 wins"
	menu.add_child(match_button)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 320
	status_label.add_theme_font_size_override("font_size", BODY_SIZE)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(status_label)
	# Controls stay on the title (Settings) and pause menus; the setup column has no copy.
	(world.get("controls_button") as Button).queue_free()
	# The setup's one primary action (only one of the two is shown), then Back to close the column.
	for primary: Button in [host, join]:
		menu.add_child(primary)
		style_primary(primary)
	button(menu, "Back", func() -> void: show_setup(""))
	pause_column = VBoxContainer.new()
	pause_column.add_theme_constant_override("separation", 10)
	pause_panel = centered_panel(pause_column)
	heading(pause_column, "Paused")
	pause_status = add_label(pause_column, "The multiplayer match continues.", BODY_SIZE)
	pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resume_button = button(pause_column, "Resume", resume)
	button(pause_column, "Settings", show_controls)
	var leave: Button = world.get("leave_button") as Button
	leave.text = "Leave game"
	pause_column.add_child(leave)
	leave.pressed.connect(func() -> void: NetworkManager.stop("Left game"))
	var loading: VBoxContainer = VBoxContainer.new()
	loading.add_theme_constant_override("separation", 10)
	loader_panel = centered_panel(loading)
	heading(loading, "Connecting")
	loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loading_label.custom_minimum_size.x = 320
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_child(loading_label)
	var progress: ProgressBar = ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	progress.custom_minimum_size.y = 4
	loading.add_child(progress)
	cancel_button = button(loading, "Cancel connection", func() -> void: NetworkManager.stop("Connection cancelled"))
	controls_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(controls_center)
	# Settings: controls and graphics side by side.
	var settings_row: HBoxContainer = HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 12)
	controls_center.add_child(settings_row)
	var controls_panel: PanelContainer = world.get("controls_panel") as PanelContainer
	settings_row.add_child(controls_panel)
	controls_panel.custom_minimum_size.x = 380
	settings_row.add_child(graphics_panel)
	graphics_panel.custom_minimum_size.x = 380
	for child: Node in graphics_panel.find_children("*", "Label", true, false):
		var label: Label = child as Label
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 320
		if label == graphics_panel.get("title"):
			style_caps(label, HEADING_SIZE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif label in (graphics_panel.get("captions") as Array):
			style_caps(label, CAPTION_SIZE)
		else:
			label.add_theme_font_size_override("font_size", BODY_SIZE)
	for child: Node in controls_panel.find_children("*", "Label", true, false):
		var label: Label = child as Label
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 320
		if label == controls_panel.get("message"):
			label.add_theme_font_size_override("font_size", BODY_SIZE)
		elif label.text.begins_with("CONTROLS"):
			label.text = "Controls"
			style_caps(label, HEADING_SIZE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			style_caps(label, CAPTION_SIZE)
	# Every tweaks panel (sword, camera, and the shading and MPEG layers' own) in one column on the
	# left, shown with the pause menu. Opening one folds the others; the column scrolls if needed.
	tweaks = preload("res://ui/sword_tweaks_panel.gd").new()
	# Down the right-hand side from the top-right corner (T-116); the perf meter has the top left.
	tweaks_wrapper.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	tweaks_wrapper.offset_right = -24
	tweaks_wrapper.offset_left = -24 - TWEAKS_WIDTH
	tweaks_wrapper.offset_top = 24
	tweaks_wrapper.offset_bottom = -40
	tweaks_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL # each panel then sits at its right
	var compact_look: Theme = compact_theme()
	tweaks_wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tweaks_wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	tweaks_list.add_theme_constant_override("separation", 2)
	tweaks_wrapper.add_child(tweaks_list)
	screen.add_child(tweaks_wrapper)
	var panels: Array[PanelContainer] = [tweaks, preload("res://ui/camera_tweaks_panel.gd").new()]
	for layer: Node in world.get_children():
		if layer != self and layer.get("tweaks") is PanelContainer:
			panels.append(layer.get("tweaks") as PanelContainer)
	for panel: PanelContainer in panels:
		if panel.get_parent() == null:
			tweaks_list.add_child(panel)
		else:
			panel.reparent(tweaks_list, false)
		(panel.get("toggle") as Button).pressed.connect(fold_other_tweaks.bind(panel))
		# On the panel itself: the shading and MPEG panels otherwise borrow the HUD's theme when shown.
		panel.theme = compact_look
		panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		compact(panel)
	var hud: Label = world.get("hud") as Label
	hud.position = Vector2(24, 24)
	hud.visible = "--debug-hud" in OS.get_cmdline_user_args()
	screen.add_child(hud)
	session_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	session_label.position = Vector2(24, 22)
	session_label.add_theme_font_size_override("font_size", 14)
	screen.add_child(session_label)
	resources.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	resources.position = Vector2(24, -142)
	resources.custom_minimum_size.x = 230
	resources.add_theme_constant_override("separation", 6)
	screen.add_child(resources)
	var colors: Array[Color] = [Color("ba6c5b"), Color("7ca38d"), Color("c2ae7b")]
	var names: Array[String] = ["Health", "Stamina", "Poise"]
	for index: int in range(3):
		var row: HBoxContainer = HBoxContainer.new()
		resources.add_child(row)
		var label: Label = add_label(row, names[index], 13)
		label.custom_minimum_size.x = 66
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(120, 7)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", box(colors[index], 3))
		row.add_child(bar)
		bars.append(bar)
		var value: Label = add_label(row, "100", 13)
		value.custom_minimum_size.x = 30
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		values.append(value)
	var hint: Label = add_label(resources, "Esc · menu", 12, Color("a7b7ad"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reticle: Label = Label.new()
	reticle.text = "+"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(reticle)
	reticle.name = "Reticle"
	add_child(perf_meter) # hidden until the perf overlay key; see ui/perf_meter.gd
	var menus: Array[Control] = [title_choices, lobby_panel, pause_panel, loader_panel, controls_panel, graphics_panel]
	for menu_root: Control in menus:
		for child: Node in menu_root.find_children("*", "BaseButton", true, false):
			fade_on_hover(child as BaseButton)
			var options: OptionButton = child as OptionButton
			if options != null:
				for index: int in range(options.item_count):
					options.set_item_text(index, options.get_item_text(index).to_upper())
			elif child is Button:
				menu_buttons.append(child as Button)
	refresh()
	title_host.grab_focus()

func centered_panel(column: VBoxContainer) -> PanelContainer:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 380
	center.add_child(panel)
	panel.add_child(column)
	return panel

func add_label(parent: Node, text: String, size: int, color: Color = Color.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func heading(parent: Node, text: String) -> Label:
	var label: Label = add_label(parent, text, HEADING_SIZE)
	style_caps(label, HEADING_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER # centred like the items below it
	return label

func caption(parent: Node, text: String) -> Label:
	var label: Label = add_label(parent, text, CAPTION_SIZE)
	style_caps(label, CAPTION_SIZE)
	return label

func style_caps(label: Label, size: int) -> void:
	label.uppercase = true
	label.add_theme_font_override("font", caps_font)
	label.add_theme_font_size_override("font_size", size)

# White fill, black text. fade_on_hover's self_modulate tints the fill red (the black text stays black) until hovered.
func style_primary(control: Button) -> void:
	var fill: StyleBoxFlat = box(Color.WHITE, 0, 10)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		control.add_theme_stylebox_override(state, fill)
	control.add_theme_stylebox_override("disabled", box(DIM_WHITE, 0, 10))
	control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_focus_color", "font_hover_color", "font_hover_pressed_color", "font_pressed_color", "font_disabled_color"]:
		control.add_theme_color_override(state, Color.BLACK)

func button(parent: Node, text: String, action: Callable) -> Button:
	var control: Button = Button.new()
	control.text = text
	control.custom_minimum_size.y = 36
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func box(color: Color, radius: int = 8, padding: int = 0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

# Plain white on black, no outlines; buttons fade to red while hovered or focused (fade_on_hover).
func make_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = BODY_SIZE
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_stylebox("panel", "PanelContainer", box(Color.BLACK, 0, 28))
	for type: String in ["Button", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, box(Color(0, 0, 0, 0), 0, 10))
		for state: String in ["font_color", "font_focus_color", "font_hover_color", "font_hover_pressed_color", "font_pressed_color"]:
			theme.set_color(state, type, Color.WHITE)
		theme.set_color("font_disabled_color", type, DIM_WHITE)
	for type: String in ["Button", "CheckButton", "OptionButton"]:
		theme.set_font("font", type, caps_font)
		theme.set_font_size("font_size", type, ITEM_SIZE)
	theme.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1, 0.08), 0, 10))
	theme.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	theme.set_color("font_color", "LineEdit", Color.WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", DIM_WHITE)
	theme.set_color("caret_color", "LineEdit", Color.WHITE)
	theme.set_color("selection_color", "LineEdit", Color(1, 1, 1, 0.3))
	theme.set_stylebox("separator", "HSeparator", StyleBoxEmpty.new())
	theme.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.12), 0))
	theme.set_stylebox("fill", "ProgressBar", box(Color.WHITE, 0))
	return theme

# The white-styled button is tinted MENU_RED at rest and fades to white while the mouse is over it.
# Keyboard focus leaves the colour alone, so no button looks preselected.
func fade_on_hover(control: BaseButton) -> void:
	control.self_modulate = MENU_RED
	# Deferred so is_hovered() already reflects the change that fired the signal. The button goes by
	# instance id: one freed before the deferred call (leaving, quitting) is skipped, not an error.
	for changed: Signal in [control.mouse_entered, control.mouse_exited]:
		changed.connect(hover_changed.bind(control.get_instance_id()), CONNECT_DEFERRED)

func hover_changed(button_id: int) -> void:
	var control: BaseButton = instance_from_id(button_id) as BaseButton
	if control == null:
		return
	var lit: bool = not control.disabled and control.is_hovered()
	if control.has_meta(&"hover_fade"):
		(control.get_meta(&"hover_fade") as Tween).kill()
	var fade: Tween = control.create_tween()
	fade.tween_property(control, "self_modulate", Color.WHITE if lit else MENU_RED, HOVER_FADE)
	control.set_meta(&"hover_fade", fade)

func local_player() -> Node:
	var players: Node3D = world.get("players") as Node3D
	return players.get_node_or_null(str(multiplayer.get_unique_id()))

func show_controls() -> void:
	(world.get("controls_panel") as Control).show()
	var local: Node = local_player()
	if local != null:
		local.call("release_input")
		paused = true

func open_pause() -> void:
	var local: Node = local_player()
	if local == null:
		return
	local.call("release_input")
	paused = true
	refresh()
	resume_button.grab_focus()

func resume() -> void:
	(world.get("controls_panel") as Control).hide()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	refresh()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.physical_keycode != KEY_ESCAPE:
		return
	var controls: Control = world.get("controls_panel") as Control
	if controls.visible:
		if bool(controls.get("waiting")):
			return
		controls.hide()
	elif local_player() == null and not setup_mode.is_empty():
		show_setup("")
	elif local_player() != null:
		if paused:
			resume()
		else:
			open_pause()
	else:
		return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	refresh()

# Runs after the panel's own toggle handler; an open panel's toggle reads "... ▾".
# The tweaks column, compact (T-116): white text on a thin black wash, flat buttons, small type.
static func compact_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = 12
	var wash: StyleBoxFlat = StyleBoxFlat.new()
	wash.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	wash.set_content_margin_all(6.0)
	wash.set_corner_radius_all(2)
	theme.set_stylebox(&"panel", &"PanelContainer", wash)
	var flat: StyleBoxEmpty = StyleBoxEmpty.new()
	flat.set_content_margin_all(2.0)
	var hover: StyleBoxFlat = StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	hover.set_content_margin_all(2.0)
	for style: StringName in [&"normal", &"pressed", &"focus", &"disabled"]:
		theme.set_stylebox(style, &"Button", flat)
	theme.set_stylebox(&"hover", &"Button", hover)
	for type: StringName in [&"Label", &"Button", &"CheckBox", &"OptionButton"]:
		theme.set_color(&"font_color", type, Color.WHITE)
	theme.set_color(&"font_hover_color", &"Button", Color.WHITE)
	theme.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	return theme

# The panels' own fixed widths, three quarters as wide.
static func compact(node: Node) -> void:
	var control: Control = node as Control
	if control != null and control.custom_minimum_size.x > 0.0:
		control.custom_minimum_size.x = roundf(control.custom_minimum_size.x * 0.75)
	for child: Node in node.get_children():
		compact(child)

func fold_other_tweaks(opened: PanelContainer) -> void:
	if not (opened.get("toggle") as Button).text.ends_with("▾"):
		return
	for panel: Node in tweaks_list.get_children():
		var toggle: Button = panel.get("toggle") as Button
		if panel != opened and toggle.text.ends_with("▾"):
			toggle.pressed.emit()

func refresh() -> void:
	# Keep controls comfortably sized on Retina/fullscreen displays, while layout works in
	# logical coordinates. The proportional title composition keeps the same framing.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var ui_scale: float = clampf(viewport_size.y / 900.0, 1.0, 2.5)
	screen.scale = Vector2.ONE * ui_scale
	screen.size = viewport_size / ui_scale
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	var active: bool = not peer is OfflineMultiplayerPeer
	var wants_music: bool = not active and DisplayServer.get_name() != "headless" and not NetworkManager.dedicated
	var wants_theme: bool = wants_music and not GameAudio.music_playing()
	if wants_theme and not menu_music.playing:
		menu_music.play()
	elif not wants_theme and menu_music.playing:
		menu_music.stop()
	menu_backdrop.visible = wants_music
	# An opaque title image covers the 3D world. Resume it before hosting/joining/connecting.
	get_viewport().disable_3d = wants_music
	for effect: CanvasLayer in world_image_effects:
		effect.visible = not wants_music
	fit_logo()
	var local: Node = local_player()
	var connecting: bool = active and local == null and not NetworkManager.dedicated
	var controls: Control = world.get("controls_panel") as Control
	graphics_panel.visible = controls.visible
	if not active:
		paused = false
	elif local != null and DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		paused = true
	var menu: VBoxContainer = world.get("menu") as VBoxContainer
	var in_lobby: bool = not active and menu.visible and not controls.visible
	lobby_panel.visible = in_lobby and not setup_mode.is_empty()
	title_screen.visible = in_lobby and setup_mode.is_empty()
	pause_panel.visible = local != null and paused and not controls.visible
	loader_panel.visible = connecting and not controls.visible
	logo.visible = title_screen.visible
	if logo.visible:
		fit_logo()
	shade.visible = in_lobby or pause_panel.visible or loader_panel.visible or controls.visible
	shade.color = Color(0, 0, 0, 0.0) if title_screen.visible else Color(0, 0, 0, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP if shade.visible else Control.MOUSE_FILTER_IGNORE
	# Idle statuses (nothing joined yet, or the player left on purpose) show the player count instead.
	var idle: bool = NetworkManager.status in ["Choose Host or Join", "Left game"]
	status_label.text = "2–4 players · LAN / Tailscale" if idle else NetworkManager.status
	loading_label.text = NetworkManager.status + "\nWaiting for the host…"
	(world.get("host_button") as Button).disabled = active
	(world.get("join_button") as Button).disabled = active
	(world.get("address") as LineEdit).editable = not active
	for toggle: String in ["pve_toggle", "village_raiders_toggle", "forest_raiders_toggle"]:
		(world.get(toggle) as CheckButton).disabled = active
	(world.get("match_toggle") as CheckButton).disabled = active
	var leave: Button = world.get("leave_button") as Button
	leave.text = "Cancel connection" if connecting else "Leave game"
	leave.visible = active
	resources.visible = local != null and not shade.visible
	session_label.visible = resources.visible
	(screen.get_node("Reticle") as Label).visible = resources.visible
	tweaks_wrapper.visible = pause_panel.visible
	# Menu item text is set in many places (and in other scripts); show it in capitals.
	for item: Button in menu_buttons:
		if item.is_visible_in_tree() and item.text != item.text.to_upper():
			item.text = item.text.to_upper()
	if local != null:
		var combat: CombatController = local.get("combat") as CombatController
		var amounts: Array[float] = [float(combat.health), combat.stamina, combat.poise]
		for index: int in range(3):
			bars[index].value = amounts[index]
			values[index].text = str(int(amounts[index]))
		var players: Node3D = world.get("players") as Node3D
		session_label.text = "SECHA   /   %d / 4 players" % players.get_child_count()

func show_setup(mode: String) -> void:
	setup_mode = mode
	setup_heading.text = "Host game" if mode == "host" else "Join game"
	(world.get("host_button") as Control).visible = mode == "host"
	(world.get("join_button") as Control).visible = mode == "join"
	(world.get("address") as Control).visible = mode == "join"
	address_heading.visible = mode == "join"
	for toggle: String in ["pve_toggle", "village_raiders_toggle", "forest_raiders_toggle"]:
		(world.get(toggle) as Control).visible = mode == "host"
	(world.get("match_toggle") as Control).visible = mode == "host"
	refresh()
	if mode.is_empty():
		title_host.grab_focus()
	elif mode == "join":
		(world.get("address") as Control).grab_focus()
	else:
		(world.get("host_button") as Control).grab_focus()

func title_button(text: String, action: Callable) -> Button:
	var control: Button = button(title_choices, text, action)
	control.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return control

func fit_logo() -> void:
	var window: Vector2 = screen.size
	# Keep navigation inside the viewport at 16:9, 16:10 and ultrawide sizes.
	var frame: Vector2 = window
	# Logo and choices share one centred column.
	logo.size = Vector2(window.x * 0.54, window.y * 0.48)
	logo.position = Vector2((window.x - logo.size.x) * 0.5, window.y * 0.16)
	title_choices.size.x = window.x * 0.25
	title_choices.position = Vector2((window.x - title_choices.size.x) * 0.5, window.y * 0.65)
	for child: Node in title_choices.get_children():
		var choice: Button = child as Button
		choice.custom_minimum_size.y = frame.y * 0.058
		choice.add_theme_font_size_override("font_size", maxi(ITEM_SIZE, int(frame.y * 0.022)))
