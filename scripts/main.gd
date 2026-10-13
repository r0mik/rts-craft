extends Node2D
## Game controller: map, player input, selection, orders, combat, collisions.

const Defs = preload("res://scripts/defs.gd")
const UnitScript = preload("res://scripts/unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const MineralScript = preload("res://scripts/mineral.gd")
const AIScript = preload("res://scripts/ai.gd")
const HUDScript = preload("res://scripts/hud.gd")
const ViewScript = preload("res://scripts/view3d.gd")

const MAP_SIZE := Vector2(4000, 3000)
const CELL := 48.0
const PLAYER := 0
const ENEMY := 1
const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(0.95, 0.28, 0.22)]

var map_size := MAP_SIZE
var bank := [50, 50]
var upgrades := [{"weapons": 0, "armor": 0}, {"weapons": 0, "armor": 0}]
var ages := [1, 1]  # current age per team (see Defs.AGES)
var entities: Node2D
var view  # 3D presentation layer (scripts/view3d.gd)
var hud
var ais: Array = []
var selection: Array = []
var control_groups := {}
var last_group_key := -1
var last_group_time := 0.0
var dragging := false
var drag_start := Vector2.ZERO  # screen position where the selection box started
var placing := ""
var attack_mode := false
var missile_mode := false  # next left click picks the missile target
var missiles: Array = []   # in flight: {team, type, from, to, t, node}
var fires: Array = []      # napalm fields: {pos, r, dps, t, node}
var merges: Array = []     # unit combinations in progress: {kind, team, units, center, t}

## Fog of war, from the player's point of view (the AI ignores it). Cells of FOG_CELL px:
## fog_vis = seen right now, fog_seen = explored at least once.
const FOG_CELL := 50.0
var fog_cols := 0
var fog_rows := 0
var fog_vis := PackedByteArray()
var fog_seen := PackedByteArray()
var fog_texture: ImageTexture      # L8: 255 visible, 110 explored, 0 unexplored (3D view)
var fog_mini_texture: ImageTexture  # RGBA dark overlay for the minimap
var fog_timer := 0.0
var game_over := false
var elapsed := 0.0
var win_check := 1.0
var start_positions := [Vector2(450, 450), Vector2(3550, 2550)]
var expansions := [Vector2(450, 2550), Vector2(3550, 450), Vector2(2000, 1500)]
## Map layout (game px). Hills are plateaus with cliffs, lakes are water: both block ground units.
var hills := [
	{"pos": Vector2(1250, 950), "r": 230.0, "h": 10.0}, {"pos": Vector2(2750, 2050), "r": 230.0, "h": 10.0},
	{"pos": Vector2(1050, 1950), "r": 190.0, "h": 9.0}, {"pos": Vector2(2950, 1050), "r": 190.0, "h": 9.0},
	{"pos": Vector2(2000, 520), "r": 170.0, "h": 8.0}, {"pos": Vector2(2000, 2480), "r": 170.0, "h": 8.0},
]
var lakes := [{"pos": Vector2(2550, 760), "r": 210.0}, {"pos": Vector2(1450, 2240), "r": 210.0}]
var obstacles: Array = []  # {pos, r} circles derived from hills and lakes
var autotest := false
var report_timer := 0.0


func _ready() -> void:
	randomize()
	for h in hills:
		obstacles.append({"pos": h.pos, "r": h.r * 0.92})
	for l in lakes:
		obstacles.append({"pos": l.pos, "r": l.r * 1.15})
	autotest = "--autotest" in OS.get_cmdline_user_args()
	view = ViewScript.new()
	add_child(view)
	view.setup(self, [Color(0.27, 0.57, 1.0), Color(0.94, 0.29, 0.23)])
	entities = Node2D.new()  # logic-only nodes; everything visible lives in the 3D view
	add_child(entities)
	_setup_map()
	hud = HUDScript.new()
	add_child(hud)
	hud.setup(self)
	_add_ai(ENEMY)
	if autotest:
		_add_ai(PLAYER)  # AI vs AI to exercise every system
	_init_fog()
	view.focus = start_positions[PLAYER] + Vector2(250, 120)
	show_message("Добывай минералы, строй армию и уничтожь красную базу!")


func _add_ai(t: int) -> void:
	var ai = AIScript.new()
	ai.game = self
	ai.team = t
	ai.easy = t == ENEMY  # the red opponent plays on easy; in AI-vs-AI tests blue uses the full build
	add_child(ai)
	ais.append(ai)


# --- Map --------------------------------------------------------------------

func _setup_map() -> void:
	for t in [PLAYER, ENEMY]:
		var base: Vector2 = start_positions[t]
		_spawn_mineral_field(base)
		spawn_building(t, "cc", base, false)
		for i in 4:
			spawn_unit(t, "worker", base + Vector2(-40 + i * 27, 85))
	for pos in expansions:
		_spawn_mineral_field(pos)
	for u in get_tree().get_nodes_in_group("units"):
		u.order_gather(best_mineral(u.position))


func _spawn_mineral_field(center: Vector2) -> void:
	var to_center := MAP_SIZE / 2.0 - center
	var dir := Vector2.UP if to_center.length() < 10.0 else -to_center.normalized()
	for i in 8:
		var ang := deg_to_rad(-63.0 + i * 18.0)
		spawn_mineral(center + dir.rotated(ang) * 250.0)


func spawn_unit(t: int, kind: String, pos: Vector2):
	var u = UnitScript.new()
	u.position = pos
	u.setup(self, t, kind)
	entities.add_child(u)
	view.add_entity(u)
	return u


func spawn_building(t: int, kind: String, pos: Vector2, constructing: bool):
	var b = BuildingScript.new()
	b.position = pos
	b.setup(self, t, kind, constructing)
	entities.add_child(b)
	view.add_entity(b)
	return b


func spawn_mineral(pos: Vector2):
	var m = MineralScript.new()
	m.position = pos
	m.setup(self)
	entities.add_child(m)
	view.add_entity(m)
	return m


# --- Queries ----------------------------------------------------------------

