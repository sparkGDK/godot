extends Node2D

class Worker:
	var id := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dir := 1
	var skill := "walker"
	var alive := true
	var saved := false
	var floater := false
	var build_steps := 0
	var build_timer := 0.0
	var bash_timer := 0.0
	var dig_timer := 0.0
	var fall_speed_peak := 0.0
	var blink := 0.0


const TILE := 8
const GRID_W := 200
const GRID_H := 90
const WORLD_W := GRID_W * TILE
const WORLD_H := GRID_H * TILE
const HUD_H := 84.0
const WALK_SPEED := 47.0
const BASH_SPEED := 33.0
const GRAVITY := 920.0
const MAX_FALL_SPEED := 430.0
const FLOAT_SPEED := 88.0
const SAFE_LANDING_SPEED := 345.0
const MAX_STEP_UP := 12
const SPAWN_INTERVAL := 0.82
const WORKER_RADIUS := 5.0
const BODY_H := 17.0
const BUILDER_INTERVAL := 0.17
const BUILDER_STEPS := 15
const BUILDER_RUN := 12.0
const BUILDER_RISE := 3.5
const BUILDER_RAMP_THICKNESS := 5.0
const DIG_INTERVAL := 0.08
const BASH_LIMIT := 4.2

const TOOLS := [
	{"id": "builder", "name": "Builder", "key": "1", "color": Color("#ffd166")},
	{"id": "digger", "name": "Digger", "key": "2", "color": Color("#8fd694")},
	{"id": "basher", "name": "Basher", "key": "3", "color": Color("#ff8fab")},
	{"id": "blocker", "name": "Blocker", "key": "4", "color": Color("#9bb7ff")},
	{"id": "floater", "name": "Floater", "key": "5", "color": Color("#8ee8ff")}
]

var terrain: Array = []
var built_ramps: Array = []
var workers: Array[Worker] = []
var level_index := 0
var spawned_count := 0
var saved_count := 0
var lost_count := 0
var spawn_timer := 0.0
var selected_tool := "builder"
var camera_x := 0.0
var manual_camera := false
var paused := false
var finished := false
var finish_text := ""
var next_worker_id := 1
var message := "Selecteaza un job, apoi click pe un omulet."

var level := {}
var stock := {}

var levels: Array[Dictionary] = []


func _ready() -> void:
	_load_levels_from_scene()
	if levels.is_empty():
		push_error("Tiny Troupe: nu exista niveluri in nodul Levels.")
		return
	_load_level(0)
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(func() -> void: queue_redraw())


func _load_levels_from_scene() -> void:
	levels.clear()
	var root := get_node_or_null("Levels")
	if root == null:
		push_warning("Tiny Troupe: lipseste nodul Levels din scena.")
		return

	for child in root.get_children():
		var level_node: Node2D = child as Node2D
		if level_node == null:
			continue

		var spawn_marker: Node2D = level_node.get_node_or_null("Spawn") as Node2D
		var terrain_root := level_node.get_node_or_null("Terrain")
		var exit_node := level_node.get_node_or_null("Exit")
		if spawn_marker == null or terrain_root == null or exit_node == null:
			push_warning("Tiny Troupe: nivelul %s trebuie sa aiba Spawn, Terrain si Exit." % level_node.name)
			continue

		var exit_shape := _first_rectangle_collision_shape(exit_node)
		if exit_shape == null:
			push_warning("Tiny Troupe: nivelul %s are nevoie de Exit/CollisionShape2D dreptunghiular." % level_node.name)
			continue

		var terrain_rects: Array[Rect2] = []
		for shape_node in terrain_root.find_children("*", "CollisionShape2D", true, false):
			var terrain_shape: CollisionShape2D = shape_node as CollisionShape2D
			if terrain_shape == null or not (terrain_shape.shape is RectangleShape2D):
				continue
			terrain_rects.append(_rect_from_collision_shape(terrain_shape, level_node))

		if terrain_rects.is_empty():
			push_warning("Tiny Troupe: nivelul %s nu are blocuri in Terrain." % level_node.name)
			continue

		levels.append({
			"name": _node_string(level_node, "level_name", level_node.name),
			"target": _node_int(level_node, "target_saved", 1),
			"total": _node_int(level_node, "total_workers", 1),
			"spawn": spawn_marker.position,
			"exit": _rect_from_collision_shape(exit_shape, level_node),
			"stock": {
				"builder": _node_int(level_node, "builders", 0),
				"digger": _node_int(level_node, "diggers", 0),
				"basher": _node_int(level_node, "bashers", 0),
				"blocker": _node_int(level_node, "blockers", 0),
				"floater": _node_int(level_node, "floaters", 0)
			},
			"terrain": terrain_rects
		})


