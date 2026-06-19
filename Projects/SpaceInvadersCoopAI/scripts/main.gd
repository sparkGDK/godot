extends Node2D

const PORT := 4246
const DISCOVERY_PORT := 4247
const DISCOVERY_MAGIC := "space-invaders-coop-network-v1"
const DISCOVERY_INTERVAL := 0.45
const DISCOVERY_SCAN_REFRESH := 5.0
const DISCOVERY_SCAN_BATCH := 32
const RECONNECT_DELAY := 0.9
const MAX_CLIENTS := 1
const NETWORK_SYNC_INTERVAL := 0.10

const STARTING_LIVES := 3
const AI_STARTING_HULL := 3
const STAR_COUNT := 120
const MAX_PARTICLES := 340
const MAX_SHOCKWAVES := 28
const MAX_POWERUPS := 16
const MAX_SCORE_POPUPS := 36

const SHIP_Y_MARGIN := 70.0
const SHIP_HALF_WIDTH := 25.0
const SHIP_HALF_HEIGHT := 25.0
const PLAYER_SPEED := 585.0
const AI_SPEED := 460.0
const PLAYER_FIRE_INTERVAL := 0.13
const AI_FIRE_INTERVAL := 0.20
const FRIENDLY_BULLET_SPEED := 760.0
const ENEMY_BULLET_SPEED := 292.0
const ENEMY_BOMB_SPEED := 178.0
const ENEMY_BOMB_RADIUS := 14.0
const ENEMY_BOMB_SPLASH_RADIUS := 72.0
const ENEMY_BOMB_CHANCE := 0.30
const PLAYER_INVULN_TIME := 1.45
const AI_REPAIR_TIME := 2.7
const POWERUP_FALL_SPEED := 145.0
const POWERUP_COLLECT_RADIUS := 34.0
const RAPID_FIRE_DURATION := 7.0
const SHIELD_DURATION := 6.5
const WEAPON_DURATION := 12.0
const ROCKET_SPLASH_RADIUS := 82.0
const LEVEL_TIME_LIMIT := 300.0
const TIME_BONUS_POINTS_PER_SECOND := 3
const TIME_BONUS_COUNT_RATE := 85.0
const TIME_BONUS_POPUP_INTERVAL := 0.22
const MISS_SCORE_PENALTY := 5
const LEVEL_INTRO_DURATION := 2.4

const ENEMY_COLS := 11
const ENEMY_ROWS := 5
const ENEMY_SPACING_X := 68.0
const ENEMY_SPACING_Y := 48.0
const ENEMY_TOP := 92.0
const ENEMY_RADIUS := 25.0
const ENEMY_SEG_COLS := 5
const ENEMY_SEG_ROWS := 3
const ENEMY_SEG_SIZE := 8.0
const ENEMY_DROP := 23.0
const ENEMY_BASE_SPEED := 38.0
const SIDE_MARGIN := 34.0
const BASE_COUNT := 3
const BASE_COLS := 14
const BASE_ROWS := 7
const BASE_CELL_SIZE := 8.0
const BASE_HP := 2

const PLAYER_COLOR := Color("#62d7ff")
const AI_COLOR := Color("#ffcf5a")
const ENEMY_BULLET_COLOR := Color("#ff5f72")
const FRIENDLY_BULLET_COLOR := Color("#dffcff")
const BASE_COLOR := Color("#7af0a3")
const BG_COLOR := Color("#080b13")
const PANEL_TEXT := Color("#f7f7ff")

const ENEMY_COLORS := [
	Color("#ff6b7a"),
	Color("#ff9f69"),
	Color("#ffcf5a"),
	Color("#7af0a3"),
	Color("#b694ff")
]

enum GameState { LEVEL_INTRO, PLAYING, LEVEL_BONUS, WAVE_TRANSITION, GAME_OVER }
enum PlayMode { MENU, LOCAL, HOST, CLIENT }

var state := GameState.PLAYING
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
var network_sync_timer := 0.0
var coop_input_axis := 0.0
var coop_input_fire := false
var rng := RandomNumberGenerator.new()

var stars: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var bases: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var enemy_bullets: Array[Dictionary] = []
var powerups: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var shockwaves: Array[Dictionary] = []
var score_popups: Array[Dictionary] = []

var player_pos := Vector2.ZERO
var ai_pos := Vector2.ZERO
var player_lives := STARTING_LIVES
var ai_hull := AI_STARTING_HULL
var score := 0
var wave := 1
var level_time_remaining := LEVEL_TIME_LIMIT
var bonus_time_remaining := 0.0
var bonus_score_buffer := 0.0
var bonus_popup_points := 0
var bonus_popup_timer := 0.0

var player_cooldown := 0.0
var ai_cooldown := 0.0
var player_invuln := 0.0
var ai_invuln := 0.0
var ai_repair_timer := 0.0
var rapid_fire_timer := 0.0
var shield_timer := 0.0
var active_weapon := "standard"
var weapon_timer := 0.0

var enemy_direction := 1.0
var enemy_fire_timer := 1.0
var level_intro_timer := 0.0
var transition_timer := 0.0
var message := ""
var message_timer := 0.0
var level_banner_text := ""
var level_banner_timer := 0.0
var level_banner_duration := 1.55
var fx_time := 0.0
var screen_shake := 0.0

var hud: CanvasLayer
var score_label: Label
var timer_label: Label
var lives_label: Label
var ai_label: Label
var status_label: Label


func _ready() -> void:
	rng.randomize()
	instance_id = rng.randi_range(1, 2147483647)
	_build_hud()
	_build_starfield()
	_connect_multiplayer_signals()
	_reset_game()
	_start_auto_match("Caut coechipier in LAN")
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _physics_process(delta: float) -> void:
	_poll_discovery(delta)
	_tick_reconnect(delta)
	fx_time += delta
	_update_starfield(delta)

	if mode == PlayMode.CLIENT:
		_read_network_input()
		if client_ready:
			_submit_input.rpc_id(1, coop_input_axis, coop_input_fire)
		_update_particles(delta)
		_update_shockwaves(delta)
		_update_score_popups(delta)
		_refresh_hud()
		queue_redraw()
		return

	if not _match_is_active():
		_update_waiting_visuals(delta)
		_refresh_hud()
		queue_redraw()
		return

	_update_timers(delta)

	match state:
		GameState.LEVEL_INTRO:
			level_intro_timer = maxf(0.0, level_intro_timer - delta)
			if level_intro_timer <= 0.0:
				state = GameState.PLAYING
				level_banner_timer = 0.0
				_show_message("Start", 0.8)
		GameState.PLAYING:
			_read_player(delta)
			_update_coop_ship(delta)
			_update_enemies(delta)
			_update_bullets(delta)
			_update_powerups(delta)
			_resolve_collisions()
			_check_wave_state()
		GameState.LEVEL_BONUS:
			_update_level_bonus(delta)
		GameState.WAVE_TRANSITION:
			_read_player(delta)
			_update_coop_ship(delta)
			_update_bullets(delta)
			_update_powerups(delta)
			_resolve_base_hits()
			_resolve_enemy_bullet_hits()
			transition_timer -= delta
			if transition_timer <= 0.0:
				wave += 1
				_build_bases()
				_build_wave()
		GameState.GAME_OVER:
			_update_bullets(delta)

	_update_particles(delta)
	_update_shockwaves(delta)
	_update_score_popups(delta)
	_refresh_hud()
	_push_state_periodically(delta)
	queue_redraw()