func valid(e) -> bool:
	return is_instance_valid(e) and e.is_alive()


func team_color(t: int) -> Color:
	return TEAM_COLORS[t]


func team_units(t: int) -> Array:
	var res := []
	for u in get_tree().get_nodes_in_group("units"):
		if u.team == t and u.is_alive():
			res.append(u)
	return res


func team_buildings(t: int) -> Array:
	var res := []
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == t and b.is_alive():
			res.append(b)
	return res


func has_completed(t: int, kind: String) -> bool:
	for b in team_buildings(t):
		if b.kind == kind and b.is_complete():
			return true
	return false


func rect_point_dist(r: Rect2, p: Vector2) -> float:
	var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(c)


func edge_dist(a, b) -> float:
	return maxf(0.0, b.surface_distance(a.position) - a.radius)


func best_mineral(p: Vector2):
	var counts := {}
	for u in get_tree().get_nodes_in_group("units"):
		if u.is_worker() and valid(u.mineral_target) and u.is_mining():
			counts[u.mineral_target] = counts.get(u.mineral_target, 0) + 1
	var best = null
	var best_score := INF
	for m in get_tree().get_nodes_in_group("minerals"):
		if not m.is_alive():
			continue
		var score: float = p.distance_to(m.position) + 70.0 * counts.get(m, 0)
		if score < best_score:
			best_score = score
			best = m
	return best


func nearest_dropoff(t: int, p: Vector2):
	var best = null
	var best_d := INF
	for b in team_buildings(t):
		if b.kind == "cc" and b.is_complete():
			var d := p.distance_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	return best


func find_enemy(u, radius: float):
	var best = null
	var best_score := INF
	for e in get_tree().get_nodes_in_group("units"):
		if e.team == u.team or not e.is_alive() or not u.can_target(e):
			continue
		var d := edge_dist(u, e)
		if d <= radius:
			var score := d + (60.0 if e.is_worker() else 0.0)
			if score < best_score:
				best_score = score
				best = e
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == u.team or not b.is_alive() or not u.can_target(b):
			continue
		var d := edge_dist(u, b)
		if d <= radius and d + 200.0 < best_score:
			best_score = d + 200.0
			best = b
	return best


## Entity at a logic (ground) point. Mouse picking goes through view.pick() instead.
func entity_at(p: Vector2):
	for u in get_tree().get_nodes_in_group("units"):
		if u.is_alive() and p.distance_to(u.position) <= u.radius + 4.0:
			return u
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_alive() and b.rect().has_point(p):
			return b
	for m in get_tree().get_nodes_in_group("minerals"):
		if m.is_alive() and p.distance_to(m.position) <= m.radius + 4.0:
			return m
	return null


func supply_used(t: int) -> int:
	var n := 0
	for u in team_units(t):
		n += int(u.stats.supply)
	for b in team_buildings(t):
		for item in b.queue:
			if Defs.UNITS.has(item):
				n += int(Defs.UNITS[item].supply)
	return n


func supply_cap(t: int) -> int:
	var n := 0
	for b in team_buildings(t):
		if b.is_complete():
			n += int(b.stats.get("supply", 0))
	return mini(n, Defs.MAX_SUPPLY)


func can_place(kind: String, pos: Vector2, margin := 6.0) -> bool:
	var size: Vector2 = Defs.BUILDINGS[kind].size
	var r := Rect2(pos - size / 2.0, size)
	if r.position.x < 20 or r.position.y < 20 or r.end.x > MAP_SIZE.x - 20 or r.end.y > MAP_SIZE.y - 20:
		return false
	var grown := r.grow(margin)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_alive() and grown.intersects(b.rect()):
			return false
	for o in obstacles:
		if rect_point_dist(r, o.pos) < o.r + 10.0:
			return false
	var gap := 70.0 if kind == "cc" else 16.0
	for m in get_tree().get_nodes_in_group("minerals"):
		if m.is_alive() and rect_point_dist(r, m.position) < m.radius + gap:
			return false
	return true


## Simple obstacle avoidance: slide along buildings and around mineral patches.
func steer_around(u, dir: Vector2, goal: Vector2) -> Vector2:
	if u.is_air():
		return dir
	var ahead: Vector2 = u.position + dir * (u.radius + 14.0)
	for b in get_tree().get_nodes_in_group("buildings"):
		var r: Rect2 = b.rect().grow(u.radius + 1.0)
		if not r.has_point(ahead) or r.has_point(goal):
			continue
		var p: Vector2 = u.position
		if p.x > r.position.x and p.x < r.end.x:
			var sx := signf(goal.x - b.position.x)
			return Vector2(sx if sx != 0.0 else 1.0, 0.0)
		var sy := signf(goal.y - b.position.y)
		return Vector2(0.0, sy if sy != 0.0 else 1.0)
	var far: Vector2 = u.position + dir * (u.radius + 34.0)
	for o in obstacles:  # start curving early around hills and lakes
		var od: float = o.r + u.radius + 2.0
		if far.distance_to(o.pos) < od and goal.distance_to(o.pos) > od:
			var on: Vector2 = (u.position - o.pos).normalized()
			var ot := Vector2(-on.y, on.x)
			return ot if ot.dot(goal - u.position) >= 0.0 else -ot
	for m in get_tree().get_nodes_in_group("minerals"):
		var min_d: float = m.radius + u.radius + 2.0
		if ahead.distance_to(m.position) < min_d and goal.distance_to(m.position) > min_d:
			var n: Vector2 = (u.position - m.position).normalized()
			var t := Vector2(-n.y, n.x)
			return t if t.dot(dir) >= 0.0 else -t
	return dir


func snap(p: Vector2) -> Vector2:
	return (p / 20.0).round() * 20.0


# --- Economy & combat -------------------------------------------------------

func add_minerals(t: int, n: int) -> void:
	bank[t] += n


func refund(t: int, n: int) -> void:
	bank[t] += n