func _first_rectangle_collision_shape(root: Node) -> CollisionShape2D:
	for node in root.find_children("*", "CollisionShape2D", true, false):
		var shape: CollisionShape2D = node as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D:
			return shape
	return null


func _rect_from_collision_shape(shape: CollisionShape2D, level_node: Node2D) -> Rect2:
	var rect_shape: RectangleShape2D = shape.shape as RectangleShape2D
	var scale := shape.global_transform.get_scale().abs()
	var size := rect_shape.size * scale
	var center := level_node.to_local(shape.global_position)
	return Rect2(center - size * 0.5, size)


func _node_int(node: Node, property_name: String, fallback: int) -> int:
	var value = node.get(property_name)
	if value == null:
		return fallback
	return int(value)


func _node_string(node: Node, property_name: String, fallback: String) -> String:
	var value = node.get(property_name)
	if value == null:
		return fallback
	var text := str(value)
	return fallback if text.is_empty() else text


func _physics_process(delta: float) -> void:
	if paused:
		queue_redraw()
		return

	if not finished:
		_spawn_tick(delta)
		_update_workers(delta)
		_check_finish()

	_update_camera(delta)
	queue_redraw()


func _draw() -> void:
	_draw_world()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_select_next_tool()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			manual_camera = true
			camera_x = clampf(camera_x - 72.0, 0.0, _max_camera_x())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			manual_camera = true
			camera_x = clampf(camera_x + 72.0, 0.0, _max_camera_x())


func _handle_key(keycode: Key) -> void:
	match keycode:
		KEY_1:
			selected_tool = "builder"
		KEY_2:
			selected_tool = "digger"
		KEY_3:
			selected_tool = "basher"
		KEY_4:
			selected_tool = "blocker"
		KEY_5:
			selected_tool = "floater"
		KEY_A, KEY_LEFT:
			manual_camera = true
			camera_x = clampf(camera_x - 120.0, 0.0, _max_camera_x())
		KEY_D, KEY_RIGHT:
			manual_camera = true
			camera_x = clampf(camera_x + 120.0, 0.0, _max_camera_x())
		KEY_C:
			manual_camera = false
		KEY_SPACE:
			paused = not paused
		KEY_R:
			_load_level(level_index)
		KEY_N:
			_load_level((level_index + 1) % levels.size())
		KEY_ESCAPE:
			get_tree().quit()


func _handle_left_click(screen_pos: Vector2) -> void:
	if screen_pos.y <= HUD_H:
		_click_hud(screen_pos)
		return

	var world_pos := Vector2(screen_pos.x + camera_x, screen_pos.y)
	var worker := _nearest_worker(world_pos)
	if worker == null:
		message = "Click mai aproape de un omulet."
		return

	_assign_tool(worker)


func _click_hud(pos: Vector2) -> void:
	for i in range(TOOLS.size()):
		var rect := _tool_rect(i)
		if rect.has_point(pos):
			selected_tool = String(TOOLS[i]["id"])
			message = "Job selectat: %s." % TOOLS[i]["name"]
			return

	var restart_rect := Rect2(_viewport_size().x - 206.0, 18.0, 86.0, 42.0)
	var next_rect := Rect2(_viewport_size().x - 108.0, 18.0, 86.0, 42.0)
	if restart_rect.has_point(pos):
		_load_level(level_index)
	elif next_rect.has_point(pos):
		_load_level((level_index + 1) % levels.size())


func _select_next_tool() -> void:
	for i in range(TOOLS.size()):
		if TOOLS[i]["id"] == selected_tool:
			selected_tool = String(TOOLS[(i + 1) % TOOLS.size()]["id"])
			message = "Job selectat: %s." % _tool_name(selected_tool)
			return


func _load_level(index: int) -> void:
	level_index = index
	level = levels[level_index]
	workers.clear()
	spawned_count = 0
	saved_count = 0
	lost_count = 0
	spawn_timer = 0.0
	next_worker_id = 1
	camera_x = 0.0
	manual_camera = false
	paused = false
	finished = false
	finish_text = ""
	selected_tool = "builder"
	message = "Nivel: %s. Salveaza trupa!" % level["name"]
	built_ramps.clear()
	stock = {}
	for key in level["stock"].keys():
		stock[key] = int(level["stock"][key])

	_clear_terrain()
	for rect in level["terrain"]:
		_fill_rect(rect, true)

	queue_redraw()


func _clear_terrain() -> void:
	terrain.clear()
	for gx in range(GRID_W):
		var column := []
		column.resize(GRID_H)
		for gy in range(GRID_H):
			column[gy] = false
		terrain.append(column)


func _spawn_tick(delta: float) -> void:
	if spawned_count >= int(level["total"]):
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		_spawn_worker()