func _draw() -> void:
	var size := _playfield_size()
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	_draw_background_effects(size)

	var shake_offset := _shake_offset()
	draw_set_transform(shake_offset, 0.0, Vector2.ONE)
	_draw_stars()
	_draw_arena(size)
	_draw_bases()
	_draw_enemies()
	_draw_bullets()
	_draw_powerups()
	_draw_ships()
	_draw_particles()
	_draw_shockwaves()
	_draw_score_popups()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_level_banner(size)
	_draw_bonus_countdown(size)

	if state == GameState.GAME_OVER:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28), true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_start_auto_match("Cautare reluata")
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_start_local_coop()
		elif event.keycode == KEY_R and _is_authoritative_game():
			_reset_game()
			_push_state_once()


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	score_label = _make_label("000000", 42, PANEL_TEXT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(score_label)

	timer_label = _make_label("05:00", 24, Color(1, 1, 1, 0.80))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(timer_label)

	lives_label = _make_label("", 18, Color(1, 1, 1, 0.72))
	lives_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.add_child(lives_label)

	ai_label = _make_label("", 18, Color(1, 1, 1, 0.72))
	ai_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(ai_label)

	status_label = _make_label("", 20, Color(1, 1, 1, 0.76))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(status_label)

	_layout_hud()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _layout_hud() -> void:
	var size := _playfield_size()
	score_label.position = Vector2(0.0, 12.0)
	score_label.size = Vector2(size.x, 56.0)
	timer_label.position = Vector2(0.0, 62.0)
	timer_label.size = Vector2(size.x, 30.0)
	lives_label.position = Vector2(18.0, 22.0)
	lives_label.size = Vector2(340.0, 30.0)
	ai_label.position = Vector2(size.x - 358.0, 22.0)
	ai_label.size = Vector2(340.0, 30.0)
	status_label.position = Vector2(0.0, size.y - 48.0)
	status_label.size = Vector2(size.x, 34.0)


func _on_viewport_resized() -> void:
	_layout_hud()
	_build_starfield()
	player_pos.x = clampf(player_pos.x, SIDE_MARGIN, _playfield_size().x - SIDE_MARGIN)
	ai_pos.x = clampf(ai_pos.x, SIDE_MARGIN, _playfield_size().x - SIDE_MARGIN)
	player_pos.y = _ship_y()
	ai_pos.y = _ship_y()
	_layout_bases()


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
	coop_input_axis = 0.0
	coop_input_fire = false
	reconnect_timer = -1.0
	pending_status = status
	_reset_game()
	level_intro_timer = 0.0
	level_banner_timer = 0.0

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		mode = PlayMode.HOST
		local_role = "p1"
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
	coop_input_axis = 0.0
	coop_input_fire = false
	reconnect_timer = -1.0
	_reset_game()
	_set_status("Coop local: P1 A/D+Space, P2 sageti+Enter")


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
	local_role = "p2"
	client_ready = false
	reconnect_timer = -1.0
	_reset_game()
	level_intro_timer = 0.0
	level_banner_timer = 0.0
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
		coop_input_axis = 0.0
		coop_input_fire = false
		_assign_role.rpc_id(id, "p2")
		_reset_game()
		_set_status("P2 conectat. Misiunea incepe.")
		_push_state_once()
	else:
		multiplayer.multiplayer_peer.disconnect_peer(id, true)


func _on_peer_disconnected(id: int) -> void:
	if mode == PlayMode.HOST and id == right_peer_id:
		right_peer_id = 0
		coop_input_axis = 0.0
		coop_input_fire = false
		_reset_game()
		_set_status("P2 deconectat, caut alt coechipier...")


func _on_connected_to_server() -> void:
	if mode == PlayMode.CLIENT:
		client_ready = true
		_set_status("Conectat ca P2")


func _on_connection_failed() -> void:
	_start_auto_match("Conexiune esuata, caut din nou")


func _on_server_disconnected() -> void:
	_start_auto_match("Host inchis, caut din nou")


@rpc("authority", "reliable")
func _assign_role(role: String) -> void:
	local_role = role
	client_ready = true
	_set_status("Conectat ca P2")


@rpc("any_peer", "unreliable")
func _submit_input(direction: float, wants_fire: bool) -> void:
	if mode != PlayMode.HOST:
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender == right_peer_id:
		coop_input_axis = clampf(direction, -1.0, 1.0)
		coop_input_fire = wants_fire


@rpc("authority", "reliable")
func _sync_state(payload: Dictionary) -> void:
	if mode != PlayMode.CLIENT:
		return

	state = int(payload.get("state", GameState.LEVEL_INTRO))
	player_pos = payload.get("player_pos", player_pos)
	ai_pos = payload.get("ai_pos", ai_pos)
	player_lives = int(payload.get("player_lives", player_lives))
	ai_hull = int(payload.get("ai_hull", ai_hull))
	score = int(payload.get("score", score))
	wave = int(payload.get("wave", wave))
	level_time_remaining = float(payload.get("level_time_remaining", level_time_remaining))
	bonus_time_remaining = float(payload.get("bonus_time_remaining", bonus_time_remaining))
	bonus_score_buffer = float(payload.get("bonus_score_buffer", bonus_score_buffer))
	bonus_popup_points = int(payload.get("bonus_popup_points", bonus_popup_points))
	bonus_popup_timer = float(payload.get("bonus_popup_timer", bonus_popup_timer))
	player_cooldown = float(payload.get("player_cooldown", player_cooldown))
	ai_cooldown = float(payload.get("ai_cooldown", ai_cooldown))
	player_invuln = float(payload.get("player_invuln", player_invuln))
	ai_invuln = float(payload.get("ai_invuln", ai_invuln))
	ai_repair_timer = float(payload.get("ai_repair_timer", ai_repair_timer))
	rapid_fire_timer = float(payload.get("rapid_fire_timer", rapid_fire_timer))
	shield_timer = float(payload.get("shield_timer", shield_timer))
	active_weapon = str(payload.get("active_weapon", active_weapon))
	weapon_timer = float(payload.get("weapon_timer", weapon_timer))
	enemy_direction = float(payload.get("enemy_direction", enemy_direction))
	enemy_fire_timer = float(payload.get("enemy_fire_timer", enemy_fire_timer))
	level_intro_timer = float(payload.get("level_intro_timer", level_intro_timer))
	transition_timer = float(payload.get("transition_timer", transition_timer))
	message = str(payload.get("message", message))
	message_timer = float(payload.get("message_timer", message_timer))
	level_banner_text = str(payload.get("level_banner_text", level_banner_text))
	level_banner_timer = float(payload.get("level_banner_timer", level_banner_timer))
	level_banner_duration = float(payload.get("level_banner_duration", level_banner_duration))
	screen_shake = float(payload.get("screen_shake", screen_shake))

	enemies = _dictionary_array(payload.get("enemies", []))
	bases = _dictionary_array(payload.get("bases", []))
	bullets = _dictionary_array(payload.get("bullets", []))
	enemy_bullets = _dictionary_array(payload.get("enemy_bullets", []))
	powerups = _dictionary_array(payload.get("powerups", []))
	particles = _dictionary_array(payload.get("particles", []))
	shockwaves = _dictionary_array(payload.get("shockwaves", []))
	score_popups = _dictionary_array(payload.get("score_popups", []))
	_refresh_hud()


func _push_state_periodically(delta: float) -> void:
	if mode != PlayMode.HOST or right_peer_id == 0:
		return

	network_sync_timer -= delta
	if network_sync_timer <= 0.0:
		network_sync_timer = NETWORK_SYNC_INTERVAL
		_push_state_once()


func _push_state_once() -> void:
	if mode == PlayMode.HOST and right_peer_id != 0:
		_sync_state.rpc(_make_state_payload())


func _make_state_payload() -> Dictionary:
	return {
		"state": int(state),
		"player_pos": player_pos,
		"ai_pos": ai_pos,
		"player_lives": player_lives,
		"ai_hull": ai_hull,
		"score": score,
		"wave": wave,
		"level_time_remaining": level_time_remaining,
		"bonus_time_remaining": bonus_time_remaining,
		"bonus_score_buffer": bonus_score_buffer,
		"bonus_popup_points": bonus_popup_points,
		"bonus_popup_timer": bonus_popup_timer,
		"player_cooldown": player_cooldown,
		"ai_cooldown": ai_cooldown,
		"player_invuln": player_invuln,
		"ai_invuln": ai_invuln,
		"ai_repair_timer": ai_repair_timer,
		"rapid_fire_timer": rapid_fire_timer,
		"shield_timer": shield_timer,
		"active_weapon": active_weapon,
		"weapon_timer": weapon_timer,
		"enemy_direction": enemy_direction,
		"enemy_fire_timer": enemy_fire_timer,
		"level_intro_timer": level_intro_timer,
		"transition_timer": transition_timer,
		"message": message,
		"message_timer": message_timer,
		"level_banner_text": level_banner_text,
		"level_banner_timer": level_banner_timer,
		"level_banner_duration": level_banner_duration,
		"screen_shake": screen_shake,
		"enemies": enemies,
		"bases": bases,
		"bullets": bullets,
		"enemy_bullets": enemy_bullets,
		"powerups": powerups,
		"particles": particles,
		"shockwaves": shockwaves,
		"score_popups": score_popups
	}


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				var dictionary: Dictionary = item
				result.append(dictionary.duplicate(true))
	return result


func _match_is_active() -> bool:
	return mode == PlayMode.LOCAL or (mode == PlayMode.HOST and right_peer_id != 0)


func _is_authoritative_game() -> bool:
	return mode == PlayMode.LOCAL or mode == PlayMode.HOST


func _set_status(text: String) -> void:
	message = text
	message_timer = 2.4
	status_label.text = text
	print("Space Invaders Coop: %s" % text)
	_refresh_hud()


func _clear_network_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _reset_game() -> void:
	var size := _playfield_size()
	state = GameState.PLAYING
	score = 0
	wave = 1
	level_time_remaining = LEVEL_TIME_LIMIT
	bonus_time_remaining = 0.0
	bonus_score_buffer = 0.0
	bonus_popup_points = 0
	bonus_popup_timer = 0.0
	player_lives = STARTING_LIVES
	ai_hull = AI_STARTING_HULL
	player_pos = Vector2(size.x * 0.32, _ship_y())
	ai_pos = Vector2(size.x * 0.70, _ship_y())
	player_cooldown = 0.0
	ai_cooldown = 0.2
	player_invuln = 0.0
	ai_invuln = 0.0
	ai_repair_timer = 0.0
	rapid_fire_timer = 0.0
	shield_timer = 0.0
	active_weapon = "standard"
	weapon_timer = 0.0
	level_intro_timer = 0.0
	transition_timer = 0.0
	message = ""
	message_timer = 0.0
	level_banner_text = ""
	level_banner_timer = 0.0
	level_banner_duration = 1.55
	screen_shake = 0.0
	bullets.clear()
	enemy_bullets.clear()
	powerups.clear()
	particles.clear()
	shockwaves.clear()
	score_popups.clear()
	_build_bases()
	_build_wave()


func _build_wave() -> void:
	enemies.clear()
	enemy_direction = 1.0
	enemy_fire_timer = 0.85
	level_time_remaining = LEVEL_TIME_LIMIT
	bonus_time_remaining = 0.0
	bonus_score_buffer = 0.0
	bonus_popup_points = 0
	bonus_popup_timer = 0.0
	_start_level_intro()

	var size := _playfield_size()
	var total_width := float(ENEMY_COLS - 1) * ENEMY_SPACING_X
	var start_x := size.x * 0.5 - total_width * 0.5
	var formation := (wave - 1) % 5

	for row in range(ENEMY_ROWS):
		for col in range(ENEMY_COLS):
			if not _formation_has_enemy(formation, row, col):
				continue

			var offset := _formation_offset(formation, row, col)
			var drop_type := _carrier_drop_type(row, col, formation)
			enemies.append({
				"pos": Vector2(start_x + float(col) * ENEMY_SPACING_X, ENEMY_TOP + float(row) * ENEMY_SPACING_Y) + offset,
				"row": row,
				"col": col,
				"segments": _make_enemy_segments(row, formation),
				"drop_type": drop_type,
				"flash": 0.0
			})


func _formation_has_enemy(formation: int, row: int, col: int) -> bool:
	match formation:
		0:
			return true
		1:
			var center := int(ENEMY_COLS / 2)
			return abs(col - center) <= center - row + 1
		2:
			return row == 0 or row == ENEMY_ROWS - 1 or col % 2 == row % 2
		3:
			return col == 0 or col == ENEMY_COLS - 1 or row == 0 or abs(col - int(ENEMY_COLS / 2)) <= row
		4:
			return row < 2 or col < 2 or col > ENEMY_COLS - 3 or (row + col) % 3 != 0
	return true


func _formation_offset(formation: int, row: int, col: int) -> Vector2:
	match formation:
		1:
			return Vector2(0.0, abs(col - int(ENEMY_COLS / 2)) * 7.0)
		2:
			return Vector2(sin(float(col) * 0.8) * 13.0, float(row % 2) * 16.0)
		3:
			return Vector2(float(row - 2) * 18.0, float(abs(col - int(ENEMY_COLS / 2))) * 3.5)
		4:
			return Vector2(sin(float(row + col)) * 10.0, cos(float(col) * 0.7) * 9.0)
	return Vector2.ZERO


func _carrier_drop_type(row: int, col: int, formation: int) -> String:
	var weapon_types := ["weapon_double", "weapon_spread", "weapon_laser", "weapon_rocket"]
	var support_types := ["rapid", "shield", "repair", "nova"]
	if row == 0 and (col + wave + formation) % 3 == 0:
		return weapon_types[(col + wave + formation) % weapon_types.size()]
	if row == 1 and (col * 2 + wave + formation) % 8 == 0:
		return weapon_types[(row + col + wave) % weapon_types.size()]
	if row == 2 and (col + wave) % 7 == 0:
		return support_types[(row + col + wave) % support_types.size()]
	return ""


func _make_enemy_segments(enemy_row: int, formation: int) -> PackedInt32Array:
	var segments := PackedInt32Array()
	for segment_row in range(ENEMY_SEG_ROWS):
		for segment_col in range(ENEMY_SEG_COLS):
			segments.append(1 if _enemy_segment_exists(segment_row, segment_col, enemy_row, formation) else 0)
	return segments


func _enemy_segment_exists(segment_row: int, segment_col: int, enemy_row: int, formation: int) -> bool:
	if segment_row == 0:
		return segment_col >= 1 and segment_col <= 3
	if segment_row == 1:
		return true
	if enemy_row <= 1 or formation == 4:
		return segment_col != 2
	return segment_col == 0 or segment_col == 2 or segment_col == 4


func _enemy_segments_alive(enemy: Dictionary) -> int:
	return _enemy_segments_alive_from_cells(enemy["segments"])


func _enemy_segments_alive_from_cells(segments: PackedInt32Array) -> int:
	var alive := 0
	for segment in segments:
		if segment > 0:
			alive += 1
	return alive


func _damage_enemy_segments(enemy: Dictionary, impact_pos: Vector2, amount: int) -> bool:
	var segments: PackedInt32Array = enemy["segments"]
	for _hit in range(amount):
		var segment_index := _nearest_enemy_segment_index(enemy, impact_pos, segments)
		if segment_index < 0:
			break
		segments[segment_index] = 0

	enemy["segments"] = segments
	enemy["flash"] = 0.12
	return _enemy_segments_alive_from_cells(segments) <= 0


func _nearest_enemy_segment_index(enemy: Dictionary, impact_pos: Vector2, segments: PackedInt32Array) -> int:
	var enemy_pos: Vector2 = enemy["pos"]
	var origin := enemy_pos - Vector2(float(ENEMY_SEG_COLS) * ENEMY_SEG_SIZE, float(ENEMY_SEG_ROWS) * ENEMY_SEG_SIZE) * 0.5
	var best_index := -1
	var best_distance := INF

	for segment_row in range(ENEMY_SEG_ROWS):
		for segment_col in range(ENEMY_SEG_COLS):
			var segment_index := segment_row * ENEMY_SEG_COLS + segment_col
			if segments[segment_index] <= 0:
				continue
			var segment_center := origin + Vector2(float(segment_col) + 0.5, float(segment_row) + 0.5) * ENEMY_SEG_SIZE
			var distance := segment_center.distance_squared_to(impact_pos)
			if distance < best_distance:
				best_distance = distance
				best_index = segment_index

	return best_index


func _destroy_enemy(index: int, enemy: Dictionary, score_amount: int, burst_count: int) -> void:
	var enemy_pos: Vector2 = enemy["pos"]
	enemies.remove_at(index)
	_add_score(score_amount, enemy_pos, "+%d" % score_amount)
	var color: Color = ENEMY_COLORS[int(enemy["row"]) % ENEMY_COLORS.size()]
	_spawn_burst(enemy_pos, color, burst_count)
	_spawn_shockwave(enemy_pos, color, 54.0)
	var drop_type := str(enemy.get("drop_type", ""))
	if not drop_type.is_empty():
		_spawn_powerup(enemy_pos, drop_type)


func _add_score(amount: int, pos: Vector2, label: String = "") -> void:
	if amount == 0:
		return

	score = maxi(0, score + amount)
	var text := label if not label.is_empty() else (("+%d" % amount) if amount > 0 else str(amount))
	var color := Color("#7af0a3") if amount > 0 else Color("#ff5f72")
	_spawn_score_popup(pos, text, color)


func _spawn_score_popup(pos: Vector2, text: String, color: Color) -> void:
	if score_popups.size() >= MAX_SCORE_POPUPS:
		score_popups.pop_front()
	score_popups.append({
		"pos": pos,
		"vel": Vector2(rng.randf_range(-14.0, 14.0), -42.0),
		"text": text,
		"color": color,
		"life": 0.95,
		"max_life": 0.95
	})


func _build_bases() -> void:
	bases.clear()
	for index in range(BASE_COUNT):
		var cells := PackedInt32Array()
		for row in range(BASE_ROWS):
			for col in range(BASE_COLS):
				cells.append(BASE_HP if _base_cell_exists(row, col) else 0)

		bases.append({
			"origin": Vector2.ZERO,
			"cells": cells,
			"flash": 0.0
		})

	_layout_bases()


func _layout_bases() -> void:
	if bases.is_empty():
		return

	var size := _playfield_size()
	var base_width := float(BASE_COLS) * BASE_CELL_SIZE
	var y := _ship_y() - 146.0
	for i in range(bases.size()):
		var base: Dictionary = bases[i]
		var center_x := size.x * (float(i + 1) / float(BASE_COUNT + 1))
		base["origin"] = Vector2(center_x - base_width * 0.5, y)
		bases[i] = base


func _base_cell_exists(row: int, col: int) -> bool:
	if row == 0:
		return col >= 4 and col <= 9
	if row == 1:
		return col >= 2 and col <= 11
	if row >= 5:
		return col <= 4 or col >= 9
	if row == 4:
		return col <= 5 or col >= 8
	return true


func _update_timers(delta: float) -> void:
	if state == GameState.PLAYING:
		level_time_remaining = maxf(0.0, level_time_remaining - delta)
	if state != GameState.LEVEL_INTRO:
		player_cooldown = maxf(0.0, player_cooldown - delta)
		ai_cooldown = maxf(0.0, ai_cooldown - delta)
		player_invuln = maxf(0.0, player_invuln - delta)
		ai_invuln = maxf(0.0, ai_invuln - delta)
		rapid_fire_timer = maxf(0.0, rapid_fire_timer - delta)
		shield_timer = maxf(0.0, shield_timer - delta)
		if weapon_timer > 0.0:
			weapon_timer = maxf(0.0, weapon_timer - delta)
			if weapon_timer <= 0.0:
				active_weapon = "standard"
	message_timer = maxf(0.0, message_timer - delta)
	level_banner_timer = maxf(0.0, level_banner_timer - delta)
	screen_shake = maxf(0.0, screen_shake - delta * 22.0)

	for i in range(bases.size()):
		var base: Dictionary = bases[i]
		base["flash"] = maxf(0.0, float(base["flash"]) - delta)
		bases[i] = base


func _read_player(delta: float) -> void:
	var axis := _axis_from_keys(KEY_A, KEY_D)
	if mode != PlayMode.LOCAL:
		axis = _combined_axis()

	player_pos.x = clampf(player_pos.x + axis * PLAYER_SPEED * delta, SIDE_MARGIN + SHIP_HALF_WIDTH, _playfield_size().x - SIDE_MARGIN - SHIP_HALF_WIDTH)
	player_pos.y = _ship_y()

	if _primary_fire_pressed() and player_cooldown <= 0.0 and state != GameState.GAME_OVER:
		_fire_friendly(player_pos + Vector2(0.0, -31.0), "player")
		player_cooldown = PLAYER_FIRE_INTERVAL * (0.34 if rapid_fire_timer > 0.0 else 1.0)


func _update_coop_ship(delta: float) -> void:
	ai_pos.y = _ship_y()

	if ai_repair_timer > 0.0:
		ai_repair_timer = maxf(0.0, ai_repair_timer - delta)
		if ai_repair_timer <= 0.0:
			ai_hull = AI_STARTING_HULL
			ai_invuln = 1.5
			ai_pos.x = clampf(_playfield_size().x * 0.72, SIDE_MARGIN + SHIP_HALF_WIDTH, _playfield_size().x - SIDE_MARGIN - SHIP_HALF_WIDTH)
			_show_message("P2 revine", 1.0)
		return

	var axis := coop_input_axis
	var wants_fire := coop_input_fire
	if mode == PlayMode.LOCAL:
		axis = _axis_from_keys(KEY_LEFT, KEY_RIGHT)
		wants_fire = _secondary_fire_pressed()

	ai_pos.x += clampf(axis, -1.0, 1.0) * AI_SPEED * delta
	ai_pos.x = clampf(ai_pos.x, SIDE_MARGIN + SHIP_HALF_WIDTH, _playfield_size().x - SIDE_MARGIN - SHIP_HALF_WIDTH)

	if state == GameState.PLAYING and ai_cooldown <= 0.0 and wants_fire:
		_fire_friendly(ai_pos + Vector2(0.0, -31.0), "ai")
		var rapid_scale := 0.36 if rapid_fire_timer > 0.0 else 1.0
		ai_cooldown = AI_FIRE_INTERVAL * rapid_scale


func _read_network_input() -> void:
	coop_input_axis = _combined_axis()
	coop_input_fire = _primary_fire_pressed() or _secondary_fire_pressed()


func _axis_from_keys(left_key: Key, right_key: Key) -> float:
	var axis := 0.0
	if Input.is_key_pressed(left_key):
		axis -= 1.0
	if Input.is_key_pressed(right_key):
		axis += 1.0
	return axis


func _combined_axis() -> float:
	var axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis += 1.0
	return clampf(axis, -1.0, 1.0)


func _primary_fire_pressed() -> bool:
	return Input.is_key_pressed(KEY_SPACE)


func _secondary_fire_pressed() -> bool:
	return Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_K)