func try_train(b, uk: String) -> bool:
	var st: Dictionary = Defs.UNITS[uk]
	if not b.can_train(uk):
		return false
	if st.has("requires") and not has_completed(b.team, st.requires):
		if b.team == PLAYER:
			show_message("Сначала нужен %s" % Defs.BUILDINGS[st.requires].name)
		return false
	if st.has("limit") and count_units(b.team, uk) >= int(st.limit):
		if b.team == PLAYER:
			show_message("%s может быть только один" % st.name)
		return false
	if bank[b.team] < st.cost:
		if b.team == PLAYER:
			show_message("Недостаточно минералов")
		return false
	if supply_used(b.team) + int(st.supply) > supply_cap(b.team):
		if b.team == PLAYER:
			show_message("Нужно больше Supply Depot (V рабочим)")
		return false
	bank[b.team] -= st.cost
	b.queue.append(uk)
	b.queue_costs.append(st.cost)
	return true


## Units of a kind a team has, counting ones queued in its buildings.
func count_units(t: int, uk: String) -> int:
	var n := team_units(t).filter(func(u): return u.kind == uk).size()
	for b in team_buildings(t):
		n += b.queue.count(uk)
	return n


## Next research level for a team, counting research already in progress.
func upgrade_level(t: int, key: String) -> int:
	var n: int = upgrades[t][key]
	for b in team_buildings(t):
		if b.is_researching(key):
			n += 1
	return n


func upgrade_cost(t: int, key: String) -> int:
	var lvl := upgrade_level(t, key)
	var costs: Array = Defs.UPGRADES[key].cost
	return costs[mini(lvl, costs.size() - 1)]


func try_research(b, key: String) -> bool:
	var up: Dictionary = Defs.UPGRADES[key]
	if not b.can_research(key):
		return false
	if upgrade_level(b.team, key) >= up.max:
		if b.team == PLAYER:
			show_message("%s: максимальный уровень" % up.name)
		return false
	var cost := upgrade_cost(b.team, key)
	if bank[b.team] < cost:
		if b.team == PLAYER:
			show_message("Недостаточно минералов")
		return false
	bank[b.team] -= cost
	b.queue.append(key)
	b.queue_costs.append(cost)
	return true


# --- Ages ---------------------------------------------------------------------

func age_hp_mult(t: int) -> float:
	return pow(2.0, ages[maxi(t, 0)] - 1)


func age_shield(t: int) -> float:
	return Defs.AGE_SHIELD[ages[maxi(t, 0)]]


func age_unit_mult(t: int) -> float:
	return Defs.AGE_UNIT_BONUS if ages[maxi(t, 0)] >= 4 else 1.0


func age_in_progress(t: int) -> bool:
	for b in team_buildings(t):
		for item in b.queue:
			if String(item).begins_with("age:"):
				return true
	return false


func try_age_up(cc) -> bool:
	var t: int = cc.team
	var n: int = ages[t] + 1
	if cc.kind != "cc" or not cc.is_complete() or n >= Defs.AGES.size() or age_in_progress(t):
		return false
	var a: Dictionary = Defs.AGES[n]
	if not has_completed(t, a.requires):
		if t == PLAYER:
			show_message("Для эпохи «%s» нужен %s" % [a.name, Defs.BUILDINGS[a.requires].name])
		return false
	if bank[t] < a.cost:
		if t == PLAYER:
			show_message("Недостаточно минералов")
		return false
	bank[t] -= a.cost
	cc.queue.append("age:%d" % n)
	cc.queue_costs.append(a.cost)
	return true


func complete_age(t: int, n: int) -> void:
	if n <= ages[t]:
		return
	ages[t] = n
	for b in team_buildings(t):
		b.apply_age()
	if n >= 4:
		for u in team_units(t):
			u.max_hp *= Defs.AGE_UNIT_BONUS
			u.hp *= Defs.AGE_UNIT_BONUS
	var a: Dictionary = Defs.AGES[n]
	if t == PLAYER:
		show_message("Наступила %s: %s" % [a.name, a.bonus])
	else:
		show_message("Противник перешёл в эпоху: %s" % a.name)


func complete_upgrade(t: int, key: String) -> void:
	upgrades[t][key] += 1
	if t == PLAYER:
		show_message("Исследование завершено: %s +%d" % [Defs.UPGRADES[key].name, upgrades[t][key]])


func item_name(item: String) -> String:
	if item.begins_with("age:"):
		return Defs.AGES[int(item.get_slice(":", 1))].name
	if item.begins_with("missile:"):
		return Defs.MISSILES[item.get_slice(":", 1)].name
	if Defs.UPGRADES.has(item):
		return "%s +%d" % [Defs.UPGRADES[item].name, upgrades[PLAYER][item] + 1]
	return Defs.UNITS[item].name


func try_order_build(w, kind: String, pos: Vector2) -> bool:
	var st: Dictionary = Defs.BUILDINGS[kind]
	var t: int = w.team
	if st.has("requires") and not has_completed(t, st.requires):
		if t == PLAYER:
			show_message("Сначала нужен %s" % Defs.BUILDINGS[st.requires].name)
		return false
	if bank[t] < st.cost:
		if t == PLAYER:
			show_message("Недостаточно минералов")
		return false
	if not can_place(kind, pos):
		if t == PLAYER:
			show_message("Здесь строить нельзя")
		return false
	bank[t] -= st.cost
	w.order_build(kind, pos)
	return true


func worker_build(w) -> void:
	if can_place(w.build_kind, w.build_pos):
		spawn_building(w.team, w.build_kind, w.build_pos, true)
	else:
		refund(w.team, Defs.BUILDINGS[w.build_kind].cost)
		if w.team == PLAYER:
			show_message("Место занято — строительство отменено")


func on_building_complete(b) -> void:
	if b.team == PLAYER:
		show_message("%s построен" % b.stats.name)


## Weapons upgrades add 20% damage per level, armour removes a flat 1.5 per level.
func scaled_damage(attacker, target, dmg: float) -> float:
	var w: int = upgrades[attacker.team].weapons
	var a: int = upgrades[target.team].armor
	if attacker.is_in_group("units"):
		dmg *= age_unit_mult(attacker.team)
	return maxf(dmg * (1.0 + 0.2 * w) - a * 1.5, dmg * 0.4)