func _spawn_worker() -> void:
	var worker := Worker.new()
	worker.id = next_worker_id
	next_worker_id += 1
	worker.pos = level["spawn"]
	worker.vel = Vector2.ZERO
	worker.dir = 1
	worker.skill = "walker"
	workers.append(worker)
	spawned_count += 1


func _update_workers(delta: float) -> void:
	for worker in workers:
		if not worker.alive or worker.saved:
			continue

		worker.blink += delta

		if _check_exit(worker):
			continue

		match worker.skill:
			"blocker":
				_update_blocker(worker)
			"builder":
				_update_builder(worker, delta)
			"digger":
				_update_digger(worker, delta)
			"basher":
				_update_basher(worker, delta)
			_:
				_update_walker(worker, delta)

		_keep_inside_world(worker)


func _update_blocker(worker: Worker) -> void:
	worker.vel = Vector2.ZERO
	if not _has_ground(worker):
		worker.skill = "walker"


func _update_walker(worker: Worker, delta: float) -> void:
	if not _apply_gravity(worker, delta):
		return

	if _is_blocked_by_blocker(worker, worker.pos.x + worker.dir * 8.0):
		worker.dir *= -1
		return

	_walk_forward(worker, WALK_SPEED, delta)


func _update_builder(worker: Worker, delta: float) -> void:
	if not _apply_gravity(worker, delta):
		return

	worker.build_timer += delta
	if worker.build_timer < BUILDER_INTERVAL:
		return

	worker.build_timer = 0.0
	if worker.build_steps >= BUILDER_STEPS:
		_finish_builder(worker)
		return

	var start := Vector2(worker.pos.x, worker.pos.y + 1.0)
	var end := start + Vector2(float(worker.dir) * BUILDER_RUN, -BUILDER_RISE)
	if _builder_step_hits_terrain(start, end, worker.dir):
		worker.dir *= -1
		end = start + Vector2(float(worker.dir) * BUILDER_RUN, -BUILDER_RISE)
		message = "Builderul a atins un obstacol si s-a intors."
		if _builder_step_hits_terrain(start, end, worker.dir):
			_finish_builder(worker)
			return

	_add_builder_ramp(start, end)

	worker.pos.x = end.x
	worker.pos.y = end.y - 1.0
	worker.build_steps += 1
	if worker.build_steps >= BUILDER_STEPS:
		_finish_builder(worker)


func _finish_builder(worker: Worker) -> void:
	worker.skill = "walker"
	worker.build_steps = 0
	worker.build_timer = 0.0
	message = "Builderul a terminat scarile."


func _add_builder_ramp(start: Vector2, end: Vector2) -> void:
	built_ramps.append({
		"start": start,
		"end": end
	})


func _builder_step_hits_terrain(start: Vector2, end: Vector2, direction: int) -> bool:
	var samples: int = int(ceili(absf(end.x - start.x) / 2.0))
	if samples < 3:
		samples = 3

	for i in range(1, samples + 1):
		var t: float = float(i) / float(samples)
		var surface := start.lerp(end, t)

		if _is_level_terrain_solid_world(surface + Vector2(0.0, -1.0)):
			return true
		if _is_level_terrain_solid_world(surface + Vector2(0.0, -4.0)):
			return true

		if i >= samples - 1:
			var face_x := surface.x + float(direction) * 4.0
			for body_y_offset in [-8.0, -14.0, -20.0]:
				if _is_level_terrain_solid_world(Vector2(face_x, surface.y + float(body_y_offset))):
					return true

	return false


func _update_digger(worker: Worker, delta: float) -> void:
	if not _has_ground(worker) and not _rect_has_solid(Rect2(worker.pos.x - 14.0, worker.pos.y + 1.0, 28.0, 28.0)):
		_apply_gravity(worker, delta)
		return

	worker.dig_timer += delta
	worker.vel = Vector2.ZERO
	_remove_rect(Rect2(worker.pos.x - 17.0, worker.pos.y - 4.0, 34.0, 28.0))
	if worker.dig_timer >= DIG_INTERVAL:
		worker.dig_timer = 0.0
		worker.pos.y += 2.0

	if not _rect_has_solid(Rect2(worker.pos.x - 13.0, worker.pos.y + 1.0, 26.0, 30.0)):
		worker.skill = "walker"


func _update_basher(worker: Worker, delta: float) -> void:
	if not _apply_gravity(worker, delta):
		return

	worker.bash_timer += delta
	var left := worker.pos.x + (8.0 if worker.dir > 0 else -33.0)
	var cut_rect := Rect2(left, worker.pos.y - 28.0, 34.0, 31.0)
	var carved := _rect_has_solid(cut_rect)
	_remove_rect(cut_rect)
	_walk_forward(worker, BASH_SPEED, delta)

	if worker.bash_timer > BASH_LIMIT or (not carved and not _solid_ahead(worker, worker.pos.y - 13.0)):
		worker.skill = "walker"
		worker.bash_timer = 0.0