func _update_waiting_visuals(delta: float) -> void:
	message_timer = maxf(0.0, message_timer - delta)
	level_banner_timer = maxf(0.0, level_banner_timer - delta)
	screen_shake = maxf(0.0, screen_shake - delta * 22.0)
	_update_particles(delta)
	_update_shockwaves(delta)
	_update_score_popups(delta)


func _ai_desired_x() -> float:
	var size := _playfield_size()
	var dodge_force := 0.0
	var has_threat := false

	for bullet in enemy_bullets:
		var pos: Vector2 = bullet["pos"]
		var vel: Vector2 = bullet["vel"]
		if pos.y > ai_pos.y or vel.y <= 0.0:
			continue

		var time_to_ai := (ai_pos.y - pos.y) / vel.y
		if time_to_ai < 0.0 or time_to_ai > 0.85:
			continue

		var predicted_x := pos.x + vel.x * time_to_ai
		var threat := 74.0 - absf(predicted_x - ai_pos.x)
		if threat > 0.0:
			has_threat = true
			var side := signf(ai_pos.x - predicted_x)
			if side == 0.0:
				side = 1.0 if ai_pos.x > size.x * 0.5 else -1.0
			dodge_force += side * (95.0 + threat)

	if has_threat:
		return clampf(ai_pos.x + dodge_force, SIDE_MARGIN + SHIP_HALF_WIDTH, size.x - SIDE_MARGIN - SHIP_HALF_WIDTH)

	var target := _pick_ai_target()
	var desired_x := size.x * 0.68
	if target.has("pos"):
		var target_pos: Vector2 = target["pos"]
		desired_x = target_pos.x

	if absf(desired_x - player_pos.x) < 86.0:
		desired_x += 116.0 if desired_x >= player_pos.x else -116.0

	return clampf(desired_x, SIDE_MARGIN + SHIP_HALF_WIDTH, size.x - SIDE_MARGIN - SHIP_HALF_WIDTH)


func _pick_ai_target() -> Dictionary:
	var best := {}
	var best_score := 999999.0

	for enemy in enemies:
		var pos: Vector2 = enemy["pos"]
		var horizontal := absf(pos.x - ai_pos.x)
		var row_pressure := pos.y * -0.42
		var player_overlap_penalty := 65.0 if absf(pos.x - player_pos.x) < 54.0 else 0.0
		var score_value := horizontal + row_pressure + player_overlap_penalty
		if score_value < best_score:
			best_score = score_value
			best = enemy

	return best


func _ai_can_fire() -> bool:
	if enemies.is_empty():
		return false

	var target := _enemy_in_lane(ai_pos.x, 38.0)
	if not target.has("pos"):
		return false

	for bullet in bullets:
		var pos: Vector2 = bullet["pos"]
		var owner := str(bullet["owner"])
		if owner == "ai" and absf(pos.x - ai_pos.x) < 16.0 and pos.y > 80.0:
			return false

	return true


