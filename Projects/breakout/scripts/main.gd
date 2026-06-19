extends Node2D

const PORT := 4242
const DISCOVERY_PORT := 4243
const DISCOVERY_MAGIC := "breakout-coop-lan-v1"
const DISCOVERY_INTERVAL := 0.45
const DISCOVERY_SCAN_REFRESH := 5.0
const DISCOVERY_SCAN_BATCH := 32
const RECONNECT_DELAY := 0.9
const MAX_CLIENTS := 1

const PADDLE_WIDTH := 148.0
const PADDLE_HEIGHT := 18.0
const PADDLE_Y_MARGIN := 58.0
const PADDLE_SPEED := 690.0
const BALL_RADIUS := 9.0
const BALL_START_SPEED := 430.0
const BALL_MAX_SPEED := 820.0
const BALL_ACCEL_PER_HIT := 18.0
const BOUNCE_MAX_ANGLE := deg_to_rad(64.0)

const BRICK_COLS := 13
const BRICK_ROWS := 7
const BRICK_HEIGHT := 24.0
const BRICK_GAP := 7.0
const BRICK_TOP_MARGIN := 96.0
const BRICK_SIDE_MARGIN := 54.0
const STARTING_LIVES := 4

const BRICK_COLORS := [
	Color("#ff6b7a"),
	Color("#ffcf5a"),
	Color("#7af0a3"),
	Color("#62d7ff"),
	Color("#b694ff"),
	Color("#ff9f69"),
	Color("#f7f7ff")
]

enum PlayMode { MENU, LOCAL, HOST, CLIENT }

var mode := PlayMode.MENU
var local_role := "menu"
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

var left_x := 440.0
var right_x := 840.0
var input_left := 0.0
var input_right := 0.0
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var score := 0
var lives := STARTING_LIVES
var level := 1
var bricks := PackedInt32Array()
var round_cooldown := 0.0
var transition_timer := 0.0
var game_message := ""

var rng := RandomNumberGenerator.new()

var hud: CanvasLayer
var score_label: Label
var lives_label: Label
var role_label: Label
var status_label: Label


func _ready() -> void:
	rng.randomize()
	instance_id = rng.randi_range(1, 2147483647)
	_build_hud()
	_connect_multiplayer_signals()
	_reset_game()
	_start_auto_match("Caut coechipier in LAN")
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
			_sync_state.rpc(left_x, right_x, ball_pos, ball_vel, score, lives, level, bricks, round_cooldown, transition_timer, game_message)
		_refresh_hud()
	elif mode == PlayMode.CLIENT and client_ready:
		_submit_input.rpc_id(1, input_right)

	queue_redraw()