func _apply_gravity(worker: Worker, delta: float) -> bool:
	if _has_ground(worker):
		if worker.vel.y > SAFE_LANDING_SPEED and not worker.floater:
			_lose_worker(worker, "Un omulet a cazut prea tare.")
			return false
		worker.vel.y = 0.0
		worker.fall_speed_peak = 0.0
		_settle_to_ground(worker)
		return true

	var max_speed := FLOAT_SPEED if worker.floater else MAX_FALL_SPEED
	worker.vel.y = minf(worker.vel.y + GRAVITY * delta, max_speed)
	worker.fall_speed_peak = maxf(worker.fall_speed_peak, worker.vel.y)
	worker.pos.y += worker.vel.y * delta

	if _has_ground(worker):
		if worker.fall_speed_peak > SAFE_LANDING_SPEED and not worker.floater:
			_lose_worker(worker, "Un omulet a cazut prea tare.")
			return false
		worker.vel.y = 0.0
		worker.fall_speed_peak = 0.0
		_snap_to_ground(worker)
		return true

	return false


func _walk_forward(worker: Worker, speed: float, delta: float) -> void:
	var next_x := worker.pos.x + float(worker.dir) * speed * delta
	if _solid_body_at(worker, next_x, worker.pos.y):
		if _try_step_up(worker, next_x):
			return
		worker.dir *= -1
		return

	worker.pos.x = next_x
	_settle_to_ground(worker)


func _try_step_up(worker: Worker, next_x: float) -> bool:
	for step in range(2, MAX_STEP_UP + 1, 2):
		var lifted_y := worker.pos.y - float(step)
		if not _solid_body_at(worker, next_x, lifted_y):
			worker.pos.x = next_x
			worker.pos.y = lifted_y
			return true
	return false


func _solid_body_at(worker: Worker, x: float, y: float) -> bool:
	var forward_x := x + float(worker.dir) * 5.0
	return (
		_is_solid_world(Vector2(forward_x, y - 4.0))
		or _is_solid_world(Vector2(forward_x, y - 12.0))
		or _is_solid_world(Vector2(forward_x, y - BODY_H))
	)


func _solid_ahead(worker: Worker, y: float) -> bool:
	var x := worker.pos.x + float(worker.dir) * 12.0
	return _is_solid_world(Vector2(x, y)) or _is_solid_world(Vector2(x, y + 9.0))


func _has_ground(worker: Worker) -> bool:
	if _ramp_ground_y_for_worker(worker, 4.0, 12.0) < INF:
		return true

	return (
		_is_solid_world(Vector2(worker.pos.x - 4.0, worker.pos.y + 2.0))
		or _is_solid_world(Vector2(worker.pos.x + 4.0, worker.pos.y + 2.0))
	)


func _snap_to_ground(worker: Worker) -> void:
	var ramp_y := _ramp_ground_y_for_worker(worker, 12.0, 24.0)
	if ramp_y < INF:
		worker.pos.y = ramp_y - 1.0
		return

	for i in range(14):
		if _has_ground(worker):
			worker.pos.y = floor((worker.pos.y + 2.0) / TILE) * TILE - 1.0
			return
		worker.pos.y += 1.0


func _settle_to_ground(worker: Worker) -> void:
	for i in range(8):
		if _has_ground(worker):
			_snap_to_ground(worker)
			return
		worker.pos.y += 1.0


func _is_blocked_by_blocker(worker: Worker, next_x: float) -> bool:
	for other in workers:
		if other == worker or not other.alive or other.saved or other.skill != "blocker":
			continue
		if absf(other.pos.x - next_x) < 17.0 and absf(other.pos.y - worker.pos.y) < 28.0:
			return true
	return false


func _check_exit(worker: Worker) -> bool:
	var exit_rect: Rect2 = level["exit"]
	if exit_rect.grow(8.0).has_point(worker.pos):
		worker.saved = true
		saved_count += 1
		message = "Salvat! %d din %d." % [saved_count, int(level["target"])]
		return true
	return false


func _keep_inside_world(worker: Worker) -> void:
	if worker.pos.x < 5.0:
		worker.pos.x = 5.0
		worker.dir = 1
	elif worker.pos.x > WORLD_W - 5.0:
		worker.pos.x = WORLD_W - 5.0
		worker.dir = -1

	if worker.pos.y > WORLD_H + 28.0:
		_lose_worker(worker, "Un omulet s-a pierdut in adanc.")


func _lose_worker(worker: Worker, text: String) -> void:
	if not worker.alive or worker.saved:
		return
	worker.alive = false
	lost_count += 1
	message = text