func _update_enemies(delta: float) -> void:
	if enemies.is_empty():
		return

	var size := _playfield_size()
	var alive_ratio := float(enemies.size()) / float(ENEMY_COLS * ENEMY_ROWS)
	var speed := ENEMY_BASE_SPEED + float(wave - 1) * 8.0 + (1.0 - alive_ratio) * 92.0
	var hit_edge := false

	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i]
		var pos: Vector2 = enemy["pos"]
		pos.x += enemy_direction * speed * delta
		if pos.x < SIDE_MARGIN + ENEMY_RADIUS or pos.x > size.x - SIDE_MARGIN - ENEMY_RADIUS:
			hit_edge = true
		enemy["pos"] = pos
		enemy["flash"] = maxf(0.0, float(enemy["flash"]) - delta)
		enemies[i] = enemy

	if hit_edge:
		enemy_direction *= -1.0
		for i in range(enemies.size()):
			var enemy: Dictionary = enemies[i]
			var pos: Vector2 = enemy["pos"]
			pos.x = clampf(pos.x, SIDE_MARGIN + ENEMY_RADIUS, size.x - SIDE_MARGIN - ENEMY_RADIUS)
			pos.y += ENEMY_DROP
			enemy["pos"] = pos
			enemies[i] = enemy

	enemy_fire_timer -= delta
	if enemy_fire_timer <= 0.0:
		_enemy_fire()
		var pressure := 1.0 - alive_ratio
		enemy_fire_timer = maxf(0.34, 1.18 - float(wave) * 0.07 - pressure * 0.24 + rng.randf_range(-0.14, 0.22))

	if _lowest_enemy_y() >= _ship_y() - 62.0:
		_defense_breached()