func deal_damage(attacker, target, dmg: float, splash: float) -> void:
	if splash > 0.0:
		var center: Vector2 = target.position
		view.fx_shot(attacker, target, true)
		var all: Array = get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("buildings")
		for e in all:
			if e.team != attacker.team and e.is_alive() and attacker.can_target(e) and e.surface_distance(center) <= splash:
				e.take_damage(scaled_damage(attacker, e, dmg if e == target else dmg * 0.5), attacker)
	else:
		view.fx_shot(attacker, target, false)
		target.take_damage(scaled_damage(attacker, target, dmg), attacker)


## Removes an entity without a death explosion (units merging into a super unit).
func remove_silently(e) -> void:
	view.remove_entity(e)
	selection.erase(e)
	for k in control_groups:
		control_groups[k].erase(e)
	e.hp = 0.0
	e.queue_free()


func kill(e) -> void:
	view.fx_death(e)
	view.remove_entity(e)
	selection.erase(e)
	for k in control_groups:
		control_groups[k].erase(e)
	e.queue_free()


# --- Player commands --------------------------------------------------------

func selected_units() -> Array:
	return selection.filter(func(e): return valid(e) and e.is_in_group("units") and e.team == PLAYER)


func selected_buildings() -> Array:
	return selection.filter(func(e): return valid(e) and e.is_in_group("buildings") and e.team == PLAYER)


func set_selection(arr: Array) -> void:
	for e in selection:
		if is_instance_valid(e):
			e.selected = false
	selection = arr.filter(func(e): return valid(e))
	for e in selection:
		e.selected = true


## Commands available for the current selection (used by hotkeys and HUD buttons).
func get_commands() -> Array:
	var cmds := []
	if game_over:
		return cmds
	var units := selected_units()
	var blds := selected_buildings()
	if not units.is_empty():
		cmds.append({"key": KEY_G, "label": "Атака (G)", "fn": cmd_attack, "icon": "@attack"})
		cmds.append({"key": KEY_X, "label": "Стоп (X)", "fn": cmd_stop, "icon": "@stop"})
		cmds.append({"key": KEY_H, "label": "Держать позицию (H)", "fn": cmd_hold, "icon": "@hold"})
		for ck in Defs.COMBOS:
			if not combo_parts(units, ck).is_empty():
				var cd: Dictionary = Defs.COMBOS[ck]
				cmds.append({"key": cd.key, "label": "Объединить: %s (%s) — %s" % [cd.name, OS.get_keycode_string(cd.key), cd.desc],
					"fn": func(): start_combine(PLAYER, ck, selected_units()), "icon": ck})
		if units.any(func(u): return u.kind == "scout"):
			var ready := units.any(func(u): return u.kind == "scout" and u.ability_cd <= 0.0)
			cmds.append({"key": KEY_F, "label": "Сбросить маяк (F): видит всё вокруг 90 с" if ready else "Маяк перезаряжается",
				"fn": cmd_beacon, "icon": "beacon", "disabled": not ready})
		if units.any(func(u): return u.is_worker()):
			for bk in Defs.WORKER_BUILDS:
				var st: Dictionary = Defs.BUILDINGS[bk]
				cmds.append({"key": st.hotkey, "label": "%s (%s) %d" % [st.name, OS.get_keycode_string(st.hotkey), st.cost],
					"fn": func(): start_placing(bk), "icon": bk, "cost": st.cost})
	elif not blds.is_empty():
		var kinds := []
		for b in blds:
			for uk in b.stats.trains:
				if not uk in kinds:
					kinds.append(uk)
		for uk in kinds:
			var st: Dictionary = Defs.UNITS[uk]
			cmds.append({"key": st.hotkey, "label": "%s (%s) %d" % [st.name, OS.get_keycode_string(st.hotkey), st.cost],
				"fn": func(): train_selected(uk), "icon": uk, "cost": st.cost})
		var cc = null
		for b in blds:
			if b.kind == "cc" and b.is_complete():
				cc = b
				break
		var next_age: int = ages[PLAYER] + 1
		if cc != null and next_age < Defs.AGES.size() and not age_in_progress(PLAYER):
			var a: Dictionary = Defs.AGES[next_age]
			cmds.append({"key": Defs.AGE_KEY, "label": "%s (E) %d: %s. Нужен %s" % [a.name, a.cost, a.bonus,
				Defs.BUILDINGS[a.requires].name], "fn": func(): try_age_up(cc), "icon": "@age:%d" % next_age, "cost": a.cost,
				"disabled": not has_completed(PLAYER, a.requires)})
		var research := []
		for b in blds:
			for key in b.stats.get("research", []):
				if not key in research:
					research.append(key)
		for key in research:
			var up: Dictionary = Defs.UPGRADES[key]
			var lvl := upgrade_level(PLAYER, key)
			var label := "%s +%d (%s) %d" % [up.name, lvl + 1, OS.get_keycode_string(up.hotkey), upgrade_cost(PLAYER, key)]
			if lvl >= up.max:
				label = "%s: макс." % up.name
			cmds.append({"key": up.hotkey, "label": label, "fn": func(): research_selected(key), "icon": "@" + key,
				"cost": upgrade_cost(PLAYER, key) if lvl < up.max else 0, "disabled": lvl >= up.max})
		if blds.any(func(b): return not b.queue.is_empty()):
			cmds.append({"key": KEY_X, "label": "Отмена (X)", "fn": cmd_cancel, "icon": "@cancel"})
		var silos := blds.filter(func(b): return b.kind == "silo" and b.is_complete())
		var ready_silo = missile_silo()
		if ready_silo != null:
			var rm: Dictionary = Defs.MISSILES[ready_silo.missile_type]
			cmds.append({"key": Defs.MISSILE_LAUNCH_KEY, "label": "Пуск: %s (L), дальность %d" % [rm.name, rm.range],
				"fn": cmd_launch, "icon": "@launch"})
		if silos.any(func(b): return not b.missile_ready and b.queue.is_empty()):
			for mk in Defs.MISSILES:
				var md: Dictionary = Defs.MISSILES[mk]
				cmds.append({"key": md.key, "label": "%s (%s) %d: %s" % [md.name, OS.get_keycode_string(md.key), md.cost, _missile_tip(mk)],
					"fn": func(): arm_selected(mk), "icon": "@missile:" + mk, "cost": md.cost})
		var damaged := _damaged_bunkers()
		if not damaged.is_empty():
			var cost := 0
			for b in damaged:
				cost += repair_cost(b)
			cmds.append({"key": KEY_R, "label": "Чинить (R) %d" % cost, "fn": cmd_repair, "icon": "@repair", "cost": cost})
	return cmds