func _check_finish() -> void:
	var total := int(level["total"])
	var target := int(level["target"])
	if saved_count >= target:
		finished = true
		finish_text = "Nivel complet! Apasa N pentru urmatorul."
	elif spawned_count >= total and saved_count + lost_count >= total:
		finished = true
		finish_text = "Mai incearca. Apasa R pentru restart."


func _nearest_worker(world_pos: Vector2) -> Worker:
	var best: Worker = null
	var best_dist := 26.0
	for worker in workers:
		if not worker.alive or worker.saved:
			continue
		var dist := worker.pos.distance_to(world_pos)
		if dist < best_dist:
			best = worker
			best_dist = dist
	return best


func _assign_tool(worker: Worker) -> void:
	if finished:
		return
	if _worker_is_busy(worker):
		message = "%s lucreaza deja." % _tool_name(worker.skill)
		return
	if selected_tool == "floater" and worker.floater:
		message = "Omuletul are deja parasuta."
		return
	if not stock.has(selected_tool) or int(stock[selected_tool]) <= 0:
		message = "Nu mai ai %s." % _tool_name(selected_tool)
		return

	stock[selected_tool] = int(stock[selected_tool]) - 1

	if selected_tool == "floater":
		worker.floater = true
		if worker.skill == "walker":
			worker.skill = "walker"
	else:
		worker.skill = selected_tool

	worker.build_steps = 0
	worker.build_timer = 0.0
	worker.bash_timer = 0.0
	worker.dig_timer = 0.0
	message = "%s primit de omuletul #%d." % [_tool_name(selected_tool), worker.id]


func _worker_is_busy(worker: Worker) -> bool:
	return worker.skill == "builder" or worker.skill == "digger" or worker.skill == "basher" or worker.skill == "blocker"


func _fill_rect(rect: Rect2, solid: bool) -> void:
	var start_x := clampi(floori(rect.position.x / TILE), 0, GRID_W - 1)
	var end_x := clampi(ceili((rect.position.x + rect.size.x) / TILE), 0, GRID_W)
	var start_y := clampi(floori(rect.position.y / TILE), 0, GRID_H - 1)
	var end_y := clampi(ceili((rect.position.y + rect.size.y) / TILE), 0, GRID_H)
	for gx in range(start_x, end_x):
		for gy in range(start_y, end_y):
			terrain[gx][gy] = solid


func _remove_rect(rect: Rect2) -> void:
	_fill_rect(rect, false)


func _rect_has_solid(rect: Rect2) -> bool:
	var start_x := clampi(floori(rect.position.x / TILE), 0, GRID_W - 1)
	var end_x := clampi(ceili((rect.position.x + rect.size.x) / TILE), 0, GRID_W)
	var start_y := clampi(floori(rect.position.y / TILE), 0, GRID_H - 1)
	var end_y := clampi(ceili((rect.position.y + rect.size.y) / TILE), 0, GRID_H)
	for gx in range(start_x, end_x):
		for gy in range(start_y, end_y):
			if bool(terrain[gx][gy]):
				return true
	return false


func _is_solid_world(point: Vector2) -> bool:
	if _is_solid_ramp_point(point):
		return true

	return _is_level_terrain_solid_world(point)


func _is_level_terrain_solid_world(point: Vector2) -> bool:
	var gx := floori(point.x / TILE)
	var gy := floori(point.y / TILE)
	return _is_solid_cell(gx, gy)


func _is_solid_ramp_point(point: Vector2) -> bool:
	for ramp_data in built_ramps:
		var ramp: Dictionary = ramp_data
		var start: Vector2 = ramp["start"]
		var end: Vector2 = ramp["end"]
		var min_x := minf(start.x, end.x) - 1.0
		var max_x := maxf(start.x, end.x) + 1.0
		if point.x < min_x or point.x > max_x:
			continue

		var t: float = (point.x - start.x) / (end.x - start.x)
		if t < 0.0 or t > 1.0:
			continue

		var surface_y := lerpf(start.y, end.y, t)
		if point.y >= surface_y and point.y <= surface_y + BUILDER_RAMP_THICKNESS:
			return true

	return false


func _ramp_ground_y_for_worker(worker: Worker, tolerance_above: float, tolerance_below: float) -> float:
	var best_y := INF
	var best_distance := INF
	for foot_offset in [-4.0, 0.0, 4.0]:
		var foot_x: float = worker.pos.x + float(foot_offset)
		for ramp_data in built_ramps:
			var ramp: Dictionary = ramp_data
			var start: Vector2 = ramp["start"]
			var end: Vector2 = ramp["end"]
			var min_x := minf(start.x, end.x) - 2.0
			var max_x := maxf(start.x, end.x) + 2.0
			if foot_x < min_x or foot_x > max_x:
				continue

			var t: float = (foot_x - start.x) / (end.x - start.x)
			if t < 0.0 or t > 1.0:
				continue

			var surface_y := lerpf(start.y, end.y, t)
			if worker.pos.y < surface_y - tolerance_above or worker.pos.y > surface_y + tolerance_below:
				continue

			var distance := absf(worker.pos.y - surface_y)
			if distance < best_distance:
				best_distance = distance
				best_y = surface_y

	return best_y


