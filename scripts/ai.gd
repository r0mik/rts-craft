extends Node
## Simple computer opponent: economy, supply, production, attack waves.

const Defs = preload("res://scripts/defs.gd")

var game
var team := 1
var think_timer := 1.0
var wave_size := 6
var elapsed := 0.0
var reserve := 0  # minerals held back for the next planned building
var easy := false  # easy mode: slow reactions, small economy, marines only, never attacks with troops, no Titan


func _process(delta: float) -> void:
	elapsed += delta
	think_timer -= delta
	if think_timer > 0.0 or game.game_over:
		return
	think_timer = 2.0 if easy else 0.6
	_think()


func _think() -> void:
	var units: Array = game.team_units(team)
	var buildings: Array = game.team_buildings(team)
	var cc = null
	for b in buildings:
		if b.kind == "cc" and b.is_complete():
			cc = b
			break
	var workers := []
	var army := []
	for u in units:
		if u.is_worker():
			workers.append(u)
		else:
			army.append(u)
	if cc != null:
		_economy(cc, workers, buildings)
	_military(cc, army, buildings)


func _count(kind: String, buildings: Array, workers: Array) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind:
			n += 1
	for w in workers:
		if w.build_kind == kind:
			n += 1
	return n


func _economy(cc, workers: Array, buildings: Array) -> void:
	for w in workers:
		if w.is_idle():
			w.order_gather(game.best_mineral(w.position))
	var used: int = game.supply_used(team)
	var cap: int = game.supply_cap(team)
	var pending_depots := 0
	for b in buildings:
		if b.kind == "depot" and b.constructing:
			pending_depots += 1
	for w in workers:
		if w.build_kind == "depot":
			pending_depots += 1
	var margin := 8 if _wants_titan(cc) else 4  # a Titan needs 6 free supply
	if cap < Defs.MAX_SUPPLY and used + margin >= cap + pending_depots * 8:
		if game.bank[team] >= 100:
			_build("depot", cc, workers)
		return  # save up for the depot
	var max_workers := 8 if easy else 18
	if workers.size() + cc.queue.size() < max_workers and cc.queue.is_empty():
		game.try_train(cc, "worker")
	# Tech/defence build order: first entry whose conditions hold gets built.
	var rax := _count("barracks", buildings, workers)
	var plan := [
		["barracks", rax < 3 and elapsed > 25.0 + rax * 70.0],
		["bunker", _count("bunker", buildings, workers) < 1 and elapsed > 110.0 and game.has_completed(team, "barracks")],
		["factory", _count("factory", buildings, workers) == 0 and elapsed > 160.0 and game.has_completed(team, "barracks")],
		["ebay", _count("ebay", buildings, workers) == 0 and elapsed > 200.0],
		["turret", _count("turret", buildings, workers) < 2 and game.has_completed(team, "ebay")],
		["starport", _count("starport", buildings, workers) == 0 and elapsed > 280.0 and game.has_completed(team, "factory")],
	]
	plan.append(["silo", _count("silo", buildings, workers) == 0 and elapsed > 330.0 and game.has_completed(team, "ebay")])
	if easy:
		var air := _enemy_air() > 0  # turrets are the easy AI's only answer to flyers
		plan = [
			["barracks", rax < 1 and elapsed > 90.0],
			["ebay", _count("ebay", buildings, workers) == 0 and (elapsed > 420.0 or air)],
			["turret", _count("turret", buildings, workers) < 2 and air and game.has_completed(team, "ebay")],
			["silo", _count("silo", buildings, workers) == 0 and elapsed > 470.0 and game.has_completed(team, "ebay")],
		]
	reserve = 0
	for entry in plan:
		if entry[1]:
			var cost: int = Defs.BUILDINGS[entry[0]].cost
			if game.bank[team] >= cost:
				_build(entry[0], cc, workers)
			else:
				reserve = cost
			break


func _build(kind: String, cc, workers: Array) -> bool:
	if workers.is_empty():
		return false
	var spot = _find_spot(kind, cc.position)
	if spot == null:
		return false
	var w = null
	for cand in workers:
		if cand.build_kind == "" and cand.carrying == 0:
			w = cand
			break
	if w == null:
		w = workers[0]
	return game.try_order_build(w, kind, spot)


func _find_spot(kind: String, center: Vector2):
	var toward: Vector2 = (game.map_size / 2.0 - center).normalized()
	var defensive: bool = kind == "bunker" or kind == "turret"
	for i in 120:
		var ang := randf_range(-0.6, 0.6) if defensive else randf_range(-1.6, 1.6)
		var far := i / 40 * 120.0  # widen the search ring when the base gets crowded
		var dist := randf_range(380.0, 520.0) if defensive else randf_range(170.0, 430.0 + far)
		var p: Vector2 = game.snap(center + toward.rotated(ang) * dist)
		if game.can_place(kind, p, 45.0):  # leave walkways between AI buildings
			return p
	return null


