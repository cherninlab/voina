extends Node
## Playtest network monitor. The net overlay key (` by default) shows the build, each peer's ENet
## round trip, jitter and packet loss, and for every remote player its snapshot rate, display drift
## and host corrections. While connected, the same numbers go to the game log every 5 s as NET
## lines, so a playtest can be diagnosed from its output afterwards. See docs/playtest.md.

const LOG_INTERVAL: float = 5.0

var overlay: Label = null
var rates: Dictionary[int, float] = {}
var counted: Dictionary[int, int] = {}
var sampled_at: float = 0.0
var refreshed_at: float = 0.0
var logged_at: float = 0.0

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		overlay = Label.new()
		var build_label: Label = Label.new()
		overlay.visible = false
		overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		overlay.position += Vector2(-16, 16)
		overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		build_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		build_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		build_label.position += Vector2(16, -12)
		build_label.text = "build " + BuildSync.label()
		for label: Label in [overlay, build_label]:
			label.add_theme_font_size_override("font_size", 15 if label == overlay else 13)
			label.add_theme_constant_override("outline_size", 4)
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			layer.add_child(label)
	if "--net-smoke" in OS.get_cmdline_user_args():
		smoke_client()

func _unhandled_input(event: InputEvent) -> void:
	if overlay != null and event.is_action_pressed(&"net_overlay"):
		overlay.visible = not overlay.visible
		refreshed_at = 0.0

func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - sampled_at >= 1.0:
		sample_rates(now - sampled_at)
		sampled_at = now
	if overlay != null and overlay.visible and now - refreshed_at >= 0.25:
		refreshed_at = now
		overlay.text = "\n".join(report())
	if now - logged_at >= LOG_INTERVAL and connected():
		logged_at = now
		for line: String in report():
			print("NET " + line)

func connected() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func players() -> Array[CharacterBody3D]:
	var found: Array[CharacterBody3D] = []
	var scene: Node = get_tree().current_scene
	var root: Node = scene.get_node_or_null(^"Players") if scene != null else null
	if root != null:
		for child: Node in root.get_children():
			if child is CharacterBody3D and child.get("remote_motion") is RemoteMotion:
				found.append(child as CharacterBody3D)
	return found

func player(peer: int) -> CharacterBody3D:
	for body: CharacterBody3D in players():
		if body.get_multiplayer_authority() == peer:
			return body
	return null

func sample_rates(elapsed: float) -> void:
	if elapsed <= 0.0:
		return
	for body: CharacterBody3D in players():
		var peer: int = body.get_multiplayer_authority()
		var count: int = (body.get("remote_motion") as RemoteMotion).snapshots
		rates[peer] = float(count - counted.get(peer, count)) / elapsed
		counted[peer] = count

func report() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var role: String = "offline"
	if connected():
		role = "host" if multiplayer.is_server() else "client %d" % multiplayer.get_unique_id()
	lines.append("%s · build %s" % [role, BuildSync.label()])
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if connected() and enet != null:
		for peer: int in multiplayer.get_peers():
			var link: ENetPacketPeer = enet.get_peer(peer)
			if link != null:
				var loss: float = link.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / ENetPacketPeer.PACKET_LOSS_SCALE * 100.0
				lines.append("peer %d rtt %d ms jitter %d ms loss %.1f%%" % [peer, int(link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)), int(link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)), loss])
	for body: CharacterBody3D in players():
		if body.is_multiplayer_authority():
			continue
		var peer: int = body.get_multiplayer_authority()
		var drift: float = (body.get("remote_motion") as RemoteMotion).offset.length()
		lines.append("player %d snaps %d/s drift %.2f m corrections %d" % [peer, int(rates.get(peer, 0.0)), drift, int(body.get("corrections_sent"))])
	lines.append("bolts in flight %d" % Projectiles.bolts.size())
	return lines

# Two-process check: the client measures the host's 60 Hz snapshots and a live ENet link.
func smoke_client() -> void:
	await get_tree().create_timer(3.2).timeout
	var host: CharacterBody3D = player(1)
	var lines: PackedStringArray = report()
	if host != null and connected() and float(rates.get(1, 0.0)) >= 45.0 and lines.size() >= 4 and lines[1].begins_with("peer 1 rtt"):
		print("NET_SMOKE_OK: %s; host snapshots %d/s" % [lines[1], int(rates.get(1, 0.0))])
		get_tree().quit()
		return
	printerr("NET_SMOKE_FAIL: " + " | ".join(lines))
	get_tree().quit(1)