func _is_solid_cell(gx: int, gy: int) -> bool:
	if gy < 0:
		return false
	if gy >= GRID_H:
		return true
	if gx < 0 or gx >= GRID_W:
		return true
	return bool(terrain[gx][gy])


func _update_camera(delta: float) -> void:
	if manual_camera:
		return

	var focus_x := float(level["spawn"].x)
	var count := 0
	for worker in workers:
		if worker.alive and not worker.saved:
			focus_x += worker.pos.x
			count += 1
	if count > 0:
		focus_x /= float(count + 1)

	var target_x := clampf(focus_x - _viewport_size().x * 0.42, 0.0, _max_camera_x())
	camera_x = lerpf(camera_x, target_x, minf(1.0, delta * 2.7))


func _draw_world() -> void:
	var size := _viewport_size()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#10253a"), true)
	draw_rect(Rect2(Vector2(0, HUD_H), Vector2(size.x, size.y - HUD_H)), Color("#163a4c"), true)

	draw_set_transform(Vector2(-camera_x, 0.0), 0.0, Vector2.ONE)
	_draw_background()
	_draw_terrain()
	_draw_built_ramps()
	_draw_hatch()
	_draw_exit()
	for worker in workers:
		_draw_worker(worker)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_background() -> void:
	for i in range(9):
		var x := float(i) * 230.0 - fmod(camera_x * 0.22, 230.0)
		draw_rect(Rect2(x, 620.0, 110.0, 84.0), Color(0.07, 0.16, 0.23, 0.5), true)

	draw_circle(Vector2(1310.0, 92.0), 32.0, Color("#ffd166"))
	draw_circle(Vector2(1302.0, 86.0), 32.0, Color("#10253a"))

	for x in range(0, WORLD_W, 64):
		var h := 26.0 + float((x / 64) % 5) * 7.0
		draw_rect(Rect2(float(x), 690.0 - h, 46.0, h), Color(0.09, 0.21, 0.27, 0.32), true)


func _draw_terrain() -> void:
	var first_x := clampi(floori(camera_x / TILE) - 2, 0, GRID_W - 1)
	var last_x := clampi(ceili((camera_x + _viewport_size().x) / TILE) + 2, 0, GRID_W)

	for gy in range(0, GRID_H):
		var run_start := -1
		for gx in range(first_x, last_x + 1):
			var solid := gx < GRID_W and bool(terrain[gx][gy])
			if solid and run_start == -1:
				run_start = gx
			elif (not solid or gx == last_x) and run_start != -1:
				var run_end := gx
				if solid and gx == last_x:
					run_end = gx + 1
				var y := float(gy * TILE)
				var shade := 0.82 + float((gy + run_start) % 4) * 0.035
				var color := Color(0.41 * shade, 0.62 * shade, 0.34 * shade)
				draw_rect(Rect2(float(run_start * TILE), y, float((run_end - run_start) * TILE), float(TILE)), color, true)
				if gy > 0 and not _is_solid_cell(run_start, gy - 1):
					draw_rect(Rect2(float(run_start * TILE), y, float((run_end - run_start) * TILE), 2.0), Color("#c5e478"), true)
				run_start = -1


func _draw_built_ramps() -> void:
	for ramp_data in built_ramps:
		var ramp: Dictionary = ramp_data
		var start: Vector2 = ramp["start"]
		var end: Vector2 = ramp["end"]
		var down := Vector2(0.0, BUILDER_RAMP_THICKNESS)
		var points := PackedVector2Array([start, end, end + down, start + down])
		draw_polygon(points, PackedColorArray([Color("#d0e85f"), Color("#d0e85f"), Color("#8ca83b"), Color("#8ca83b")]))
		draw_line(start, end, Color("#f4ff9d"), 2.0)


func _draw_hatch() -> void:
	var spawn: Vector2 = level["spawn"]
	draw_rect(Rect2(spawn.x - 28.0, spawn.y - 66.0, 58.0, 48.0), Color("#2a3146"), true)
	draw_rect(Rect2(spawn.x - 22.0, spawn.y - 58.0, 46.0, 34.0), Color("#5bc0be"), true)
	draw_rect(Rect2(spawn.x - 13.0, spawn.y - 48.0, 28.0, 24.0), Color("#10131c"), true)
	draw_line(Vector2(spawn.x - 30.0, spawn.y - 18.0), Vector2(spawn.x + 32.0, spawn.y - 18.0), Color("#ffd166"), 4.0)