func _military(cc, army: Array, buildings: Array) -> void:
	# Boss: one Titan once the base is established; minerals are held back for it.
	# Ages: advance when the economy allows (the easy AI later); minerals are held back for it.
	if cc != null and game.ages[team] + 1 < Defs.AGES.size() and not game.age_in_progress(team):
		var n: int = game.ages[team] + 1
		var at: float = [0.0, 0.0, 220.0, 400.0, 600.0][n] * (1.4 if easy else 1.0)
		if elapsed > at and game.has_completed(team, Defs.AGES[n].requires):
			if not game.try_age_up(cc):
				reserve = maxi(reserve, int(Defs.AGES[n].cost))
	if _wants_titan(cc):
		if not game.try_train(cc, "titan"):
			reserve = maxi(reserve, int(Defs.UNITS.titan.cost))
	# Missiles: keep the silo loaded (random affordable type) and fire at the densest group of
	# enemy units and buildings within the missile's range. The easy AI uses them too.
	for b in buildings:
		if b.kind != "silo" or not b.is_complete():
			continue
		if b.missile_ready:
			var md: Dictionary = Defs.MISSILES[b.missile_type]
			var tgt = _missile_target(b.position, md.range, md.radius)
			if tgt != null:
				game.launch_missile(b, tgt)
		elif b.queue.is_empty():
			var options := []
			for mk in Defs.MISSILES:
				if game.bank[team] - reserve >= Defs.MISSILES[mk].cost:
					options.append(mk)
			if not options.is_empty():
				game.try_arm_missile(b, options.pick_random())
	for b in buildings:
		if not b.is_complete() or game.bank[team] - reserve < 50:
			continue
		if easy and (b.kind != "barracks" or not b.queue.is_empty() or game.bank[team] < 100):
			continue
		if b.kind == "barracks" and b.queue.size() < 2:
			# one medic for every five marines
			var medic: bool = game.count_units(team, "medic") * 5 < game.count_units(team, "marine") - 2
			game.try_train(b, "medic" if medic else "marine")
		elif b.kind == "factory" and b.queue.size() < 1:
			# answer enemy flyers with AA Rovers, otherwise build tanks
			game.try_train(b, "aa" if game.count_units(team, "aa") < _enemy_air() else "tank")
		elif b.kind == "starport" and b.queue.size() < 1:
			var spare: int = game.bank[team] - reserve
			var kind := "wraith"
			if spare >= 500 and game.count_units(team, "devastator") < 2:
				kind = "devastator"
			elif spare >= 400:
				kind = "stormbird"
			elif spare >= 150 and game.count_units(team, "drone") < 4:
				kind = "drone"
			game.try_train(b, kind)
		elif b.kind == "ebay" and b.queue.is_empty() and game.bank[team] >= 250:
			if not game.try_research(b, "weapons"):
				game.try_research(b, "armor")
	# Merge idle units at home into super units whenever a recipe is complete.
	for ck in Defs.COMBOS:
		var idle := army.filter(func(u): return u.is_idle())
		game.start_combine(team, ck, idle)
	if army.is_empty():
		return
	var home: Vector2 = cc.position if cc != null else army[0].position
	var threat = _threat_near(home, 800.0)
	if threat != null:
		for a in army:
			if a.is_idle() and a.position.distance_to(home) < 1200.0:
				a.order_attack_move(threat.position)
		return
	if easy:
		return  # the easy (red) opponent only defends its base: no attack waves
	if army.size() >= wave_size:
		var tgt = _enemy_target(home)
		if tgt != null:
			for a in army:
				a.order_attack_move(tgt.position)
			wave_size = mini(wave_size + 4, 40)
		return
	# Units already out on the field keep pushing towards the next target.
	for a in army:
		if a.is_idle() and a.position.distance_to(home) > 900.0:
			var tgt = _enemy_target(a.position)
			if tgt != null:
				a.order_attack_move(tgt.position)


func _wants_titan(cc) -> bool:
	return not easy and cc != null and elapsed > 300.0 and game.has_completed(team, "barracks") \
			and game.count_units(team, "titan") == 0


func _enemy_air() -> int:
	var n := 0
	for u in game.get_tree().get_nodes_in_group("units"):
		if u.team != team and u.is_alive() and u.is_air():
			n += 1
	return n


func _missile_target(from: Vector2, max_range: float, r: float):
	var enemies := []
	for e in game.get_tree().get_nodes_in_group("units") + game.get_tree().get_nodes_in_group("buildings"):
		if e.team != team and e.team >= 0 and e.is_alive() and e.position.distance_to(from) <= max_range:
			enemies.append(e)
	var best = null
	var best_n := 0
	for c in enemies:
		var n := 0
		for e in enemies:
			if c.position.distance_squared_to(e.position) <= r * r:
				n += 2 if e.is_in_group("buildings") else 1
		if n > best_n:
			best_n = n
			best = c.position
	return best


func _threat_near(p: Vector2, r: float):
	for u in game.get_tree().get_nodes_in_group("units"):
		if u.team != team and u.is_alive() and u.position.distance_to(p) < r:
			return u
	return null


func _enemy_target(from: Vector2):
	var best = null
	var best_d := INF
	for b in game.get_tree().get_nodes_in_group("buildings"):
		if b.team != team and b.is_alive():
			var d := from.distance_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	if best == null:
		for u in game.get_tree().get_nodes_in_group("units"):
			if u.team != team and u.is_alive():
				return u
	return best