func cmd_attack() -> void:
	attack_mode = true
	missile_mode = false
	placing = ""


# --- Unit combinations ------------------------------------------------------------

## Picks the units for a combination from candidates (the ones closest to their group centre);
## returns [] if there are not enough of some part.
func combo_parts(candidates: Array, ck: String) -> Array:
	var picked := []
	var busy := []
	for m in merges:
		busy.append_array(m.units)
	for part in Defs.COMBOS[ck].parts:
		var need: int = Defs.COMBOS[ck].parts[part]
		var pool: Array = candidates.filter(func(u): return valid(u) and u.kind == part and not u in busy)
		if pool.size() < need:
			return []
		var c := Vector2.ZERO
		for u in pool:
			c += u.position
		c /= pool.size()
		pool.sort_custom(func(a, b): return a.position.distance_squared_to(c) < b.position.distance_squared_to(c))
		picked.append_array(pool.slice(0, need))
	return picked


## Orders the parts to gather; _update_merges fuses them into the super unit once they meet.
func start_combine(t: int, ck: String, candidates: Array) -> bool:
	var parts := combo_parts(candidates, ck)
	if parts.is_empty():
		return false
	var c := Vector2.ZERO
	for u in parts:
		c += u.position
	c /= parts.size()
	for u in parts:
		u.order_move(c)
	merges.append({"kind": ck, "team": t, "units": parts, "center": c, "t": 0.0})
	if t == PLAYER:
		show_message("Собираются в %s…" % Defs.COMBOS[ck].name.to_lower())
		add_marker(c, Color(0.6, 0.8, 1.0))
	return true


func _update_merges(delta: float) -> void:
	for m in merges.duplicate():
		m["t"] += delta
		if m.units.any(func(u): return not valid(u)) or m.t > 20.0:
			merges.erase(m)
			if m.team == PLAYER:
				show_message("Объединение сорвано")
			continue
		var far := 0.0
		for u in m.units:
			far = maxf(far, u.position.distance_to(m.center))
		if far > 110.0 and not (m.t > 6.0 and far < 230.0):
			continue
		merges.erase(m)
		var was_selected := false
		for u in m.units:
			was_selected = was_selected or u.selected
			remove_silently(u)
		var su = spawn_unit(m.team, m.kind, m.center)
		view.fx_merge(m.center)
		if m.team == PLAYER:
			show_message("%s готов!" % Defs.COMBOS[m.kind].name)
			if was_selected:
				set_selection(selection + [su])


## Seeker: the first ready scout in the selection drops a sensor beacon where it stands.
func cmd_beacon() -> void:
	for u in selected_units():
		if u.kind == "scout" and u.ability_cd <= 0.0:
			u.ability_cd = u.stats.beacon_cooldown
			spawn_unit(u.team, "beacon", u.position)
			show_message("Маяк установлен")
			return


func cmd_launch() -> void:
	missile_mode = true
	attack_mode = false
	placing = ""
	show_message("Выберите цель для ракеты (ЛКМ), ПКМ — отмена")


# --- Missiles ---------------------------------------------------------------

func _missile_tip(mk: String) -> String:
	var md: Dictionary = Defs.MISSILES[mk]
	match mk:
		"cluster":
			return "%d кассет по %d урона на площади %d" % [md.bomblets, md.damage, md.radius]
		"napalm":
			return "поджигает землю радиусом %d на %d с (%d урона/с)" % [md.radius, md.burn_time, md.burn_dps]
	return "%d урона, радиус %d, дальность %d" % [md.damage, md.radius, md.range]


## The first selected silo with a loaded missile (null if none).
func missile_silo():
	for b in selected_buildings():
		if b.kind == "silo" and b.is_complete() and b.missile_ready:
			return b
	return null


func arm_selected(mk: String) -> void:
	for b in selected_buildings():
		if try_arm_missile(b, mk):
			return


func try_arm_missile(b, mk: String) -> bool:
	if b.kind != "silo" or not b.is_complete() or b.missile_ready or not b.queue.is_empty():
		return false
	var md: Dictionary = Defs.MISSILES[mk]
	if bank[b.team] < md.cost:
		if b.team == PLAYER:
			show_message("Недостаточно минералов")
		return false
	bank[b.team] -= md.cost
	b.queue.append("missile:" + mk)
	b.queue_costs.append(md.cost)
	return true


func launch_missile(silo, target: Vector2) -> bool:
	if not valid(silo) or not silo.missile_ready:
		return false
	var mk: String = silo.missile_type
	var md: Dictionary = Defs.MISSILES[mk]
	target = target.clamp(Vector2.ZERO, map_size)
	if silo.position.distance_to(target) > md.range:
		if silo.team == PLAYER:
			show_message("Слишком далеко: %s бьёт не дальше %d" % [md.name, md.range])
		return false
	silo.missile_type = ""
	var m := {"team": silo.team, "type": mk, "from": silo.position, "to": target, "t": 0.0}
	m["node"] = view.add_missile(silo.position, target, mk)
	missiles.append(m)
	if silo.team != PLAYER:
		show_message("Внимание! Пуск вражеской ракеты: %s!" % md.name)
	return true