func _draw() -> void:
	var size := _playfield_size()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#11131b"), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 6.0)), Color("#62d7ff"), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(6.0, size.y)), Color(1, 1, 1, 0.08), true)
	draw_rect(Rect2(Vector2(size.x - 6.0, 0.0), Vector2(6.0, size.y)), Color(1, 1, 1, 0.08), true)
	draw_rect(Rect2(Vector2(0.0, size.y - 18.0), Vector2(size.x, 18.0)), Color("#ff6b7a").darkened(0.45), true)

	for index in range(bricks.size()):
		if bricks[index] <= 0:
			continue
		var row := int(index / BRICK_COLS)
		var rect := _brick_rect(index)
		var color: Color = BRICK_COLORS[row % BRICK_COLORS.size()]
		draw_rect(rect.grow(2.0), Color(color.r, color.g, color.b, 0.13), true)
		draw_rect(rect, color, true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(1, 1, 1, 0.25), true)

	if mode == PlayMode.MENU:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.36), true)

	var left_rect := _paddle_rect(true)
	var right_rect := _paddle_rect(false)
	draw_rect(left_rect.grow(5.0), Color(0.38, 0.84, 1.0, 0.12), true)
	draw_rect(right_rect.grow(5.0), Color(1.0, 0.81, 0.35, 0.13), true)
	draw_rect(left_rect, Color("#62d7ff"), true)
	draw_rect(right_rect, Color("#ffcf5a"), true)

	draw_circle(ball_pos, BALL_RADIUS + 10.0, Color(1, 1, 1, 0.08))
	draw_circle(ball_pos, BALL_RADIUS, Color("#f7f7ff"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_start_auto_match("Cautare reluata")
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_start_local_coop()
		elif event.keycode == KEY_SPACE and _is_authoritative_game():
			_reset_game()
			_push_state_once()


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	score_label = _make_label("0", 42, Color("#f7f7ff"))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(score_label)

	lives_label = _make_label("", 18, Color(1, 1, 1, 0.7))
	lives_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.add_child(lives_label)

	role_label = _make_label("", 18, Color(1, 1, 1, 0.68))
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	score_label.position = Vector2(0.0, 12.0)
	score_label.size = Vector2(size.x, 54.0)
	lives_label.position = Vector2(18.0, 20.0)
	lives_label.size = Vector2(320.0, 30.0)
	role_label.position = Vector2(size.x - 338.0, 20.0)
	role_label.size = Vector2(320.0, 30.0)
	status_label.position = Vector2(0.0, size.y - 48.0)
	status_label.size = Vector2(size.x, 32.0)


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
	local_role = "auto"
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
		local_role = "left"
		_set_status("%s..." % status)
		_send_discovery()
	else:
		_connect_to_host("127.0.0.1", "Conectare automata la joc local")


func _start_local_coop() -> void:
	_clear_network_peer()
	mode = PlayMode.LOCAL
	local_role = "local"
	right_peer_id = 0
	client_ready = false
	reconnect_timer = -1.0
	_reset_game()
	_set_status("Coop local")


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
		_set_status("Caut coechipier in LAN...")
		return

	multiplayer.multiplayer_peer = peer
	mode = PlayMode.CLIENT
	local_role = "right"
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
		_start_auto_match(pending_status if not pending_status.is_empty() else "Caut coechipier in LAN")


func _on_peer_connected(id: int) -> void:
	if mode != PlayMode.HOST:
		return
	if id == multiplayer.get_unique_id():
		return

	if right_peer_id == 0:
		right_peer_id = id
		_assign_role.rpc_id(id, "right")
		_reset_game()
		_set_status("Echipa este conectata")
		_push_state_once()
	else:
		multiplayer.multiplayer_peer.disconnect_peer(id, true)


func _on_peer_disconnected(id: int) -> void:
	if mode == PlayMode.HOST and id == right_peer_id:
		right_peer_id = 0
		input_right = 0.0
		_reset_game()
		_set_status("Coechipier deconectat, caut alt jucator...")


func _on_connected_to_server() -> void:
	if mode == PlayMode.CLIENT:
		client_ready = true
		_set_status("Conectat la echipa")


func _on_connection_failed() -> void:
	_start_auto_match("Conexiune esuata, caut din nou")


func _on_server_disconnected() -> void:
	_start_auto_match("Gazda s-a inchis, caut din nou")


@rpc("authority", "reliable")
func _assign_role(role: String) -> void:
	local_role = role
	client_ready = true
	_set_status("Conectat la echipa")


@rpc("any_peer", "unreliable")
func _submit_input(direction: float) -> void:
	if mode != PlayMode.HOST:
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender == right_peer_id:
		input_right = clampf(direction, -1.0, 1.0)


@rpc("authority", "unreliable")
func _sync_state(
	synced_left_x: float,
	synced_right_x: float,
	synced_ball_pos: Vector2,
	synced_ball_vel: Vector2,
	synced_score: int,
	synced_lives: int,
	synced_level: int,
	synced_bricks: PackedInt32Array,
	synced_round_cooldown: float,
	synced_transition_timer: float,
	synced_status: String
) -> void:
	if mode != PlayMode.CLIENT:
		return

	left_x = synced_left_x
	right_x = synced_right_x
	ball_pos = synced_ball_pos
	ball_vel = synced_ball_vel
	score = synced_score
	lives = synced_lives
	level = synced_level
	bricks = synced_bricks
	round_cooldown = synced_round_cooldown
	transition_timer = synced_transition_timer
	game_message = synced_status
	status_label.text = synced_status
	_refresh_hud()


func _push_state_once() -> void:
	if mode == PlayMode.HOST and right_peer_id != 0:
		_sync_state.rpc(left_x, right_x, ball_pos, ball_vel, score, lives, level, bricks, round_cooldown, transition_timer, game_message)


func _read_local_input() -> void:
	match mode:
		PlayMode.LOCAL:
			input_left = _axis_from_keys(KEY_A, KEY_D)
			input_right = _axis_from_keys(KEY_LEFT, KEY_RIGHT)
		PlayMode.HOST:
			input_left = _axis_from_keys(KEY_A, KEY_D)
		PlayMode.CLIENT:
			input_right = _axis_from_keys(KEY_LEFT, KEY_RIGHT)


func _simulate_game(delta: float) -> void:
	var size := _playfield_size()
	var half_paddle := PADDLE_WIDTH * 0.5
	left_x = clampf(left_x + input_left * PADDLE_SPEED * delta, half_paddle + 10.0, size.x * 0.5 - 12.0)
	right_x = clampf(right_x + input_right * PADDLE_SPEED * delta, size.x * 0.5 + 12.0, size.x - half_paddle - 10.0)

	if transition_timer > 0.0:
		transition_timer = maxf(0.0, transition_timer - delta)
		if transition_timer <= 0.0:
			_reset_game()
		return

	if round_cooldown > 0.0:
		round_cooldown = maxf(0.0, round_cooldown - delta)
		return

	ball_pos += ball_vel * delta

	if ball_pos.x <= BALL_RADIUS + 6.0:
		ball_pos.x = BALL_RADIUS + 6.0
		ball_vel.x = absf(ball_vel.x)
	elif ball_pos.x >= size.x - BALL_RADIUS - 6.0:
		ball_pos.x = size.x - BALL_RADIUS - 6.0
		ball_vel.x = -absf(ball_vel.x)

	if ball_pos.y <= BALL_RADIUS + 6.0:
		ball_pos.y = BALL_RADIUS + 6.0
		ball_vel.y = absf(ball_vel.y)

	var ball_rect := Rect2(ball_pos - Vector2(BALL_RADIUS, BALL_RADIUS), Vector2(BALL_RADIUS * 2.0, BALL_RADIUS * 2.0))
	_collide_with_paddles(ball_rect)
	ball_rect = Rect2(ball_pos - Vector2(BALL_RADIUS, BALL_RADIUS), Vector2(BALL_RADIUS * 2.0, BALL_RADIUS * 2.0))
	_collide_with_bricks(ball_rect)

	if ball_pos.y > size.y + BALL_RADIUS:
		lives -= 1
		if lives <= 0:
			game_message = "Runda pierduta"
			transition_timer = 1.35
			ball_vel = Vector2.ZERO
		else:
			game_message = "Vieti ramase: %d" % lives
			_reset_round()

	if _remaining_bricks() == 0:
		score += 500 * level
		level += 1
		game_message = "Nivel %d" % level
		_build_level()
		_reset_round()


func _collide_with_paddles(ball_rect: Rect2) -> void:
	if ball_vel.y <= 0.0:
		return

	var left_rect := _paddle_rect(true)
	var right_rect := _paddle_rect(false)
	if ball_rect.intersects(left_rect):
		ball_pos.y = left_rect.position.y - BALL_RADIUS
		_bounce_from_paddle(left_x)
	elif ball_rect.intersects(right_rect):
		ball_pos.y = right_rect.position.y - BALL_RADIUS
		_bounce_from_paddle(right_x)


func _bounce_from_paddle(paddle_center_x: float) -> void:
	var offset := clampf((ball_pos.x - paddle_center_x) / (PADDLE_WIDTH * 0.5), -1.0, 1.0)
	var speed := minf(ball_vel.length() + BALL_ACCEL_PER_HIT, BALL_MAX_SPEED)
	var angle := offset * BOUNCE_MAX_ANGLE
	ball_vel = Vector2(sin(angle) * speed, -cos(angle) * speed)
	game_message = "Combo coop"


func _collide_with_bricks(ball_rect: Rect2) -> void:
	for index in range(bricks.size()):
		if bricks[index] <= 0:
			continue

		var rect := _brick_rect(index)
		if not ball_rect.intersects(rect):
			continue

		bricks[index] = 0
		score += 25 * level
		game_message = "Scor %d" % score

		var overlap_left := ball_rect.end.x - rect.position.x
		var overlap_right := rect.end.x - ball_rect.position.x
		var overlap_top := ball_rect.end.y - rect.position.y
		var overlap_bottom := rect.end.y - ball_rect.position.y
		var min_horizontal := minf(overlap_left, overlap_right)
		var min_vertical := minf(overlap_top, overlap_bottom)

		if min_horizontal < min_vertical:
			if overlap_left < overlap_right:
				ball_pos.x = rect.position.x - BALL_RADIUS
				ball_vel.x = -absf(ball_vel.x)
			else:
				ball_pos.x = rect.end.x + BALL_RADIUS
				ball_vel.x = absf(ball_vel.x)
		else:
			if overlap_top < overlap_bottom:
				ball_pos.y = rect.position.y - BALL_RADIUS
				ball_vel.y = -absf(ball_vel.y)
			else:
				ball_pos.y = rect.end.y + BALL_RADIUS
				ball_vel.y = absf(ball_vel.y)
		return


func _reset_game() -> void:
	var size := _playfield_size()
	left_x = size.x * 0.35
	right_x = size.x * 0.65
	input_left = 0.0
	input_right = 0.0
	score = 0
	lives = STARTING_LIVES
	level = 1
	transition_timer = 0.0
	game_message = ""
	_build_level()
	_reset_round()
	_refresh_hud()
	queue_redraw()


func _build_level() -> void:
	bricks = PackedInt32Array()
	for _index in range(BRICK_COLS * BRICK_ROWS):
		bricks.append(1)


func _reset_round() -> void:
	var size := _playfield_size()
	ball_pos = Vector2(size.x * 0.5, size.y * 0.63)
	var speed := minf(BALL_START_SPEED + float(level - 1) * 28.0, BALL_MAX_SPEED - 120.0)
	ball_vel = Vector2(rng.randf_range(-0.35, 0.35) * speed, -speed)
	round_cooldown = 0.75


func _remaining_bricks() -> int:
	var remaining := 0
	for hp in bricks:
		if hp > 0:
			remaining += 1
	return remaining


func _paddle_rect(left: bool) -> Rect2:
	var y := _playfield_size().y - PADDLE_Y_MARGIN
	var x := (left_x if left else right_x) - PADDLE_WIDTH * 0.5
	return Rect2(Vector2(x, y), Vector2(PADDLE_WIDTH, PADDLE_HEIGHT))


func _brick_rect(index: int) -> Rect2:
	var size := _playfield_size()
	var col := index % BRICK_COLS
	var row := int(index / BRICK_COLS)
	var total_width := size.x - BRICK_SIDE_MARGIN * 2.0
	var brick_width := (total_width - BRICK_GAP * float(BRICK_COLS - 1)) / float(BRICK_COLS)
	var x := BRICK_SIDE_MARGIN + float(col) * (brick_width + BRICK_GAP)
	var y := BRICK_TOP_MARGIN + float(row) * (BRICK_HEIGHT + BRICK_GAP)
	return Rect2(Vector2(x, y), Vector2(brick_width, BRICK_HEIGHT))


func _axis_from_keys(left_key: Key, right_key: Key) -> float:
	var axis := 0.0
	if Input.is_key_pressed(left_key):
		axis -= 1.0
	if Input.is_key_pressed(right_key):
		axis += 1.0
	return axis


func _match_is_active() -> bool:
	return mode == PlayMode.LOCAL or (mode == PlayMode.HOST and right_peer_id != 0)


func _is_authoritative_game() -> bool:
	return mode == PlayMode.LOCAL or mode == PlayMode.HOST


func _playfield_size() -> Vector2:
	return get_viewport_rect().size


func _refresh_hud() -> void:
	score_label.text = "%06d" % score
	lives_label.text = "Vieti %d  Nivel %d" % [lives, level]

	match mode:
		PlayMode.MENU:
			role_label.text = "AUTO"
		PlayMode.LOCAL:
			role_label.text = "COOP LOCAL"
		PlayMode.HOST:
			role_label.text = "P1 HOST"
		PlayMode.CLIENT:
			role_label.text = "P2 CLIENT"


func _set_status(text: String) -> void:
	game_message = text
	status_label.text = text
	print("Breakout: %s" % text)
	_refresh_hud()


func _clear_network_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
