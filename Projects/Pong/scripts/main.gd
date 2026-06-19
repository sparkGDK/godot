extends Node2D

const PORT := 4242
const DISCOVERY_PORT := 4243
const DISCOVERY_MAGIC := "pong-auto-lan-v1"
const DISCOVERY_INTERVAL := 0.45
const DISCOVERY_SCAN_REFRESH := 5.0
const DISCOVERY_SCAN_BATCH := 32
const RECONNECT_DELAY := 0.9
const MAX_CLIENTS := 1
const PADDLE_WIDTH := 18.0
const PADDLE_HEIGHT := 124.0
const PADDLE_MARGIN := 58.0
const PADDLE_SPEED := 540.0
const BALL_RADIUS := 12.0
const BALL_SPEED := 470.0
const BALL_MAX_SPEED := 820.0
const BALL_ACCEL_PER_HIT := 34.0
const BOUNCE_MAX_ANGLE := deg_to_rad(58.0)

enum PlayMode { MENU, LOCAL, HOST, CLIENT }

var mode := PlayMode.MENU
var local_side := "menu"
var right_peer_id := 0
var client_ready := false
var instance_id := 0
var discovery_udp: PacketPeerUDP
var discovery_timer := 0.0
var discovery_scan_refresh_timer := 0.0
var discovery_scan_index := 0
var discovery_targets: Array[String] = []
var reconnect_timer := -1.0
var pending_status := ""

var left_y := 360.0
var right_y := 360.0
var input_left := 0.0
var input_right := 0.0
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var score_left := 0
var score_right := 0
var round_cooldown := 0.0

var rng := RandomNumberGenerator.new()

var hud: CanvasLayer
var score_label: Label
var status_label: Label
var role_label: Label


func _ready() -> void:
	rng.randomize()
	instance_id = rng.randi_range(1, 2147483647)
	_build_hud()
	_connect_multiplayer_signals()
	_reset_game()
	_start_auto_match("Caut jucator in retea")
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(_layout_hud)


func _physics_process(delta: float) -> void:
	_poll_discovery(delta)
	_tick_reconnect(delta)

	if mode == PlayMode.MENU:
		queue_redraw()
		return

	_read_local_input()

	if _is_authoritative_game():
		if _match_is_active():
			_simulate_game(delta)
		if mode == PlayMode.HOST and right_peer_id != 0:
			_sync_state.rpc(left_y, right_y, ball_pos, ball_vel, score_left, score_right, round_cooldown)
		_refresh_hud()
	elif mode == PlayMode.CLIENT and client_ready:
		_submit_input.rpc_id(1, input_right)

	queue_redraw()