## Damages everything (both sides) within r of p: full damage at the centre, half at the edge.
func _blast(p: Vector2, r: float, dmg: float) -> void:
	var all: Array = get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("buildings")
	for e in all:
		if not e.is_alive():
			continue
		var d: float = maxf(0.0, e.surface_distance(p))
		if d <= r:
			e.take_damage(dmg * (1.0 - 0.5 * d / r), null)


func _update_missiles(delta: float) -> void:
	for m in missiles.duplicate():
		var md: Dictionary = Defs.MISSILES[m.type]
		m["t"] += delta / md.flight
		if m.t < 1.0:
			view.move_missile(m.node, m.from, m.to, m.t)
			continue
		missiles.erase(m)
		match m.type:
			"cluster":
				view.missile_impact(m.node, m.to, md.bomblet_radius)
				for i in int(md.bomblets):
					var p: Vector2 = m.to + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * (md.radius - md.bomblet_radius)
					view.fx_explosion(p, 1.6)
					_blast(p, md.bomblet_radius, md.damage)
			"napalm":
				view.missile_impact(m.node, m.to, md.radius * 0.5)
				_blast(m.to, md.radius * 0.5, md.damage)
				fires.append({"pos": m.to, "r": md.radius, "dps": md.burn_dps, "t": md.burn_time,
					"node": view.add_fire_zone(m.to, md.radius)})
			_:
				view.missile_impact(m.node, m.to, md.radius)
				_blast(m.to, md.radius, md.damage)
	# napalm fields keep burning everything inside them
	for f in fires.duplicate():
		f["t"] -= delta
		if f.t <= 0.0:
			fires.erase(f)
			f.node.queue_free()
			continue
		var all: Array = get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("buildings")
		for e in all:
			if e.is_alive() and not (e.is_in_group("units") and e.is_air()) and e.surface_distance(f.pos) <= f.r:
				e.take_damage(f.dps * delta, null)


# --- Fog of war ---------------------------------------------------------------

func _init_fog() -> void:
	fog_cols = ceili(map_size.x / FOG_CELL)
	fog_rows = ceili(map_size.y / FOG_CELL)
	fog_vis.resize(fog_cols * fog_rows)
	fog_seen.resize(fog_cols * fog_rows)
	fog_vis.fill(0)
	fog_seen.fill(0)
	fog_texture = ImageTexture.create_from_image(Image.create(fog_cols, fog_rows, false, Image.FORMAT_L8))
	fog_mini_texture = ImageTexture.create_from_image(Image.create(fog_cols, fog_rows, false, Image.FORMAT_RGBA8))
	view.set_fog(fog_texture, Vector2(fog_cols, fog_rows) * FOG_CELL)
	_update_fog()


func sight_of(e) -> float:
	if e.is_in_group("units"):
		return e.stats.sight
	return maxf(e.size.x, e.size.y) * 0.5 + 220.0


