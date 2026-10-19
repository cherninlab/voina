extends CanvasLayer
## Local presentation only: menus release input; network and host simulation continue.

var world: Node3D
var screen: Control = Control.new()
var shade: ColorRect = ColorRect.new()
var lobby_panel: PanelContainer
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

func _ready() -> void:
	name = "GameUI"
	layer = 2
	world = get_parent() as Node3D
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = make_theme()
	add_child(screen)
	shade.color = Color(0.025, 0.04, 0.04, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var menu: VBoxContainer = world.get("menu") as VBoxContainer
	lobby_panel = centered_panel(menu)
	menu.add_theme_constant_override("separation", 12)
	add_label(menu, "SECHA", 40)
	add_label(menu, "WOODLAND VILLAGE", 12, Color("9eb1a6"))
	menu.add_child(HSeparator.new())
	var address: LineEdit = world.get("address") as LineEdit
	add_label(menu, "Host address", 14)
	address.text = "127.0.0.1"
	address.placeholder_text = "IP address or Tailscale hostname"
	address.custom_minimum_size = Vector2(320, 42)
	menu.add_child(address)
	address.text_submitted.connect(func(_text: String) -> void: (world.get("join_button") as Button).pressed.emit())
	var host: Button = world.get("host_button") as Button
	host.text = "Host game"
	menu.add_child(host)
	host.pressed.connect(func() -> void: NetworkManager.host_game(NetworkManager.port))
	var join: Button = world.get("join_button") as Button
	join.text = "Join game"
	menu.add_child(join)
	join.pressed.connect(func() -> void: NetworkManager.join_game(address.text, NetworkManager.port))
	var pve: CheckButton = world.get("pve_toggle") as CheckButton
	pve.text = "Add 3 raiders"
	menu.add_child(pve)
	var match_button: CheckButton = world.get("match_toggle") as CheckButton
	match_button.text = "Rounds · first to 3 wins"
	menu.add_child(match_button)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 320
	status_label.add_theme_color_override("font_color", Color("b5c4ba"))
	status_label.add_theme_font_size_override("font_size", 14)
	menu.add_child(status_label)
	var controls: Button = world.get("controls_button") as Button
	controls.text = "Controls"
	menu.add_child(controls)
	controls.pressed.connect(show_controls)
	button(menu, "Quit", func() -> void: get_tree().quit())
	pause_column = VBoxContainer.new()
	pause_column.add_theme_constant_override("separation", 12)
	pause_panel = centered_panel(pause_column)
	add_label(pause_column, "PAUSED", 30)
	pause_status = add_label(pause_column, "The multiplayer match continues.", 14, Color("a7b7ad"))
	resume_button = button(pause_column, "Resume", resume)
	button(pause_column, "Controls", show_controls)
	var leave: Button = world.get("leave_button") as Button
	leave.text = "Leave game"
	pause_column.add_child(leave)
	leave.pressed.connect(func() -> void: NetworkManager.stop("Left game"))
	var loading: VBoxContainer = VBoxContainer.new()
	loading.add_theme_constant_override("separation", 16)
	loader_panel = centered_panel(loading)
	add_label(loading, "CONNECTING", 26)
	loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loading_label.custom_minimum_size.x = 320
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
	var controls_panel: PanelContainer = world.get("controls_panel") as PanelContainer
	controls_center.add_child(controls_panel)
	controls_panel.custom_minimum_size.x = 380
	for child: Node in controls_panel.find_children("*", "Label", true, false):
		var label: Label = child as Label
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 320
	# Every tweaks panel (sword, camera, and the shading and MPEG layers' own) in one column on the
	# left, shown with the pause menu. Opening one folds the others; the column scrolls if needed.
	tweaks = preload("res://ui/sword_tweaks_panel.gd").new()
	tweaks_wrapper.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	tweaks_wrapper.offset_left = 24
	tweaks_wrapper.offset_top = 24
	tweaks_wrapper.offset_bottom = -40
	tweaks_wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tweaks_wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	tweaks_list.add_theme_constant_override("separation", 8)
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
	refresh()

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

func add_label(parent: Node, text: String, size: int, color: Color = Color("eee9db")) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func button(parent: Node, text: String, action: Callable) -> Button:
	var control: Button = Button.new()
	control.text = text
	control.custom_minimum_size.y = 42
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

func make_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("eee9db"))
	theme.set_stylebox("panel", "PanelContainer", box(Color(0.065, 0.09, 0.085, 0.97), 10, 24))
	theme.set_stylebox("normal", "Button", box(Color("293a32"), 6, 8))
	theme.set_stylebox("hover", "Button", box(Color("3c5345"), 6, 8))
	theme.set_stylebox("pressed", "Button", box(Color("526b57"), 6, 8))
	var focus: StyleBoxFlat = box(Color(0, 0, 0, 0), 6)
	focus.set_border_width_all(2)
	focus.border_color = Color("c4d7b1")
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("normal", "LineEdit", box(Color("101a16"), 6, 10))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("background", "ProgressBar", box(Color("1c2822"), 3))
	theme.set_stylebox("fill", "ProgressBar", box(Color("96b294"), 3))
	return theme

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
func fold_other_tweaks(opened: PanelContainer) -> void:
	if not (opened.get("toggle") as Button).text.ends_with("▾"):
		return
	for panel: Node in tweaks_list.get_children():
		var toggle: Button = panel.get("toggle") as Button
		if panel != opened and toggle.text.ends_with("▾"):
			toggle.pressed.emit()

func refresh() -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	var active: bool = not peer is OfflineMultiplayerPeer
	var local: Node = local_player()
	var connecting: bool = active and local == null and not NetworkManager.dedicated
	var controls: Control = world.get("controls_panel") as Control
	if not active:
		paused = false
	elif local != null and DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		paused = true
	var menu: VBoxContainer = world.get("menu") as VBoxContainer
	lobby_panel.visible = not active and menu.visible and not controls.visible
	pause_panel.visible = local != null and paused and not controls.visible
	loader_panel.visible = connecting and not controls.visible
	shade.visible = lobby_panel.visible or pause_panel.visible or loader_panel.visible or controls.visible
	shade.mouse_filter = Control.MOUSE_FILTER_STOP if shade.visible else Control.MOUSE_FILTER_IGNORE
	status_label.text = NetworkManager.status if NetworkManager.status != "Choose Host or Join" else "2–4 players · LAN / Tailscale"
	loading_label.text = NetworkManager.status + "\nWaiting for the host…"
	(world.get("host_button") as Button).disabled = active
	(world.get("join_button") as Button).disabled = active
	(world.get("address") as LineEdit).editable = not active
	(world.get("pve_toggle") as CheckButton).disabled = active
	(world.get("match_toggle") as CheckButton).disabled = active
	var leave: Button = world.get("leave_button") as Button
	leave.text = "Cancel connection" if connecting else "Leave game"
	leave.visible = active
	resources.visible = local != null and not shade.visible
	session_label.visible = resources.visible
	(screen.get_node("Reticle") as Label).visible = resources.visible
	tweaks_wrapper.visible = pause_panel.visible
	if local != null:
		var combat: CombatController = local.get("combat") as CombatController
		var amounts: Array[float] = [float(combat.health), combat.stamina, combat.poise]
		for index: int in range(3):
			bars[index].value = amounts[index]
			values[index].text = str(int(amounts[index]))
		var players: Node3D = world.get("players") as Node3D
		session_label.text = "SECHA   /   %d / 4 players" % players.get_child_count()