func _update_bullets(delta: float) -> void:
	var size := _playfield_size()

	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[i]
		var pos: Vector2 = bullet["pos"]
		var vel: Vector2 = bullet["vel"]
		pos += vel * delta
		if pos.y < -40.0 or pos.x < -40.0 or pos.x > size.x + 40.0:
			if bool(bullet.get("penalize_miss", false)):
				_add_score(-MISS_SCORE_PENALTY, pos.clamp(Vector2(20.0, 60.0), size - Vector2(20.0, 20.0)), "-MISS %d" % MISS_SCORE_PENALTY)
			bullets.remove_at(i)
			continue
		bullet["pos"] = pos
		bullets[i] = bullet

	for i in range(enemy_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = enemy_bullets[i]
		var pos: Vector2 = bullet["pos"]
		var vel: Vector2 = bullet["vel"]
		pos += vel * delta
		if str(bullet.get("kind", "shot")) == "bomb" and pos.y >= _ship_y() + 24.0:
			_explode_enemy_bomb(pos)
			enemy_bullets.remove_at(i)
			continue
		if pos.y > size.y + 50.0 or pos.x < -50.0 or pos.x > size.x + 50.0:
			enemy_bullets.remove_at(i)
			continue
		bullet["pos"] = pos
		enemy_bullets[i] = bullet


func _update_powerups(delta: float) -> void:
	var size := _playfield_size()

	for i in range(powerups.size() - 1, -1, -1):
		var powerup: Dictionary = powerups[i]
		var pos: Vector2 = powerup["pos"]
		var vel: Vector2 = powerup["vel"]
		vel.y = move_toward(vel.y, POWERUP_FALL_SPEED, 220.0 * delta)
		pos += vel * delta
		pos.x += sin(fx_time * 4.0 + float(powerup["phase"])) * 18.0 * delta

		if pos.y > size.y + 42.0:
			powerups.remove_at(i)
			continue

		powerup["pos"] = pos
		powerup["vel"] = vel
		powerups[i] = powerup

		if pos.distance_squared_to(player_pos) <= pow(POWERUP_COLLECT_RADIUS, 2.0):
			_collect_powerup(i, "Tu")
			continue

		if ai_repair_timer <= 0.0 and pos.distance_squared_to(ai_pos) <= pow(POWERUP_COLLECT_RADIUS, 2.0):
			_collect_powerup(i, "P2")


func _resolve_collisions() -> void:
	_resolve_base_hits()
	_resolve_friendly_hits()
	_resolve_enemy_bullet_hits()


func _resolve_base_hits() -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[i]
		var pos: Vector2 = bullet["pos"]
		if _damage_base_at(pos):
			if bool(bullet.get("penalize_miss", false)):
				_add_score(-MISS_SCORE_PENALTY, pos, "-BASE %d" % MISS_SCORE_PENALTY)
			bullets.remove_at(i)

	for i in range(enemy_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = enemy_bullets[i]
		var pos: Vector2 = bullet["pos"]
		if str(bullet.get("kind", "shot")) == "bomb":
			if _bomb_over_base(pos):
				_explode_enemy_bomb(pos)
				enemy_bullets.remove_at(i)
		elif _damage_base_at(pos):
			enemy_bullets.remove_at(i)


func _resolve_friendly_hits() -> void:
	for bi in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[bi]
		var bullet_pos: Vector2 = bullet["pos"]
		var owner := str(bullet["owner"])
		var weapon := str(bullet.get("weapon", "standard"))
		var bullet_radius := float(bullet.get("radius", 6.0))
		var damage := int(bullet.get("damage", 1))
		var consumed := false

		for ei in range(enemies.size() - 1, -1, -1):
			var enemy: Dictionary = enemies[ei]
			var enemy_pos: Vector2 = enemy["pos"]
			if bullet_pos.distance_squared_to(enemy_pos) > pow(ENEMY_RADIUS + bullet_radius, 2.0):
				continue

			var destroyed := _damage_enemy_segments(enemy, bullet_pos, damage)
			if destroyed:
				_destroy_enemy(ei, enemy, 20 + wave * 5, 28)
			else:
				enemies[ei] = enemy
				_add_score(8, enemy_pos, "+8")
				_spawn_burst(enemy_pos, Color(1, 1, 1, 0.85), 10)

			if float(bullet.get("splash", 0.0)) > 0.0:
				_rocket_splash(enemy_pos, owner, float(bullet.get("splash", 0.0)))
				_spawn_shockwave(enemy_pos, _weapon_color("rocket"), float(bullet.get("splash", 0.0)) * 1.18)
				_spawn_burst(enemy_pos, _weapon_color("rocket"), 42)
				consumed = true
			elif int(bullet.get("pierce", 0)) > 0:
				bullet["pierce"] = int(bullet["pierce"]) - 1
				bullets[bi] = bullet
				consumed = false
			else:
				consumed = true
			break

		if consumed:
			bullets.remove_at(bi)


func _rocket_splash(center: Vector2, owner: String, radius: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		var enemy_pos: Vector2 = enemy["pos"]
		if enemy_pos.distance_to(center) > radius:
			continue

		var destroyed := _damage_enemy_segments(enemy, center, 1)
		if destroyed:
			_destroy_enemy(i, enemy, 16 + wave * 4, 18)
		else:
			enemies[i] = enemy

func _damage_base_at(pos: Vector2) -> bool:
	for base_index in range(bases.size()):
		var base: Dictionary = bases[base_index]
		var origin: Vector2 = base["origin"]
		var local := pos - origin
		if local.x < 0.0 or local.y < 0.0:
			continue

		var col := int(local.x / BASE_CELL_SIZE)
		var row := int(local.y / BASE_CELL_SIZE)
		if col < 0 or col >= BASE_COLS or row < 0 or row >= BASE_ROWS:
			continue

		var cell_index := row * BASE_COLS + col
		var cells: PackedInt32Array = base["cells"]
		if cells[cell_index] <= 0:
			continue

		cells[cell_index] -= 1
		base["cells"] = cells
		base["flash"] = 0.08
		bases[base_index] = base
		var hit_pos := origin + Vector2(float(col) + 0.5, float(row) + 0.5) * BASE_CELL_SIZE
		_spawn_burst(hit_pos, BASE_COLOR, 8)
		_spawn_shockwave(hit_pos, BASE_COLOR, 18.0)
		return true

	return false


func _bomb_over_base(pos: Vector2) -> bool:
	for base in bases:
		var origin: Vector2 = base["origin"]
		var local := pos - origin
		if local.x < -ENEMY_BOMB_RADIUS or local.y < -ENEMY_BOMB_RADIUS:
			continue
		if local.x > float(BASE_COLS) * BASE_CELL_SIZE + ENEMY_BOMB_RADIUS or local.y > float(BASE_ROWS) * BASE_CELL_SIZE + ENEMY_BOMB_RADIUS:
			continue

		var cells: PackedInt32Array = base["cells"]
		for row in range(BASE_ROWS):
			for col in range(BASE_COLS):
				var cell_index := row * BASE_COLS + col
				if cells[cell_index] <= 0:
					continue
				var cell_center := origin + Vector2(float(col) + 0.5, float(row) + 0.5) * BASE_CELL_SIZE
				if cell_center.distance_squared_to(pos) <= pow(ENEMY_BOMB_RADIUS + BASE_CELL_SIZE, 2.0):
					return true
	return false


func _explode_enemy_bomb(pos: Vector2) -> void:
	_damage_bases_in_radius(pos, ENEMY_BOMB_SPLASH_RADIUS)
	if shield_timer > 0.0 and (
		pos.distance_squared_to(player_pos) <= pow(ENEMY_BOMB_SPLASH_RADIUS + 24.0, 2.0)
		or (ai_repair_timer <= 0.0 and pos.distance_squared_to(ai_pos) <= pow(ENEMY_BOMB_SPLASH_RADIUS + 24.0, 2.0))
	):
		shield_timer = maxf(0.0, shield_timer - 1.1)
	else:
		if player_invuln <= 0.0 and pos.distance_squared_to(player_pos) <= pow(ENEMY_BOMB_SPLASH_RADIUS, 2.0):
			_damage_player()
		if ai_repair_timer <= 0.0 and ai_invuln <= 0.0 and pos.distance_squared_to(ai_pos) <= pow(ENEMY_BOMB_SPLASH_RADIUS, 2.0):
			_damage_ai()

	_spawn_burst(pos, ENEMY_BULLET_COLOR, 64)
	_spawn_shockwave(pos, ENEMY_BULLET_COLOR, ENEMY_BOMB_SPLASH_RADIUS * 1.55)
	_kick_shake(7.5)


func _damage_bases_in_radius(pos: Vector2, radius: float) -> void:
	for base_index in range(bases.size()):
		var base: Dictionary = bases[base_index]
		var origin: Vector2 = base["origin"]
		var cells: PackedInt32Array = base["cells"]
		var changed := false
		for row in range(BASE_ROWS):
			for col in range(BASE_COLS):
				var cell_index := row * BASE_COLS + col
				if cells[cell_index] <= 0:
					continue
				var cell_center := origin + Vector2(float(col) + 0.5, float(row) + 0.5) * BASE_CELL_SIZE
				if cell_center.distance_squared_to(pos) <= pow(radius, 2.0):
					cells[cell_index] = max(0, cells[cell_index] - 2)
					changed = true

		if changed:
			base["cells"] = cells
			base["flash"] = 0.14
			bases[base_index] = base


func _resolve_enemy_bullet_hits() -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = enemy_bullets[i]
		var pos: Vector2 = bullet["pos"]
		var is_bomb := str(bullet.get("kind", "shot")) == "bomb"

		if shield_timer > 0.0 and (
			pos.distance_squared_to(player_pos) <= pow(48.0 + (22.0 if is_bomb else 0.0), 2.0)
			or (ai_repair_timer <= 0.0 and pos.distance_squared_to(ai_pos) <= pow(48.0 + (22.0 if is_bomb else 0.0), 2.0))
		):
			enemy_bullets.remove_at(i)
			if is_bomb:
				_explode_enemy_bomb(pos)
			shield_timer = maxf(0.0, shield_timer - (1.1 if is_bomb else 0.45))
			_spawn_burst(pos, _powerup_color("shield"), 12)
			_spawn_shockwave(pos, _powerup_color("shield"), 38.0)
			continue

		if is_bomb and player_invuln <= 0.0 and pos.distance_squared_to(player_pos) <= pow(ENEMY_BOMB_RADIUS + SHIP_HALF_WIDTH, 2.0):
			enemy_bullets.remove_at(i)
			_explode_enemy_bomb(pos)
			continue

		if player_invuln <= 0.0 and _ship_rect(player_pos).has_point(pos):
			enemy_bullets.remove_at(i)
			_damage_player()
			continue

		if is_bomb and ai_repair_timer <= 0.0 and ai_invuln <= 0.0 and pos.distance_squared_to(ai_pos) <= pow(ENEMY_BOMB_RADIUS + SHIP_HALF_WIDTH, 2.0):
			enemy_bullets.remove_at(i)
			_explode_enemy_bomb(pos)
			continue

		if ai_repair_timer <= 0.0 and ai_invuln <= 0.0 and _ship_rect(ai_pos).has_point(pos):
			enemy_bullets.remove_at(i)
			_damage_ai()


func _check_wave_state() -> void:
	if enemies.is_empty() and state == GameState.PLAYING:
		_start_level_complete_bonus()


func _start_level_complete_bonus() -> void:
	state = GameState.LEVEL_BONUS
	bonus_time_remaining = level_time_remaining
	bonus_score_buffer = 0.0
	bonus_popup_points = 0
	bonus_popup_timer = TIME_BONUS_POPUP_INTERVAL
	bullets.clear()
	enemy_bullets.clear()
	powerups.clear()
	var center := Vector2(_playfield_size().x * 0.5, _playfield_size().y * 0.36)
	_add_score(180 + wave * 40, center, "CLEAR +%d" % (180 + wave * 40))
	_spawn_shockwave(center, AI_COLOR, 180.0)
	_spawn_burst(center, AI_COLOR, 70)
	level_banner_timer = 0.0
	_show_message("Bonus timp", 2.0)


func _update_level_bonus(delta: float) -> void:
	if bonus_time_remaining > 0.0:
		var consumed := minf(bonus_time_remaining, TIME_BONUS_COUNT_RATE * delta)
		bonus_time_remaining -= consumed
		level_time_remaining = bonus_time_remaining
		bonus_score_buffer += consumed * float(TIME_BONUS_POINTS_PER_SECOND)
		bonus_popup_timer -= delta
		var whole_points := int(bonus_score_buffer)
		if whole_points > 0:
			bonus_score_buffer -= float(whole_points)
			score = maxi(0, score + whole_points)
			bonus_popup_points += whole_points
		if bonus_popup_points > 0 and (bonus_popup_timer <= 0.0 or bonus_time_remaining <= 0.0):
			_spawn_score_popup(Vector2(_playfield_size().x * 0.5, _playfield_size().y * 0.51), "+TIME %d" % bonus_popup_points, Color("#ffcf5a"))
			bonus_popup_points = 0
			bonus_popup_timer = TIME_BONUS_POPUP_INTERVAL
		return

	level_time_remaining = 0.0
	bonus_time_remaining = 0.0
	if bonus_popup_points > 0:
		_spawn_score_popup(Vector2(_playfield_size().x * 0.5, _playfield_size().y * 0.51), "+TIME %d" % bonus_popup_points, Color("#ffcf5a"))
		bonus_popup_points = 0
	transition_timer = 0.75
	state = GameState.WAVE_TRANSITION


func _fire_friendly(pos: Vector2, owner: String) -> void:
	var weapon := active_weapon if weapon_timer > 0.0 else "standard"
	var penalize_miss := owner == "player" or owner == "ai"
	match weapon:
		"double":
			_spawn_friendly_bullet(pos + Vector2(-10.0, 0.0), Vector2(0.0, -FRIENDLY_BULLET_SPEED), owner, weapon, 5.5, 1, 0, 0.0, penalize_miss)
			_spawn_friendly_bullet(pos + Vector2(10.0, 0.0), Vector2(0.0, -FRIENDLY_BULLET_SPEED), owner, weapon, 5.5, 1, 0, 0.0, false)
		"spread":
			_spawn_friendly_bullet(pos, Vector2(0.0, -FRIENDLY_BULLET_SPEED), owner, weapon, 5.5, 1, 0, 0.0, penalize_miss)
			_spawn_friendly_bullet(pos + Vector2(-8.0, 2.0), Vector2(-155.0, -FRIENDLY_BULLET_SPEED * 0.92), owner, weapon, 5.0, 1, 0, 0.0, false)
			_spawn_friendly_bullet(pos + Vector2(8.0, 2.0), Vector2(155.0, -FRIENDLY_BULLET_SPEED * 0.92), owner, weapon, 5.0, 1, 0, 0.0, false)
		"laser":
			_spawn_friendly_bullet(pos, Vector2(0.0, -FRIENDLY_BULLET_SPEED * 1.35), owner, weapon, 9.0, 1, 4, 0.0, penalize_miss)
		"rocket":
			_spawn_friendly_bullet(pos, Vector2(0.0, -FRIENDLY_BULLET_SPEED * 0.68), owner, weapon, 10.0, 2, 0, ROCKET_SPLASH_RADIUS, penalize_miss)
		_:
			_spawn_friendly_bullet(pos, Vector2(0.0, -FRIENDLY_BULLET_SPEED), owner, weapon, 6.0, 1, 0, 0.0, penalize_miss)

	var color := _weapon_color(weapon) if weapon != "standard" else (PLAYER_COLOR if owner == "player" else AI_COLOR)
	_spawn_burst(pos + Vector2(0.0, 9.0), color, 5)


func _spawn_friendly_bullet(pos: Vector2, vel: Vector2, owner: String, weapon: String, radius: float, damage: int, pierce: int, splash: float, penalize_miss: bool = false) -> void:
	bullets.append({
		"pos": pos,
		"vel": vel,
		"owner": owner,
		"weapon": weapon,
		"radius": radius,
		"damage": damage,
		"pierce": pierce,
		"splash": splash,
		"penalize_miss": penalize_miss
	})


func _spawn_powerup(pos: Vector2, powerup_type: String) -> void:
	if powerups.size() >= MAX_POWERUPS:
		powerups.pop_front()

	var color := _powerup_color(powerup_type)
	powerups.append({
		"pos": pos,
		"vel": Vector2(rng.randf_range(-36.0, 36.0), -70.0),
		"type": powerup_type,
		"phase": rng.randf_range(0.0, TAU)
	})
	_spawn_burst(pos, color, 16)
	_spawn_shockwave(pos, color, 34.0)


func _collect_powerup(index: int, collector: String) -> void:
	if index < 0 or index >= powerups.size():
		return

	var powerup: Dictionary = powerups[index]
	var powerup_type := str(powerup["type"])
	var pos: Vector2 = powerup["pos"]
	var color := _powerup_color(powerup_type)
	powerups.remove_at(index)

	if powerup_type.begins_with("weapon_"):
		active_weapon = powerup_type.replace("weapon_", "")
		weapon_timer = WEAPON_DURATION
		_show_message("%s: arma %s" % [collector, _weapon_name(active_weapon)], 1.35)
	else:
		match powerup_type:
			"rapid":
				rapid_fire_timer = RAPID_FIRE_DURATION
				_show_message("%s: foc rapid" % collector, 1.2)
			"shield":
				shield_timer = SHIELD_DURATION
				_show_message("%s: scut activ" % collector, 1.2)
			"repair":
				if player_lives < STARTING_LIVES:
					player_lives += 1
					_show_message("%s: viata recuperata" % collector, 1.2)
				else:
					ai_hull = mini(AI_STARTING_HULL, ai_hull + 1)
					ai_repair_timer = 0.0
					_show_message("%s: P2 reparat" % collector, 1.2)
			"nova":
				_trigger_nova(pos, collector)

	_add_score(35, pos, "+35")
	_spawn_burst(pos, color, 42)
	_spawn_shockwave(pos, color, 92.0)


func _trigger_nova(pos: Vector2, collector: String) -> void:
	enemy_bullets.clear()
	var hits := 0
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		var enemy_pos: Vector2 = enemy["pos"]
		if enemy_pos.distance_to(pos) > 230.0:
			continue

		var destroyed := _damage_enemy_segments(enemy, pos, 1)
		if destroyed:
			_destroy_enemy(i, enemy, 18 + wave * 4, 18)
		else:
			enemies[i] = enemy
		hits += 1

	_show_message("%s: bomba EMP %d" % [collector, hits], 1.25)


func _powerup_color(powerup_type: String) -> Color:
	match powerup_type:
		"rapid":
			return Color("#62d7ff")
		"shield":
			return Color("#7af0a3")
		"repair":
			return Color("#ffcf5a")
		"nova":
			return Color("#b694ff")
		"weapon_double":
			return Color("#5ee7ff")
		"weapon_spread":
			return Color("#ff9f69")
		"weapon_laser":
			return Color("#ff5fbc")
		"weapon_rocket":
			return Color("#b694ff")
	return Color("#f7f7ff")


func _powerup_label(powerup_type: String) -> String:
	match powerup_type:
		"rapid":
			return "R"
		"shield":
			return "S"
		"repair":
			return "+"
		"nova":
			return "*"
		"weapon_double":
			return "2"
		"weapon_spread":
			return "3"
		"weapon_laser":
			return "L"
		"weapon_rocket":
			return "X"
	return "?"


func _weapon_color(weapon: String) -> Color:
	match weapon:
		"double":
			return Color("#5ee7ff")
		"spread":
			return Color("#ff9f69")
		"laser":
			return Color("#ff5fbc")
		"rocket":
			return Color("#b694ff")
	return FRIENDLY_BULLET_COLOR


func _weapon_name(weapon: String) -> String:
	match weapon:
		"double":
			return "Dublu"
		"spread":
			return "Spread"
		"laser":
			return "Laser"
		"rocket":
			return "Racheta"
	return "Standard"


func _enemy_fire() -> void:
	var shooters := _bottom_enemies()
	if shooters.is_empty():
		return

	var shooter: Dictionary = shooters[rng.randi_range(0, shooters.size() - 1)]
	var pos: Vector2 = shooter["pos"]
	var bomb_chance := minf(0.52, ENEMY_BOMB_CHANCE + float(wave - 1) * 0.035)
	if rng.randf() < bomb_chance:
		_spawn_enemy_bomb(pos + Vector2(rng.randf_range(-8.0, 8.0), 22.0))
		if rng.randf() < 0.45:
			return

	var aim_x := player_pos.x
	if ai_repair_timer <= 0.0 and rng.randf() < 0.46:
		aim_x = ai_pos.x
	var drift := clampf((aim_x - pos.x) * 0.18, -76.0, 76.0)

	enemy_bullets.append({
		"pos": pos + Vector2(0.0, 18.0),
		"vel": Vector2(drift, ENEMY_BULLET_SPEED + float(wave - 1) * 9.0),
		"kind": "shot",
		"phase": rng.randf_range(0.0, TAU)
	})
	_spawn_burst(pos + Vector2(0.0, 18.0), ENEMY_BULLET_COLOR, 4)


func _spawn_enemy_bomb(pos: Vector2) -> void:
	enemy_bullets.append({
		"pos": pos,
		"vel": Vector2(rng.randf_range(-20.0, 20.0), ENEMY_BOMB_SPEED + float(wave - 1) * 10.0),
		"kind": "bomb",
		"phase": rng.randf_range(0.0, TAU)
	})
	_spawn_burst(pos, ENEMY_BULLET_COLOR, 10)
	_spawn_shockwave(pos, ENEMY_BULLET_COLOR, 26.0)


func _bottom_enemies() -> Array[Dictionary]:
	var by_col := {}
	for enemy in enemies:
		var col := int(enemy["col"])
		var pos: Vector2 = enemy["pos"]
		if not by_col.has(col):
			by_col[col] = enemy
		else:
			var current: Dictionary = by_col[col]
			var current_pos: Vector2 = current["pos"]
			if pos.y > current_pos.y:
				by_col[col] = enemy

	var result: Array[Dictionary] = []
	for key in by_col.keys():
		result.append(by_col[key])
	return result


func _enemy_in_lane(x: float, lane_width: float) -> Dictionary:
	var best := {}
	var best_y := -999999.0
	for enemy in enemies:
		var pos: Vector2 = enemy["pos"]
		if absf(pos.x - x) <= lane_width and pos.y > best_y:
			best_y = pos.y
			best = enemy
	return best


func _damage_player() -> void:
	if state == GameState.GAME_OVER:
		return

	player_lives -= 1
	player_invuln = PLAYER_INVULN_TIME
	_spawn_burst(player_pos, PLAYER_COLOR, 42)
	_spawn_shockwave(player_pos, PLAYER_COLOR, 96.0)
	_kick_shake(8.0)

	if player_lives <= 0:
		state = GameState.GAME_OVER
		enemy_bullets.clear()
		_show_message("Misiune pierduta", 999.0)
	else:
		_show_message("Nava ta a fost lovita", 1.1)


func _damage_ai() -> void:
	ai_hull -= 1
	ai_invuln = 1.1
	_spawn_burst(ai_pos, AI_COLOR, 34)
	_spawn_shockwave(ai_pos, AI_COLOR, 76.0)
	_kick_shake(5.6)

	if ai_hull <= 0:
		ai_hull = 0
		ai_repair_timer = AI_REPAIR_TIME
		_show_message("P2 in reparatii", 1.3)
	else:
		_show_message("P2 lovit", 0.9)


func _defense_breached() -> void:
	var breach_pos := Vector2(_playfield_size().x * 0.5, _ship_y() - 54.0)
	_spawn_burst(breach_pos, ENEMY_BULLET_COLOR, 90)
	_spawn_shockwave(breach_pos, ENEMY_BULLET_COLOR, 190.0)
	player_lives -= 1
	player_invuln = PLAYER_INVULN_TIME
	enemy_bullets.clear()

	if player_lives <= 0:
		state = GameState.GAME_OVER
		_show_message("Linia a cazut", 999.0)
	else:
		_show_message("Linie strapunsa", 1.3)
		_build_wave()


func _build_starfield() -> void:
	stars.clear()
	var size := _playfield_size()
	for _i in range(STAR_COUNT):
		stars.append({
			"pos": Vector2(rng.randf_range(0.0, size.x), rng.randf_range(0.0, size.y)),
			"speed": rng.randf_range(8.0, 34.0),
			"radius": rng.randf_range(0.8, 2.0),
			"alpha": rng.randf_range(0.26, 0.82)
		})


func _update_starfield(delta: float) -> void:
	var size := _playfield_size()
	for i in range(stars.size()):
		var star: Dictionary = stars[i]
		var pos: Vector2 = star["pos"]
		pos.y += float(star["speed"]) * delta
		if pos.y > size.y:
			pos.y = 0.0
			pos.x = rng.randf_range(0.0, size.x)
		star["pos"] = pos
		stars[i] = star


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[i]
		var life := float(particle["life"]) - delta
		if life <= 0.0:
			particles.remove_at(i)
			continue

		var pos: Vector2 = particle["pos"]
		var vel: Vector2 = particle["vel"]
		pos += vel * delta
		vel *= 0.92
		particle["pos"] = pos
		particle["vel"] = vel
		particle["life"] = life
		particles[i] = particle


func _update_shockwaves(delta: float) -> void:
	for i in range(shockwaves.size() - 1, -1, -1):
		var shockwave: Dictionary = shockwaves[i]
		var life := float(shockwave["life"]) - delta
		if life <= 0.0:
			shockwaves.remove_at(i)
			continue

		shockwave["life"] = life
		shockwaves[i] = shockwave


func _update_score_popups(delta: float) -> void:
	for i in range(score_popups.size() - 1, -1, -1):
		var popup: Dictionary = score_popups[i]
		var life := float(popup["life"]) - delta
		if life <= 0.0:
			score_popups.remove_at(i)
			continue

		var pos: Vector2 = popup["pos"]
		var vel: Vector2 = popup["vel"]
		pos += vel * delta
		vel *= 0.92
		popup["pos"] = pos
		popup["vel"] = vel
		popup["life"] = life
		score_popups[i] = popup


func _spawn_burst(pos: Vector2, color: Color, count: int) -> void:
	for _i in range(count):
		if particles.size() >= MAX_PARTICLES:
			particles.pop_front()
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(70.0, 260.0)
		var life := rng.randf_range(0.28, 0.72)
		var size := rng.randf_range(1.5, 4.8)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"life": life,
			"max_life": life,
			"size": size,
			"color": color
		})


func _spawn_shockwave(pos: Vector2, color: Color, radius: float) -> void:
	if shockwaves.size() >= MAX_SHOCKWAVES:
		shockwaves.pop_front()
	var life := 0.48
	shockwaves.append({
		"pos": pos,
		"life": life,
		"max_life": life,
		"radius": radius,
		"color": color
	})


func _kick_shake(amount: float) -> void:
	screen_shake = minf(14.0, screen_shake + amount)


func _shake_offset() -> Vector2:
	if screen_shake <= 0.01:
		return Vector2.ZERO
	return Vector2(
		sin(fx_time * 74.0) * screen_shake + sin(fx_time * 19.0) * screen_shake * 0.45,
		cos(fx_time * 61.0) * screen_shake * 0.75
	)


func _draw_stars() -> void:
	for star in stars:
		var pos: Vector2 = star["pos"]
		var alpha := float(star["alpha"])
		var radius := float(star["radius"])
		var speed := float(star["speed"])
		draw_circle(pos, radius, Color(0.8, 0.9, 1.0, alpha))
		if speed > 24.0:
			draw_line(pos + Vector2(0.0, -speed * 0.22), pos, Color(0.58, 0.76, 1.0, alpha * 0.28), maxf(1.0, radius))


func _draw_background_effects(size: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(fx_time * 0.7)
	draw_circle(Vector2(size.x * 0.20 + sin(fx_time * 0.23) * 60.0, size.y * 0.24), 260.0, Color(0.16, 0.33, 0.56, 0.08 + pulse * 0.025))
	draw_circle(Vector2(size.x * 0.82 + cos(fx_time * 0.19) * 70.0, size.y * 0.42), 310.0, Color(0.42, 0.16, 0.38, 0.055))
	draw_circle(Vector2(size.x * 0.52, size.y * 0.86 + sin(fx_time * 0.31) * 28.0), 250.0, Color(0.13, 0.42, 0.28, 0.045))

	for y in range(0, int(size.y), 36):
		var offset := sin(fx_time * 1.3 + float(y) * 0.03) * 22.0
		draw_line(Vector2(offset, float(y)), Vector2(size.x + offset, float(y)), Color(1, 1, 1, 0.018), 1.0)


func _draw_arena(size: Vector2) -> void:
	var defense_y := _ship_y() - 58.0
	var scan_y := fmod(fx_time * 110.0, size.y)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 5.0)), Color("#62d7ff"), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 32.0)), Color(0.18, 0.52, 0.75, 0.035), true)
	draw_rect(Rect2(Vector2(0.0, defense_y), Vector2(size.x, 2.0)), Color(1, 1, 1, 0.10), true)
	draw_rect(Rect2(Vector2(0.0, scan_y), Vector2(size.x, 2.0)), Color(0.65, 0.9, 1.0, 0.10), true)

	for x in range(0, int(size.x), 48):
		var alpha := 0.12 + 0.08 * sin(fx_time * 4.0 + float(x) * 0.04)
		draw_rect(Rect2(Vector2(float(x), defense_y), Vector2(20.0, 2.0)), Color(1, 1, 1, alpha), true)