func _draw_exit() -> void:
	var exit_rect: Rect2 = level["exit"]
	draw_rect(exit_rect, Color("#1f2937"), true)
	draw_rect(exit_rect.grow(-6.0), Color("#3ddc97"), true)
	draw_rect(Rect2(exit_rect.position.x + 12.0, exit_rect.position.y + 16.0, 22.0, 34.0), Color("#10253a"), true)
	draw_circle(exit_rect.position + Vector2(exit_rect.size.x * 0.5, 13.0), 10.0, Color("#fff3b0"))


func _draw_worker(worker: Worker) -> void:
	if worker.saved:
		return

	var base := worker.pos
	if not worker.alive:
		draw_circle(base, 6.0, Color(0.85, 0.2, 0.22, 0.45))
		draw_line(base + Vector2(-6, -6), base + Vector2(6, 6), Color("#ff6b6b"), 2.0)
		draw_line(base + Vector2(6, -6), base + Vector2(-6, 6), Color("#ff6b6b"), 2.0)
		return

	var skill_color := _skill_color(worker)
	var facing: float = float(worker.dir)
	var walking_anim: bool = worker.skill != "blocker" and worker.skill != "digger" and _has_ground(worker)
	var phase: float = worker.blink * 11.5 + float(worker.id) * 0.37
	var stride: float = sin(phase) * 5.0 if walking_anim else 0.0
	var arm_swing: float = sin(phase + PI) * 4.0 if walking_anim else 0.0
	var body_bob: float = -absf(sin(phase * 2.0)) * 1.2 if walking_anim else 0.0
	var pose_base := base + Vector2(0.0, body_bob)
	var hip_left := pose_base + Vector2(-3.0, -6.0)
	var hip_right := pose_base + Vector2(3.0, -6.0)
	var left_foot := base + Vector2(-4.0 + stride * facing, 1.5)
	var right_foot := base + Vector2(4.0 - stride * facing, 1.5)

	draw_line(hip_left, left_foot, Color("#10131c"), 2.3)
	draw_line(hip_right, right_foot, Color("#10131c"), 2.3)
	draw_rect(Rect2(pose_base.x - 4.5, pose_base.y - 18.0, 9.0, 13.0), skill_color, true)
	draw_line(pose_base + Vector2(-facing * 3.0, -15.0), pose_base + Vector2(-facing * (7.0 + arm_swing), -10.5), skill_color.darkened(0.18), 2.0)
	draw_line(pose_base + Vector2(facing * 3.0, -15.0), pose_base + Vector2(facing * (8.5 - arm_swing), -12.0), skill_color.lightened(0.25), 2.0)
	draw_circle(pose_base + Vector2(0.0, -23.0), 5.7, Color("#f5d7a1"))
	draw_circle(pose_base + Vector2(facing * 2.0, -24.0), 1.2, Color("#10131c"))

	if worker.floater:
		draw_arc(pose_base + Vector2(0.0, -33.0), 13.0, PI, TAU, 16, Color("#8ee8ff"), 2.0)
		draw_line(pose_base + Vector2(0.0, -33.0), pose_base + Vector2(0.0, -24.0), Color("#8ee8ff"), 1.5)

	if worker.skill == "blocker":
		draw_arc(base + Vector2.ZERO, 18.0, 0.0, TAU, 30, Color(0.62, 0.72, 1.0, 0.7), 2.0)
	elif worker.skill == "builder":
		draw_line(pose_base + Vector2(-7.0, -8.0), pose_base + Vector2(8.0, -13.0), Color("#ffe29a"), 2.5)
	elif worker.skill == "digger":
		draw_line(pose_base + Vector2(-8.0, -10.0), pose_base + Vector2(9.0, -19.0), Color("#d6f599"), 2.0)
	elif worker.skill == "basher":
		draw_line(pose_base + Vector2(facing * 4.0, -14.0), pose_base + Vector2(facing * 14.0, -14.0), Color("#ffccd5"), 3.0)