func _draw() -> void:
	var size := _playfield_size()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#10131c"), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 5.0)), Color("#79ffe1"), true)
	draw_rect(Rect2(Vector2(0.0, size.y - 5.0), Vector2(size.x, 5.0)), Color("#ffcf5a"), true)

	for y in range(18, int(size.y), 44):
		draw_rect(Rect2(Vector2(size.x * 0.5 - 2.0, float(y)), Vector2(4.0, 24.0)), Color(1, 1, 1, 0.28), true)

	if mode == PlayMode.MENU:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.36), true)

	var left_rect := _paddle_rect(true)
	var right_rect := _paddle_rect(false)
	draw_rect(left_rect.grow(4.0), Color(0.2, 1.0, 0.82, 0.12), true)
	draw_rect(right_rect.grow(4.0), Color(1.0, 0.81, 0.35, 0.12), true)
	draw_rect(left_rect, Color("#79ffe1"), true)
	draw_rect(right_rect, Color("#ffcf5a"), true)
	draw_circle(ball_pos, BALL_RADIUS + 8.0, Color(1, 1, 1, 0.08))
	draw_circle(ball_pos, BALL_RADIUS, Color("#f7f7ff"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_start_auto_match("Cautare reluata")
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if mode != PlayMode.MENU and _is_authoritative_game():
			_reset_game()
			if mode == PlayMode.HOST and right_peer_id != 0:
				_sync_state.rpc(left_y, right_y, ball_pos, ball_vel, score_left, score_right, round_cooldown)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	score_label = _make_label("0  :  0", 52, Color("#f7f7ff"))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(score_label)

	role_label = _make_label("", 18, Color(1, 1, 1, 0.62))
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(role_label)

	status_label = _make_label("", 18, Color(1, 1, 1, 0.74))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(status_label)

	_layout_hud()
	_refresh_hud()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _layout_hud() -> void:
	var size := _playfield_size()
	score_label.position = Vector2(0.0, 14.0)
	score_label.size = Vector2(size.x, 64.0)
	role_label.position = Vector2(0.0, 78.0)
	role_label.size = Vector2(size.x, 28.0)
	status_label.position = Vector2(0.0, size.y - 54.0)
	status_label.size = Vector2(size.x, 34.0)


func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _start_auto_match(status: String) -> void:
	_clear_network_peer()
	_ensure_discovery()
	mode = PlayMode.MENU
	local_side = "auto"
	right_peer_id = 0
	client_ready = false
	input_left = 0.0
	input_right = 0.0
	reconnect_timer = -1.0
	pending_status = status
	_reset_game()

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		mode = PlayMode.HOST
		local_side = "left"
		_set_status("%s..." % status)
		_send_discovery()
	else:
		_connect_to_host("127.0.0.1", "Conectare automata la joc local")


func _ensure_discovery() -> void:
	if discovery_udp != null:
		return

	discovery_udp = PacketPeerUDP.new()
	var error := discovery_udp.bind(DISCOVERY_PORT)
	if error != OK:
		discovery_udp = null
		return

	discovery_udp.set_broadcast_enabled(true)
	discovery_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_refresh_discovery_targets()


func _poll_discovery(delta: float) -> void:
	if discovery_udp == null:
		return

	while discovery_udp.get_available_packet_count() > 0:
		var packet := discovery_udp.get_packet()
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if data.get("magic", "") != DISCOVERY_MAGIC:
			continue
		if int(data.get("port", PORT)) != PORT:
			continue

		var remote_id := int(data.get("id", 0))
		if remote_id == instance_id or remote_id == 0:
			continue
		if data.get("state", "") != "host":
			continue

		var remote_ip := discovery_udp.get_packet_ip()
		if mode == PlayMode.HOST and right_peer_id == 0 and remote_id < instance_id:
			_connect_to_host(remote_ip, "Gasit joc in retea")
			return

	discovery_timer -= delta
	discovery_scan_refresh_timer -= delta
	if discovery_scan_refresh_timer <= 0.0:
		discovery_scan_refresh_timer = DISCOVERY_SCAN_REFRESH
		_refresh_discovery_targets()

	if discovery_timer <= 0.0:
		discovery_timer = DISCOVERY_INTERVAL
		if mode == PlayMode.HOST and right_peer_id == 0:
			_send_discovery()


func _send_discovery() -> void:
	if discovery_udp == null:
		return

	var payload := {
		"magic": DISCOVERY_MAGIC,
		"id": instance_id,
		"state": "host",
		"port": PORT
	}
	var packet := JSON.stringify(payload).to_utf8_buffer()
	_send_discovery_packet("255.255.255.255", packet)
	_send_discovery_scan(packet)


func _send_discovery_packet(address: String, packet: PackedByteArray) -> void:
	discovery_udp.set_dest_address(address, DISCOVERY_PORT)
	discovery_udp.put_packet(packet)


func _send_discovery_scan(packet: PackedByteArray) -> void:
	if discovery_targets.is_empty():
		return

	var sent := 0
	while sent < DISCOVERY_SCAN_BATCH:
		var address := discovery_targets[discovery_scan_index]
		_send_discovery_packet(address, packet)
		discovery_scan_index = (discovery_scan_index + 1) % discovery_targets.size()
		sent += 1
		if discovery_scan_index == 0:
			break


func _refresh_discovery_targets() -> void:
	var targets := {}
	for address in IP.get_local_addresses():
		if not _is_lan_ipv4(address):
			continue

		var parts := address.split(".")
		var prefix := "%s.%s.%s." % [parts[0], parts[1], parts[2]]
		for host in range(1, 255):
			var candidate := "%s%d" % [prefix, host]
			if candidate != address:
				targets[candidate] = true

	discovery_targets.clear()
	for target in targets.keys():
		discovery_targets.append(str(target))

	discovery_targets.sort()
	if discovery_scan_index >= discovery_targets.size():
		discovery_scan_index = 0


func _is_lan_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false

	for part in parts:
		if not part.is_valid_int():
			return false
		var value := int(part)
		if value < 0 or value > 255:
			return false

	var a := int(parts[0])
	var b := int(parts[1])

	if a == 0 or a == 127 or a >= 224:
		return false
	if a == 10:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	if a == 192 and b == 168:
		return true
	if a == 169 and b == 254:
		return true
	if a == 100 and b >= 64 and b <= 127:
		return true

	return false


func _connect_to_host(address: String, status: String) -> void:
	_clear_network_peer()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		mode = PlayMode.MENU
		pending_status = status
		reconnect_timer = RECONNECT_DELAY
		_set_status("Caut jucator in retea...")
		return

	multiplayer.multiplayer_peer = peer
	mode = PlayMode.CLIENT
	local_side = "right"
	client_ready = false
	reconnect_timer = -1.0
	_reset_game()
	_set_status("%s: %s" % [status, address])


func _tick_reconnect(delta: float) -> void:
	if reconnect_timer < 0.0:
		return

	reconnect_timer -= delta
	if reconnect_timer <= 0.0:
		reconnect_timer = -1.0
		_start_auto_match(pending_status if not pending_status.is_empty() else "Caut jucator in retea")


func _on_peer_connected(id: int) -> void:
	if mode != PlayMode.HOST:
		return
	if id == multiplayer.get_unique_id():
		return

	if right_peer_id == 0:
		right_peer_id = id
		_assign_side.rpc_id(id, "right")
		_reset_game()
		_set_status("Jucator conectat")
	else:
		multiplayer.multiplayer_peer.disconnect_peer(id, true)


func _on_peer_disconnected(id: int) -> void:
	if mode == PlayMode.HOST and id == right_peer_id:
		right_peer_id = 0
		input_right = 0.0
		_reset_game()
		_set_status("Jucator deconectat, caut alt jucator...")


func _on_connected_to_server() -> void:
	if mode == PlayMode.CLIENT:
		client_ready = true
		_set_status("Conectat")


func _on_connection_failed() -> void:
	_start_auto_match("Conexiune esuata, caut din nou")


func _on_server_disconnected() -> void:
	_start_auto_match("Gazda s-a inchis, caut din nou")


@rpc("authority", "reliable")
func _assign_side(side: String) -> void:
	local_side = side
	client_ready = true
	_set_status("Conectat")


@rpc("any_peer", "unreliable")
func _submit_input(direction: float) -> void:
	if mode != PlayMode.HOST:
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender == right_peer_id:
		input_right = clampf(direction, -1.0, 1.0)


@rpc("authority", "unreliable")
func _sync_state(
	synced_left_y: float,
	synced_right_y: float,
	synced_ball_pos: Vector2,
	synced_ball_vel: Vector2,
	synced_score_left: int,
	synced_score_right: int,
	synced_round_cooldown: float
) -> void:
	if mode != PlayMode.CLIENT:
		return

	left_y = synced_left_y
	right_y = synced_right_y
	ball_pos = synced_ball_pos
	ball_vel = synced_ball_vel
	score_left = synced_score_left
	score_right = synced_score_right
	round_cooldown = synced_round_cooldown
	_refresh_hud()


func _read_local_input() -> void:
	match mode:
		PlayMode.LOCAL:
			input_left = _axis_from_keys(KEY_W, KEY_S)
			input_right = _axis_from_keys(KEY_UP, KEY_DOWN)
		PlayMode.HOST:
			input_left = _axis_from_keys(KEY_W, KEY_S)
		PlayMode.CLIENT:
			input_right = _axis_from_keys(KEY_UP, KEY_DOWN)


func _simulate_game(delta: float) -> void:
	var size := _playfield_size()
	var half_paddle := PADDLE_HEIGHT * 0.5
	left_y = clampf(left_y + input_left * PADDLE_SPEED * delta, half_paddle + 10.0, size.y - half_paddle - 10.0)
	right_y = clampf(right_y + input_right * PADDLE_SPEED * delta, half_paddle + 10.0, size.y - half_paddle - 10.0)

	if round_cooldown > 0.0:
		round_cooldown = maxf(0.0, round_cooldown - delta)
		return

	ball_pos += ball_vel * delta

	if ball_pos.y <= BALL_RADIUS + 6.0:
		ball_pos.y = BALL_RADIUS + 6.0
		ball_vel.y = absf(ball_vel.y)
	elif ball_pos.y >= size.y - BALL_RADIUS - 6.0:
		ball_pos.y = size.y - BALL_RADIUS - 6.0
		ball_vel.y = -absf(ball_vel.y)

	var ball_rect := Rect2(ball_pos - Vector2(BALL_RADIUS, BALL_RADIUS), Vector2(BALL_RADIUS * 2.0, BALL_RADIUS * 2.0))
	var left_rect := _paddle_rect(true)
	var right_rect := _paddle_rect(false)

	if ball_vel.x < 0.0 and ball_rect.intersects(left_rect):
		ball_pos.x = left_rect.position.x + left_rect.size.x + BALL_RADIUS
		_bounce_from_paddle(1.0, (ball_pos.y - left_y) / half_paddle)
	elif ball_vel.x > 0.0 and ball_rect.intersects(right_rect):
		ball_pos.x = right_rect.position.x - BALL_RADIUS
		_bounce_from_paddle(-1.0, (ball_pos.y - right_y) / half_paddle)

	if ball_pos.x < -BALL_RADIUS:
		score_right += 1
		_reset_round(-1.0)
	elif ball_pos.x > size.x + BALL_RADIUS:
		score_left += 1
		_reset_round(1.0)


func _bounce_from_paddle(direction: float, contact_offset: float) -> void:
	var offset := clampf(contact_offset, -1.0, 1.0)
	var speed := minf(ball_vel.length() + BALL_ACCEL_PER_HIT, BALL_MAX_SPEED)
	var angle := offset * BOUNCE_MAX_ANGLE
	ball_vel = Vector2(cos(angle) * speed * direction, sin(angle) * speed)


func _reset_game() -> void:
	var size := _playfield_size()
	left_y = size.y * 0.5
	right_y = size.y * 0.5
	score_left = 0
	score_right = 0
	var serve_direction := -1.0 if rng.randi_range(0, 1) == 0 else 1.0
	_reset_round(serve_direction)
	_refresh_hud()
	queue_redraw()


func _reset_round(direction: float) -> void:
	var size := _playfield_size()
	ball_pos = size * 0.5
	var y_speed := rng.randf_range(-0.45, 0.45) * BALL_SPEED
	ball_vel = Vector2(direction * BALL_SPEED, y_speed)
	round_cooldown = 0.75


func _paddle_rect(left: bool) -> Rect2:
	var x := PADDLE_MARGIN if left else _playfield_size().x - PADDLE_MARGIN - PADDLE_WIDTH
	var y := (left_y if left else right_y) - PADDLE_HEIGHT * 0.5
	return Rect2(Vector2(x, y), Vector2(PADDLE_WIDTH, PADDLE_HEIGHT))


func _axis_from_keys(up_key: Key, down_key: Key) -> float:
	var axis := 0.0
	if Input.is_key_pressed(up_key):
		axis -= 1.0
	if Input.is_key_pressed(down_key):
		axis += 1.0
	return axis


func _match_is_active() -> bool:
	return mode == PlayMode.LOCAL or (mode == PlayMode.HOST and right_peer_id != 0)


func _is_authoritative_game() -> bool:
	return mode == PlayMode.LOCAL or mode == PlayMode.HOST


func _playfield_size() -> Vector2:
	return get_viewport_rect().size


func _refresh_hud() -> void:
	score_label.text = "%d  :  %d" % [score_left, score_right]

	match mode:
		PlayMode.MENU:
			role_label.text = "AUTO"
		PlayMode.LOCAL:
			role_label.text = "LOCAL"
		PlayMode.HOST:
			role_label.text = "STANGA - HOST"
		PlayMode.CLIENT:
			role_label.text = "DREAPTA - CLIENT"


func _set_status(text: String) -> void:
	status_label.text = text
	print("Pong: %s" % text)
	_refresh_hud()


func _return_to_menu(status: String) -> void:
	_start_auto_match(status)


func _clear_network_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