func _draw_bases() -> void:
	for base in bases:
		var origin: Vector2 = base["origin"]
		var cells: PackedInt32Array = base["cells"]
		var flash := float(base["flash"])
		var color := Color(1, 1, 1, 0.9) if flash > 0.0 else BASE_COLOR
		var shadow_rect := Rect2(origin + Vector2(-5.0, 4.0), Vector2(float(BASE_COLS) * BASE_CELL_SIZE + 10.0, float(BASE_ROWS) * BASE_CELL_SIZE))
		var glow := 0.08 + 0.04 * sin(fx_time * 4.0 + origin.x * 0.01)
		draw_rect(shadow_rect.grow(5.0), Color(BASE_COLOR.r, BASE_COLOR.g, BASE_COLOR.b, glow), true)
		draw_rect(shadow_rect, Color(BASE_COLOR.r, BASE_COLOR.g, BASE_COLOR.b, 0.08), true)

		for row in range(BASE_ROWS):
			for col in range(BASE_COLS):
				var cell_index := row * BASE_COLS + col
				var hp := cells[cell_index]
				if hp <= 0:
					continue

				var rect := Rect2(
					origin + Vector2(float(col), float(row)) * BASE_CELL_SIZE,
					Vector2(BASE_CELL_SIZE - 1.0, BASE_CELL_SIZE - 1.0)
				)
				var cell_color := color if hp >= BASE_HP else BASE_COLOR.darkened(0.35)
				draw_rect(rect, cell_color, true)
				draw_rect(rect.grow(1.5), Color(BASE_COLOR.r, BASE_COLOR.g, BASE_COLOR.b, 0.035), true)
				if hp >= BASE_HP:
					draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)), Color(1, 1, 1, 0.24), true)


func _draw_enemies() -> void:
	for enemy in enemies:
		var pos: Vector2 = enemy["pos"]
		var row := int(enemy["row"])
		var col := int(enemy["col"])
		var bob := sin(fx_time * 4.2 + float(row) * 0.8 + float(col) * 0.35) * 3.5
		var draw_pos := pos + Vector2(0.0, bob)
		var color: Color = ENEMY_COLORS[row % ENEMY_COLORS.size()]
		if float(enemy["flash"]) > 0.0:
			color = Color(1, 1, 1, 0.96)
		_draw_enemy(draw_pos, color, enemy, str(enemy.get("drop_type", "")))