func _draw_hud() -> void:
	var size := _viewport_size()
	draw_rect(Rect2(0.0, 0.0, size.x, HUD_H), Color("#10131c"), true)
	draw_rect(Rect2(0.0, HUD_H - 3.0, size.x, 3.0), Color("#5bc0be"), true)

	for i in range(TOOLS.size()):
		_draw_tool_button(i)

	var level_text := "%s  |  Salvati %d/%d  |  Afara %d/%d  |  Pierduti %d" % [
		level["name"], saved_count, int(level["target"]), spawned_count, int(level["total"]), lost_count
	]
	draw_string(ThemeDB.fallback_font, Vector2(600.0, 31.0), level_text, HORIZONTAL_ALIGNMENT_LEFT, 510.0, 18, Color("#f7f7ff"))
	draw_string(ThemeDB.fallback_font, Vector2(600.0, 57.0), message, HORIZONTAL_ALIGNMENT_LEFT, 530.0, 15, Color(1, 1, 1, 0.68))

	_draw_hud_button(Rect2(size.x - 206.0, 18.0, 86.0, 42.0), "R", "Restart")
	_draw_hud_button(Rect2(size.x - 108.0, 18.0, 86.0, 42.0), "N", "Next")

	if paused:
		_draw_center_banner("Pauza", "Space continua")
	elif finished:
		_draw_center_banner(finish_text, "R restart | N nivel urmator")


func _draw_tool_button(index: int) -> void:
	var tool: Dictionary = TOOLS[index]
	var id := String(tool["id"])
	var rect := _tool_rect(index)
	var selected := selected_tool == id
	var color: Color = tool["color"]
	draw_rect(rect, Color("#182235"), true)
	draw_rect(rect, color if selected else Color(1, 1, 1, 0.22), false, 2.0)
	draw_circle(rect.position + Vector2(22.0, 22.0), 14.0, Color(color, 0.28))
	_draw_tool_icon(id, rect.position + Vector2(22.0, 22.0), color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(43.0, 20.0), "%s %s" % [tool["key"], tool["name"]], HORIZONTAL_ALIGNMENT_LEFT, 82.0, 13, Color("#f7f7ff"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(43.0, 39.0), "x%d" % int(stock.get(id, 0)), HORIZONTAL_ALIGNMENT_LEFT, 76.0, 14, color.lightened(0.12))


func _draw_tool_icon(id: String, center: Vector2, color: Color) -> void:
	match id:
		"builder":
			draw_line(center + Vector2(-9, 7), center + Vector2(8, -5), color, 3.0)
			draw_line(center + Vector2(-4, 8), center + Vector2(10, -2), color, 3.0)
		"digger":
			draw_line(center + Vector2(-8, -6), center + Vector2(8, 8), color, 3.0)
			draw_line(center + Vector2(1, -9), center + Vector2(10, 0), color, 2.0)
		"basher":
			draw_line(center + Vector2(-10, 0), center + Vector2(9, 0), color, 3.0)
			draw_line(center + Vector2(3, -6), center + Vector2(10, 0), color, 3.0)
			draw_line(center + Vector2(3, 6), center + Vector2(10, 0), color, 3.0)
		"blocker":
			draw_rect(Rect2(center.x - 8, center.y - 10, 16, 20), color, false, 3.0)
			draw_line(center + Vector2(-8, 0), center + Vector2(8, 0), color, 3.0)
		"floater":
			draw_arc(center + Vector2(0, 2), 12.0, PI, TAU, 14, color, 3.0)
			draw_line(center + Vector2(0, 2), center + Vector2(0, 11), color, 2.0)


func _draw_hud_button(rect: Rect2, key: String, label: String) -> void:
	draw_rect(rect, Color("#182235"), true)
	draw_rect(rect, Color(1, 1, 1, 0.22), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12.0, 18.0), key, HORIZONTAL_ALIGNMENT_LEFT, 20.0, 16, Color("#ffd166"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(32.0, 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, 50.0, 14, Color("#f7f7ff"))


func _draw_center_banner(title: String, subtitle: String) -> void:
	var size := _viewport_size()
	var rect := Rect2(size.x * 0.5 - 270.0, size.y * 0.5 - 58.0, 540.0, 116.0)
	draw_rect(rect, Color(0.06, 0.08, 0.12, 0.86), true)
	draw_rect(rect, Color("#5bc0be"), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(24.0, 44.0), title, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 48.0, 25, Color("#f7f7ff"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(24.0, 78.0), subtitle, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 48.0, 16, Color(1, 1, 1, 0.68))


func _tool_rect(index: int) -> Rect2:
	return Rect2(16.0 + float(index) * 112.0, 14.0, 104.0, 52.0)


func _tool_name(id: String) -> String:
	for tool_data in TOOLS:
		var tool: Dictionary = tool_data
		if tool["id"] == id:
			return String(tool["name"])
	return id


func _skill_color(worker: Worker) -> Color:
	match worker.skill:
		"builder":
			return Color("#ffd166")
		"digger":
			return Color("#8fd694")
		"basher":
			return Color("#ff8fab")
		"blocker":
			return Color("#9bb7ff")
		_:
			if worker.floater:
				return Color("#8ee8ff")
			return Color("#f7f7ff")


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


func _max_camera_x() -> float:
	return maxf(0.0, float(WORLD_W) - _viewport_size().x)