func _update_fog() -> void:
	fog_vis.fill(0)
	for e in team_units(PLAYER) + team_buildings(PLAYER):
		var r: float = sight_of(e)
		var c: Vector2 = e.position
		var x0 := maxi(0, int((c.x - r) / FOG_CELL))
		var x1 := mini(fog_cols - 1, int((c.x + r) / FOG_CELL))
		var y0 := maxi(0, int((c.y - r) / FOG_CELL))
		var y1 := mini(fog_rows - 1, int((c.y + r) / FOG_CELL))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if Vector2((x + 0.5) * FOG_CELL, (y + 0.5) * FOG_CELL).distance_squared_to(c) <= r * r:
					fog_vis[y * fog_cols + x] = 1
					fog_seen[y * fog_cols + x] = 1
	var lum := PackedByteArray()
	var mini_px := PackedByteArray()
	lum.resize(fog_vis.size())
	mini_px.resize(fog_vis.size() * 4)
	mini_px.fill(0)
	for i in fog_vis.size():
		lum[i] = 255 if fog_vis[i] else (110 if fog_seen[i] else 0)
		mini_px[i * 4 + 3] = 0 if fog_vis[i] else (110 if fog_seen[i] else 200)
	fog_texture.update(Image.create_from_data(fog_cols, fog_rows, false, Image.FORMAT_L8, lum))
	fog_mini_texture.update(Image.create_from_data(fog_cols, fog_rows, false, Image.FORMAT_RGBA8, mini_px))
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team != PLAYER and not b.seen_by_player:
			var r: Rect2 = b.rect()
			for p in [r.get_center(), r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
				if is_point_visible(p):
					b.seen_by_player = true
					break


func is_point_visible(p: Vector2) -> bool:
	var x := int(p.x / FOG_CELL)
	var y := int(p.y / FOG_CELL)
	if x < 0 or y < 0 or x >= fog_cols or y >= fog_rows:
		return false
	return fog_vis[y * fog_cols + x] == 1


## Whether the player may see an entity: own things always, enemy units only inside vision,
## enemy buildings once spotted, minerals always.
func visible_to_player(e) -> bool:
	if e.team == PLAYER or e.team < 0:
		return true
	if e.is_in_group("buildings"):
		return e.seen_by_player
	return is_point_visible(e.position)


func cmd_stop() -> void:
	for u in selected_units():
		u.order_stop()


func cmd_hold() -> void:
	for u in selected_units():
		u.order_hold()


func cmd_cancel() -> void:
	for b in selected_buildings():
		if not b.queue.is_empty():
			b.cancel_last()
			return


func research_selected(key: String) -> void:
	for b in selected_buildings():
		if b.can_research(key):
			try_research(b, key)
			return


const REPAIR_COST_PER_HP := 0.1  # minerals per hit point; a fully broken bunker costs 55


func _damaged_bunkers() -> Array:
	return selected_buildings().filter(func(b): return b.kind == "bunker" and b.is_complete() and b.hp < b.max_hp)


func repair_cost(b) -> int:
	return ceili((b.max_hp - b.hp) * REPAIR_COST_PER_HP)


## Instantly repairs the selected bunkers for minerals; if money runs short, repairs as much as it can pay for.
func cmd_repair() -> void:
	for b in _damaged_bunkers():
		if bank[PLAYER] <= 0:
			show_message("Недостаточно минералов")
			return
		var cost := repair_cost(b)
		if bank[PLAYER] >= cost:
			bank[PLAYER] -= cost
			b.hp = b.max_hp
		else:
			b.hp = minf(b.max_hp, b.hp + bank[PLAYER] / REPAIR_COST_PER_HP)
			bank[PLAYER] = 0


func train_selected(uk: String) -> void:
	var best = null
	for b in selected_buildings():
		if b.can_train(uk) and (best == null or b.queue.size() < best.queue.size()):
			best = b
	if best != null:
		try_train(best, uk)


func start_placing(kind: String) -> void:
	var st: Dictionary = Defs.BUILDINGS[kind]
	if st.has("requires") and not has_completed(PLAYER, st.requires):
		show_message("Сначала нужен %s" % Defs.BUILDINGS[st.requires].name)
		return
	if bank[PLAYER] < st.cost:
		show_message("Недостаточно минералов")
		return
	attack_mode = false
	placing = kind


func _try_place(wp: Vector2, keep: bool) -> void:
	var p := snap(wp)
	var workers := selected_units().filter(func(u): return u.is_worker())
	if workers.is_empty():
		placing = ""
		return
	workers.sort_custom(func(a, b): return a.position.distance_to(p) < b.position.distance_to(p))
	var w = workers[0]
	for cand in workers:
		if cand.build_kind == "":
			w = cand
			break
	if try_order_build(w, placing, p):
		add_marker(p, Color(0.3, 1.0, 0.3))
		if not keep:
			placing = ""


func issue_move(units: Array, p: Vector2, attack := false) -> void:
	var n := units.size()
	var cols := int(ceil(sqrt(n)))
	var rows := int(ceil(float(n) / cols))
	for i in n:
		var off := Vector2((i % cols - (cols - 1) / 2.0) * 28.0, (i / cols - (rows - 1) / 2.0) * 28.0)
		if attack:
			units[i].order_attack_move(p + off)
		else:
			units[i].order_move(p + off)


func _right_click(p: Vector2, picked = null) -> void:
	var units := selected_units()
	if units.is_empty():
		var blds := selected_buildings()
		for b in blds:
			b.rally = p
			b.has_rally = true
		if not blds.is_empty():
			add_marker(p, Color(1.0, 0.9, 0.3))
		return
	var t = picked if picked != null else entity_at(p)
	if t != null and not visible_to_player(t):
		t = null  # no orders against things hidden in the fog
	if t != null and t.is_in_group("minerals"):
		var others := []
		for u in units:
			if u.is_worker():
				u.order_gather(t)
			else:
				others.append(u)
		if not others.is_empty():
			issue_move(others, p)
		add_marker(p, Color(0.4, 0.9, 1.0))
	elif t != null and t.team != PLAYER:
		for u in units:
			u.order_attack(t)
		add_marker(p, Color(1.0, 0.25, 0.2))
	elif t != null and t.is_in_group("buildings") and t.kind == "cc":
		var others := []
		for u in units:
			if u.is_worker() and u.carrying > 0:
				u.order_return()
			else:
				others.append(u)
		if not others.is_empty():
			issue_move(others, p)
		add_marker(p, Color(0.3, 1.0, 0.3))
	else:
		issue_move(units, p)
		add_marker(p, Color(0.3, 1.0, 0.3))


func minimap_command(wp: Vector2) -> void:
	var units := selected_units()
	if not units.is_empty():
		issue_move(units, wp, attack_mode)
		attack_mode = false


func add_marker(p: Vector2, c: Color) -> void:
	view.fx_marker(p, c)


func show_message(text: String) -> void:
	if hud != null:
		hud.show_message(text)
	if autotest:
		print("[msg] ", text)


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var sp: Vector2 = event.position
		var wp: Vector2 = view.screen_to_ground(sp)
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if placing != "":
						_try_place(wp, event.shift_pressed)
					elif missile_mode:
						missile_mode = false
						for b in selected_buildings():
							if b.kind == "silo" and launch_missile(b, wp):
								add_marker(wp, Color(1.0, 0.25, 0.2))
								break
					elif attack_mode:
						var units := selected_units()
						var t = view.pick(sp)
						if t != null and t.team >= 0 and t.team != PLAYER:
							for u in units:
								u.order_attack(t)
						else:
							issue_move(units, wp, true)
						add_marker(wp, Color(1.0, 0.25, 0.2))
						attack_mode = false
					else:
						dragging = true
						drag_start = sp
				elif dragging:
					dragging = false
					_finish_selection(drag_start, sp, event.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if placing != "" or attack_mode or missile_mode:
						placing = ""
						attack_mode = false
						missile_mode = false
					elif not game_over:
						_right_click(wp, view.pick(sp))
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					view.zoom(1.0 / 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					view.zoom(1.12)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		var before: Vector2 = view.screen_to_ground(event.position - event.relative)
		view.focus += before - view.screen_to_ground(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(event: InputEventKey) -> void:
	var key := event.keycode
	if game_over and key == KEY_R:
		get_tree().reload_current_scene()
		return
	if key == KEY_ESCAPE:
		placing = ""
		attack_mode = false
		missile_mode = false
		return
	if key >= KEY_1 and key <= KEY_9:
		var n := int(key - KEY_0)
		if event.ctrl_pressed:
			control_groups[n] = selection.duplicate()
			show_message("Группа %d назначена" % n)
		elif control_groups.has(n):
			set_selection(control_groups[n])
			var now := Time.get_ticks_msec() / 1000.0
			if last_group_key == n and now - last_group_time < 0.4 and not selection.is_empty():
				view.focus = selection[0].position
			last_group_key = n
			last_group_time = now
		return
	if key == KEY_SPACE:
		view.focus = start_positions[PLAYER]
		return
	for c in get_commands():
		if c.key == key:
			c["fn"].call()
			return


func _finish_selection(a: Vector2, b: Vector2, add: bool) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)  # screen space
	var picked := []
	if r.size.length() < 8.0:
		var e = view.pick(b)
		if e != null and e.team >= 0:
			picked = [e]
	else:
		picked = view.units_in_rect(r, PLAYER)
		if picked.is_empty():
			picked = view.buildings_in_rect(r, PLAYER)
	if add:
		var s := selection.filter(func(e): return valid(e) and e.team == PLAYER)
		for p in picked:
			if p.team != PLAYER:
				continue
			if s.has(p):
				s.erase(p)
			else:
				s.append(p)
		set_selection(s)
	else:
		set_selection(picked)


# --- Frame update -----------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	fog_timer -= delta
	if fog_timer <= 0.0:
		fog_timer = 0.2
		_update_fog()
	_update_missiles(delta)
	_update_merges(delta)
	_update_camera(delta)
	_resolve_collisions()
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		dragging = false
		_finish_selection(drag_start, get_viewport().get_mouse_position(), Input.is_key_pressed(KEY_SHIFT))
	win_check -= delta
	if win_check <= 0.0 and not game_over:
		win_check = 1.0
		if team_buildings(PLAYER).is_empty():
			game_over = true
			hud.show_big("ПОРАЖЕНИЕ", Color(1.0, 0.3, 0.25))
			if autotest:
				print("[result] RED wins at %.0fs" % elapsed)
		elif team_buildings(ENEMY).is_empty():
			game_over = true
			hud.show_big("ПОБЕДА!", Color(0.4, 1.0, 0.4))
			if autotest:
				print("[result] BLUE wins at %.0fs" % elapsed)
	if autotest:
		_autotest_screenshot()
		report_timer -= delta
		if report_timer <= 0.0:
			report_timer = 30.0
			for t in [PLAYER, ENEMY]:
				var counts := {}
				for u in team_units(t):
					counts[u.kind] = counts.get(u.kind, 0) + 1
				var bcounts := {}
				for b in team_buildings(t):
					bcounts[b.kind] = bcounts.get(b.kind, 0) + 1
				print("[%4.0fs] team %d: minerals=%d supply=%d/%d units=%s buildings=%s" % [
					elapsed, t, bank[t], supply_used(t), supply_cap(t), counts, bcounts])


## Debug helper: `-- --autotest --screenshot=<path> --shot-time=<sec>` saves one frame.
func _autotest_screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--screenshot="):
			continue
		var at := 240.0
		for a2 in OS.get_cmdline_user_args():
			if a2.begins_with("--shot-time="):
				at = float(a2.trim_prefix("--shot-time="))
		if elapsed >= at and not has_meta("shot_done"):
			set_meta("shot_done", true)
			var army := team_units(PLAYER).filter(func(u): return not u.is_worker())
			set_selection(army)
			view.focus = start_positions[PLAYER] + Vector2(350, 200)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))
			print("[shot] saved")


func _update_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	# WASD by physical position, so it works with any keyboard layout; arrows kept as a fallback.
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if DisplayServer.window_is_focused() and not autotest:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		var edge := 12.0
		if mp.x >= 0 and mp.y >= 0 and mp.x <= vs.x and mp.y <= vs.y:
			if mp.x < edge: dir.x -= 1
			if mp.x > vs.x - edge: dir.x += 1
			if mp.y < edge: dir.y -= 1
			if mp.y > vs.y - edge: dir.y += 1
	view.focus += dir.normalized() * 14.0 * view.dist * delta
	view.focus = view.focus.clamp(Vector2.ZERO, MAP_SIZE)


func _resolve_collisions() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var grid := {}
	for u in units:
		var k := Vector2i(floori(u.position.x / CELL), floori(u.position.y / CELL))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(u)
	for u in units:
		if not u.is_alive():
			continue
		# Mining workers pass through other units, like in StarCraft.
		var ghost: bool = (u.is_worker() and u.is_mining()) or u.stats.get("static", false)
		if not ghost:
			var c := Vector2i(floori(u.position.x / CELL), floori(u.position.y / CELL))
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var cell = grid.get(c + Vector2i(dx, dy))
					if cell == null:
						continue
					for o in cell:
						if o == u or o.get_instance_id() < u.get_instance_id() or not o.is_alive():
							continue
						if (o.is_worker() and o.is_mining()) or o.is_air() != u.is_air() or o.stats.get("static", false):
							continue
						var diff: Vector2 = u.position - o.position
						var min_d: float = u.radius + o.radius
						var d := diff.length()
						if d < min_d:
							var n := diff / d if d > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
							var push := (min_d - d) * 0.5
							u.position += n * push
							o.position -= n * push
		if u.is_air():
			u.position = u.position.clamp(Vector2(10, 10), MAP_SIZE - Vector2(10, 10))
			continue
		for b in get_tree().get_nodes_in_group("buildings"):
			var r: Rect2 = b.rect().grow(u.radius)
			if r.has_point(u.position):
				var p: Vector2 = u.position
				var dl := p.x - r.position.x
				var dr := r.end.x - p.x
				var dt := p.y - r.position.y
				var db := r.end.y - p.y
				var m := minf(minf(dl, dr), minf(dt, db))
				if m == dl: p.x = r.position.x
				elif m == dr: p.x = r.end.x
				elif m == dt: p.y = r.position.y
				else: p.y = r.end.y
				u.position = p
		for mn in get_tree().get_nodes_in_group("minerals"):
			var diff: Vector2 = u.position - mn.position
			var min_d: float = u.radius + mn.radius
			if diff.length_squared() < min_d * min_d:
				var d := diff.length()
				var n := diff / d if d > 0.01 else Vector2.DOWN
				u.position = mn.position + n * min_d
		for o in obstacles:  # hills and lakes
			var od: Vector2 = u.position - o.pos
			var orr: float = o.r + u.radius
			if od.length_squared() < orr * orr:
				var dl := od.length()
				u.position = o.pos + (od / dl if dl > 0.01 else Vector2.DOWN) * orr
		u.position = u.position.clamp(Vector2(10, 10), MAP_SIZE - Vector2(10, 10))