func _draw_enemy(pos: Vector2, color: Color, enemy: Dictionary, drop_type: String) -> void:
	var glow_alpha := 0.09 + 0.04 * sin(fx_time * 5.0 + pos.x * 0.04)
	var segments: PackedInt32Array = enemy["segments"]
	var alive_segments := _enemy_segments_alive_from_cells(segments)
	draw_circle(pos, 27.0, Color(color.r, color.g, color.b, glow_alpha))
	draw_rect(Rect2(pos - Vector2(22.0, 14.0), Vector2(44.0, 28.0)), Color(color.r, color.g, color.b, 0.09), true)

	var origin := pos - Vector2(float(ENEMY_SEG_COLS) * ENEMY_SEG_SIZE, float(ENEMY_SEG_ROWS) * ENEMY_SEG_SIZE) * 0.5
	for segment_row in range(ENEMY_SEG_ROWS):
		for segment_col in range(ENEMY_SEG_COLS):
			var segment_index := segment_row * ENEMY_SEG_COLS + segment_col
			if segments[segment_index] <= 0:
				continue

			var rect := Rect2(
				origin + Vector2(float(segment_col), float(segment_row)) * ENEMY_SEG_SIZE,
				Vector2(ENEMY_SEG_SIZE - 1.0, ENEMY_SEG_SIZE - 1.0)
			)
			var segment_color := color.lightened(0.12) if float(enemy["flash"]) > 0.0 else color
			if alive_segments <= 3:
				segment_color = color.darkened(0.22)
			draw_rect(rect.grow(1.0), Color(color.r, color.g, color.b, 0.08), true)
			draw_rect(rect, segment_color, true)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)), Color(1, 1, 1, 0.18), true)

	if segments[ENEMY_SEG_COLS + 1] > 0:
		draw_rect(Rect2(origin + Vector2(1.0, 1.0) * ENEMY_SEG_SIZE + Vector2(2.0, 2.0), Vector2(3.0, 3.0)), BG_COLOR, true)
	if segments[ENEMY_SEG_COLS + 3] > 0:
		draw_rect(Rect2(origin + Vector2(3.0, 1.0) * ENEMY_SEG_SIZE + Vector2(3.0, 2.0), Vector2(3.0, 3.0)), BG_COLOR, true)

	if not drop_type.is_empty():
		var power_color := _powerup_color(drop_type)
		var pulse := 0.5 + 0.5 * sin(fx_time * 8.0 + pos.x * 0.02)
		draw_circle(pos + Vector2(0.0, -1.0), 8.0 + pulse * 2.0, Color(power_color.r, power_color.g, power_color.b, 0.30))
		_draw_diamond(pos + Vector2(0.0, -1.0), 6.0, power_color)


func _draw_bullets() -> void:
	for bullet in bullets:
		var pos: Vector2 = bullet["pos"]
		var owner := str(bullet["owner"])
		var weapon := str(bullet.get("weapon", "standard"))
		var color := _weapon_color(weapon) if weapon != "standard" else (FRIENDLY_BULLET_COLOR if owner == "player" else AI_COLOR.lightened(0.25))
		var vel: Vector2 = bullet["vel"]
		var dir := vel.normalized()
		var side := Vector2(-dir.y, dir.x)

		if weapon == "laser":
			draw_line(pos + dir * 34.0, pos - dir * 40.0, Color(color.r, color.g, color.b, 0.28), 13.0)
			draw_line(pos + dir * 34.0, pos - dir * 40.0, Color(color.r, color.g, color.b, 0.92), 4.0)
			draw_circle(pos, 13.0, Color(color.r, color.g, color.b, 0.18))
		elif weapon == "rocket":
			draw_line(pos - dir * 30.0, pos - dir * 8.0, Color(1.0, 0.55, 0.18, 0.35), 10.0)
			draw_circle(pos, 14.0, Color(color.r, color.g, color.b, 0.18))
			draw_polygon(PackedVector2Array([
				pos + dir * 13.0,
				pos - dir * 10.0 + side * 8.0,
				pos - dir * 5.0,
				pos - dir * 10.0 - side * 8.0
			]), PackedColorArray([color]))
		else:
			draw_line(pos + dir * -24.0, pos + dir * -2.0, Color(color.r, color.g, color.b, 0.22), 8.0)
			draw_line(pos + dir * -18.0, pos + dir * 12.0, Color(color.r, color.g, color.b, 0.68), 3.0)
			draw_circle(pos, 10.0, Color(color.r, color.g, color.b, 0.18))
			draw_rect(Rect2(pos - Vector2(2.0, 12.0), Vector2(4.0, 19.0)), color, true)

	for bullet in enemy_bullets:
		var pos: Vector2 = bullet["pos"]
		var kind := str(bullet.get("kind", "shot"))
		if kind == "bomb":
			var pulse := 0.5 + 0.5 * sin(fx_time * 9.0 + float(bullet.get("phase", 0.0)))
			draw_line(pos - Vector2(0.0, 34.0), pos - Vector2(0.0, 12.0), Color(1.0, 0.24, 0.26, 0.20), 8.0)
			draw_circle(pos, 24.0 + pulse * 6.0, Color(1.0, 0.16, 0.20, 0.16))
			draw_circle(pos, ENEMY_BOMB_RADIUS, ENEMY_BULLET_COLOR)
			draw_circle(pos + Vector2(-4.0, -4.0), 4.0, Color(1, 1, 1, 0.38))
			draw_arc(pos, ENEMY_BOMB_RADIUS + 7.0, fx_time * 4.0, fx_time * 4.0 + PI * 1.35, 30, Color(1.0, 0.62, 0.30, 0.70), 2.0)
		else:
			draw_line(pos - Vector2(0.0, 19.0), pos + Vector2(0.0, 10.0), Color(1.0, 0.30, 0.40, 0.22), 9.0)
			draw_line(pos - Vector2(0.0, 12.0), pos + Vector2(0.0, 14.0), Color(1.0, 0.42, 0.50, 0.68), 3.0)
			draw_circle(pos, 10.0, Color(1, 0.36, 0.45, 0.16))
			draw_rect(Rect2(pos - Vector2(3.0, 5.0), Vector2(6.0, 14.0)), ENEMY_BULLET_COLOR, true)


func _draw_powerups() -> void:
	for powerup in powerups:
		var pos: Vector2 = powerup["pos"]
		var powerup_type := str(powerup["type"])
		var color := _powerup_color(powerup_type)
		var pulse := 0.5 + 0.5 * sin(fx_time * 7.2 + float(powerup["phase"]))
		var bob := Vector2(0.0, sin(fx_time * 5.0 + float(powerup["phase"])) * 3.5)
		var draw_pos := pos + bob

		draw_circle(draw_pos, 24.0 + pulse * 6.0, Color(color.r, color.g, color.b, 0.14))
		draw_circle(draw_pos, 13.0, Color(0.05, 0.07, 0.13, 0.86))
		_draw_diamond(draw_pos, 13.0, Color(color.r, color.g, color.b, 0.92))
		_draw_diamond(draw_pos, 7.0, Color(1, 1, 1, 0.52))
		draw_string(ThemeDB.fallback_font, draw_pos + Vector2(-5.0, 5.0), _powerup_label(powerup_type), HORIZONTAL_ALIGNMENT_CENTER, 10.0, 14, Color(0.03, 0.05, 0.08, 0.92))


func _draw_ships() -> void:
	var player_draw_pos := player_pos + Vector2(0.0, sin(fx_time * 8.0) * 1.6)
	if shield_timer > 0.0:
		_draw_active_shield(player_draw_pos, PLAYER_COLOR)
	if rapid_fire_timer > 0.0:
		_draw_rapid_aura(player_draw_pos, PLAYER_COLOR)
	if active_weapon != "standard" and weapon_timer > 0.0:
		_draw_weapon_aura(player_draw_pos)
	_draw_ship(player_draw_pos, PLAYER_COLOR, player_invuln, false)
	if ai_repair_timer <= 0.0:
		var ai_draw_pos := ai_pos + Vector2(0.0, sin(fx_time * 7.4 + 1.3) * 1.8)
		if shield_timer > 0.0:
			_draw_active_shield(ai_draw_pos, AI_COLOR)
		if rapid_fire_timer > 0.0:
			_draw_rapid_aura(ai_draw_pos, AI_COLOR)
		if active_weapon != "standard" and weapon_timer > 0.0:
			_draw_weapon_aura(ai_draw_pos)
		_draw_ship(ai_draw_pos, AI_COLOR, ai_invuln, true)
	else:
		var alpha := 0.22 + 0.12 * sin(Time.get_ticks_msec() * 0.012)
		draw_circle(ai_pos, 32.0, Color(AI_COLOR.r, AI_COLOR.g, AI_COLOR.b, alpha))
		draw_arc(ai_pos, 34.0, -PI * 0.5, PI * 1.5, 36, Color(AI_COLOR.r, AI_COLOR.g, AI_COLOR.b, 0.32), 2.0)


func _draw_ship(pos: Vector2, color: Color, invuln: float, is_ai: bool) -> void:
	if invuln > 0.0 and int(invuln * 18.0) % 2 == 0:
		return

	var pulse := 0.5 + 0.5 * sin(fx_time * 6.0 + (1.4 if is_ai else 0.0))
	draw_circle(pos, 42.0 + pulse * 5.0, Color(color.r, color.g, color.b, 0.10 + pulse * 0.03))
	draw_circle(pos + Vector2(0.0, 8.0), 27.0, Color(color.r, color.g, color.b, 0.12))

	var hull := PackedVector2Array([
		pos + Vector2(0.0, -30.0),
		pos + Vector2(25.0, 17.0),
		pos + Vector2(10.0, 12.0),
		pos + Vector2(0.0, 27.0),
		pos + Vector2(-10.0, 12.0),
		pos + Vector2(-25.0, 17.0)
	])
	draw_polygon(hull, PackedColorArray([color]))
	draw_polyline(hull, Color(1, 1, 1, 0.28), 2.0, true)
	draw_circle(pos + Vector2(0.0, -4.0), 7.0, Color(0.08, 0.10, 0.18, 0.72))

	var flame_color := Color("#7af0a3") if is_ai else Color("#ffcf5a")
	draw_circle(pos + Vector2(0.0, 27.0), 16.0 + pulse * 6.0, Color(flame_color.r, flame_color.g, flame_color.b, 0.13))
	draw_polygon(PackedVector2Array([
		pos + Vector2(-7.0, 20.0),
		pos + Vector2(0.0, 40.0 + pulse * 7.0 + rng.randf_range(-2.0, 3.0)),
		pos + Vector2(7.0, 20.0)
	]), PackedColorArray([Color(flame_color.r, flame_color.g, flame_color.b, 0.64)]))

	if is_ai:
		draw_circle(pos + Vector2(-18.0, 4.0), 4.0, Color(1, 1, 1, 0.28))
		draw_circle(pos + Vector2(18.0, 4.0), 4.0, Color(1, 1, 1, 0.28))


func _draw_active_shield(pos: Vector2, color: Color) -> void:
	var pulse := 0.5 + 0.5 * sin(fx_time * 9.0)
	draw_circle(pos, 51.0 + pulse * 4.0, Color(BASE_COLOR.r, BASE_COLOR.g, BASE_COLOR.b, 0.11))
	draw_arc(pos, 49.0 + pulse * 4.0, 0.0, TAU, 72, Color(BASE_COLOR.r, BASE_COLOR.g, BASE_COLOR.b, 0.54), 2.2)
	draw_arc(pos, 39.0, fx_time * 2.4, fx_time * 2.4 + PI * 1.35, 42, Color(color.r, color.g, color.b, 0.34), 2.0)


func _draw_rapid_aura(pos: Vector2, color: Color) -> void:
	for i in range(3):
		var angle := fx_time * 8.0 + float(i) * TAU / 3.0
		var start := pos + Vector2(cos(angle), sin(angle)) * 36.0
		var end := pos + Vector2(cos(angle + 0.55), sin(angle + 0.55)) * 45.0
		draw_line(start, end, Color(color.r, color.g, color.b, 0.45), 2.0)


func _draw_weapon_aura(pos: Vector2) -> void:
	var color := _weapon_color(active_weapon)
	var pulse := 0.5 + 0.5 * sin(fx_time * 10.0)
	draw_arc(pos, 58.0 + pulse * 5.0, fx_time * -2.0, fx_time * -2.0 + PI * 1.45, 48, Color(color.r, color.g, color.b, 0.42), 2.6)
	draw_arc(pos, 63.0, fx_time * 2.3, fx_time * 2.3 + PI * 0.95, 42, Color(1, 1, 1, 0.16), 1.4)


func _draw_diamond(pos: Vector2, radius: float, color: Color) -> void:
	draw_polygon(PackedVector2Array([
		pos + Vector2(0.0, -radius),
		pos + Vector2(radius, 0.0),
		pos + Vector2(0.0, radius),
		pos + Vector2(-radius, 0.0)
	]), PackedColorArray([color]))


func _draw_particles() -> void:
	for particle in particles:
		var pos: Vector2 = particle["pos"]
		var life := float(particle["life"])
		var max_life := float(particle["max_life"])
		var color: Color = particle["color"]
		var size := float(particle.get("size", 3.0))
		var alpha := clampf(life / max_life, 0.0, 1.0)
		var vel: Vector2 = particle["vel"]
		if vel.length_squared() > 1.0:
			draw_line(pos - vel.normalized() * size * 2.4, pos, Color(color.r, color.g, color.b, color.a * alpha * 0.34), maxf(1.0, size))
		draw_circle(pos, size + alpha * 2.2, Color(color.r, color.g, color.b, color.a * alpha))


func _draw_shockwaves() -> void:
	for shockwave in shockwaves:
		var pos: Vector2 = shockwave["pos"]
		var life := float(shockwave["life"])
		var max_life := float(shockwave["max_life"])
		var color: Color = shockwave["color"]
		var progress := 1.0 - clampf(life / max_life, 0.0, 1.0)
		var radius := float(shockwave["radius"]) * progress
		var alpha := (1.0 - progress) * 0.42
		draw_arc(pos, radius, 0.0, TAU, 72, Color(color.r, color.g, color.b, alpha), 3.0)
		draw_arc(pos, radius * 0.62, 0.0, TAU, 72, Color(1, 1, 1, alpha * 0.22), 1.0)


func _draw_score_popups() -> void:
	var font := ThemeDB.fallback_font
	for popup in score_popups:
		var pos: Vector2 = popup["pos"]
		var life := float(popup["life"])
		var max_life := float(popup["max_life"])
		var alpha := clampf(life / max_life, 0.0, 1.0)
		var text := str(popup["text"])
		var color: Color = popup["color"]
		var font_size := 20
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(font, pos + Vector2(-width * 0.5 + 2.0, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0, 0, 0, alpha * 0.72))
		draw_string(font, pos + Vector2(-width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(color.r, color.g, color.b, alpha))


func _ship_rect(pos: Vector2) -> Rect2:
	return Rect2(pos - Vector2(SHIP_HALF_WIDTH, SHIP_HALF_HEIGHT), Vector2(SHIP_HALF_WIDTH * 2.0, SHIP_HALF_HEIGHT * 2.0))


func _ship_y() -> float:
	return _playfield_size().y - SHIP_Y_MARGIN


func _playfield_size() -> Vector2:
	return get_viewport_rect().size


func _lowest_enemy_y() -> float:
	var y := -999999.0
	for enemy in enemies:
		var pos: Vector2 = enemy["pos"]
		y = maxf(y, pos.y)
	return y


func _show_message(text: String, duration: float) -> void:
	message = text
	message_timer = duration


func _start_level_intro() -> void:
	state = GameState.LEVEL_INTRO
	level_intro_timer = LEVEL_INTRO_DURATION
	_show_level_banner("LEVEL %d" % wave, LEVEL_INTRO_DURATION)
	_show_message("Pregatire", LEVEL_INTRO_DURATION)


func _show_level_banner(text: String, duration: float = 1.55) -> void:
	level_banner_text = text
	level_banner_timer = duration
	level_banner_duration = duration


func _draw_level_banner(size: Vector2) -> void:
	if level_banner_timer <= 0.0:
		return

	var progress := 1.0 - clampf(level_banner_timer / maxf(level_banner_duration, 0.01), 0.0, 1.0)
	var fade_in := clampf(progress / 0.16, 0.0, 1.0)
	var fade_out := clampf((1.0 - progress) / 0.18, 0.0, 1.0)
	var alpha := minf(fade_in, fade_out)
	var scale := 1.18 - progress * 0.18
	var font := ThemeDB.fallback_font
	var font_size := int(82.0 * scale)
	var sub_size := int(22.0 * scale)
	var title_width := font.get_string_size(level_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var y := size.y * 0.34
	var x := size.x * 0.5 - title_width * 0.5
	var panel_size := Vector2(minf(size.x - 56.0, 640.0), 174.0)
	var panel := Rect2(Vector2(size.x * 0.5 - panel_size.x * 0.5, y - 103.0), panel_size)
	var color := Color(0.86, 0.98, 1.0, alpha)
	var glow := Color(0.27, 0.72, 1.0, alpha * 0.18)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, alpha * 0.18), true)
	draw_rect(panel, Color(0.02, 0.04, 0.08, alpha * 0.78), true)
	draw_rect(panel, Color(0.24, 0.72, 1.0, alpha * 0.64), false, 3.0)
	draw_line(panel.position + Vector2(24.0, 18.0), panel.position + Vector2(panel.size.x - 24.0, 18.0), Color(1.0, 0.81, 0.35, alpha * 0.55), 2.0)
	draw_line(panel.position + Vector2(24.0, panel.size.y - 18.0), panel.position + Vector2(panel.size.x - 24.0, panel.size.y - 18.0), Color(1.0, 0.81, 0.35, alpha * 0.55), 2.0)
	draw_circle(Vector2(size.x * 0.5, y - 22.0), 180.0 * scale, glow)
	draw_string(font, Vector2(x + 4.0, y + 4.0), level_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.05, 0.08, 0.14, alpha * 0.88))
	draw_string(font, Vector2(x, y), level_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

	var subtitle := "GET READY" if state == GameState.LEVEL_INTRO else "READY"
	var subtitle_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sub_size).x
	draw_string(font, Vector2(size.x * 0.5 - subtitle_width * 0.5, y + 38.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sub_size, Color(1.0, 0.81, 0.35, alpha * 0.84))


func _draw_bonus_countdown(size: Vector2) -> void:
	if state != GameState.LEVEL_BONUS:
		return

	var font := ThemeDB.fallback_font
	var title := "LEVEL COMPLETED"
	var title_size := 54
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size).x
	var center := Vector2(size.x * 0.5, size.y * 0.42)
	var alpha := 0.88
	var bonus_text := "TIME BONUS  %s  x%d" % [_format_time(bonus_time_remaining), TIME_BONUS_POINTS_PER_SECOND]
	var bonus_size := 24
	var bonus_width := font.get_string_size(bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, bonus_size).x

	draw_rect(Rect2(Vector2(0.0, center.y - 92.0), Vector2(size.x, 150.0)), Color(0, 0, 0, 0.24), true)
	draw_circle(center - Vector2(0.0, 28.0), 190.0, Color(0.26, 0.72, 1.0, 0.10))
	draw_string(font, Vector2(center.x - title_width * 0.5 + 3.0, center.y - 38.0 + 3.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, Color(0.03, 0.05, 0.08, alpha))
	draw_string(font, Vector2(center.x - title_width * 0.5, center.y - 38.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, Color(0.86, 0.98, 1.0, alpha))
	draw_string(font, Vector2(center.x - bonus_width * 0.5, center.y + 18.0), bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, bonus_size, Color(1.0, 0.81, 0.35, alpha))


func _refresh_hud() -> void:
	score_label.text = "SCORE %06d" % score
	if state == GameState.LEVEL_BONUS:
		timer_label.text = "BONUS %s" % _format_time(bonus_time_remaining)
	else:
		timer_label.text = _format_time(level_time_remaining)
	lives_label.text = "Vieti %d  Val %d" % [maxi(player_lives, 0), wave]

	if mode == PlayMode.HOST and right_peer_id == 0:
		ai_label.text = "P2 asteptare LAN"
	elif mode == PlayMode.CLIENT:
		ai_label.text = "P2 CLIENT"
	elif ai_repair_timer > 0.0:
		ai_label.text = "P2 reparatii %.1fs" % ai_repair_timer
	else:
		ai_label.text = "P2 hull %d" % ai_hull

	if state == GameState.GAME_OVER:
		status_label.text = "Misiune pierduta"
	elif mode == PlayMode.MENU:
		status_label.text = "Caut coechipier in LAN..."
	elif mode == PlayMode.HOST and right_peer_id == 0:
		status_label.text = "Host P1: asteapta P2 in LAN"
	elif mode == PlayMode.CLIENT and not client_ready:
		status_label.text = "P2: conectare..."
	elif message_timer > 0.0:
		status_label.text = message
	elif rapid_fire_timer > 0.0 or shield_timer > 0.0 or (active_weapon != "standard" and weapon_timer > 0.0):
		var parts: Array[String] = []
		if active_weapon != "standard" and weapon_timer > 0.0:
			parts.append("%s %.0fs" % [_weapon_name(active_weapon), weapon_timer])
		if rapid_fire_timer > 0.0:
			parts.append("Foc rapid %.0fs" % rapid_fire_timer)
		if shield_timer > 0.0:
			parts.append("Scut %.0fs" % shield_timer)
		status_label.text = "  |  ".join(parts)
	elif mode == PlayMode.LOCAL:
		status_label.text = "Coop local"
	elif mode == PlayMode.CLIENT:
		status_label.text = "P2 conectat"
	elif mode == PlayMode.HOST:
		status_label.text = "P1 HOST + P2 LAN"
	else:
		status_label.text = "Coop network"


func _format_time(seconds: float) -> String:
	var whole := maxi(0, int(ceil(seconds)))
	var minutes := int(whole / 60)
	var secs := whole % 60
	return "%02d:%02d" % [minutes, secs]
