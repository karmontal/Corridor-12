extends Node
## Headless test suite. Run:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 on success, 1 on any failure.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _failures := 0
var _checks := 0
var _events := {}
var _scenarios := {}


func _ready() -> void:
	Progress.path = "user://test_progress.json"
	Progress.reset()
	_events = ScenarioData.load_events()
	for s in ScenarioData.load_all():
		_scenarios[s.id] = s
	_test_data_valid()
	_test_validator_catches_mistakes()
	_test_routing()
	_test_planning()
	_test_travel_rules()
	_test_run_day()
	_test_equity()
	_test_events()
	_test_full_playthroughs()
	_test_assets()
	await _test_ui_flow()
	Progress.reset()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + label)


func eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [label, expected, actual])


func _sim(id: String, seed_override: int = -1) -> Simulation:
	return Simulation.new(_scenarios[id].duplicate(true), _events, seed_override)


func _test_data_valid() -> void:
	eq(_scenarios.size(), 3, "three scenarios")
	for id in ["north", "two_gates", "cold_chain"]:
		check(_scenarios.has(id), "scenario %s exists" % id)
	for id in _scenarios:
		var errs := ScenarioData.validate(_scenarios[id], _events)
		check(errs.is_empty(), "%s is valid: %s" % [id, errs])
	check(_events.size() >= 10, "at least 10 event cards")
	for id in _events:
		var errs := ScenarioData.validate_event(_events[id])
		check(errs.is_empty(), "event %s is valid: %s" % [id, errs])


func _test_validator_catches_mistakes() -> void:
	var s: Dictionary = _scenarios.north.duplicate(true)
	s.edges.append({"a": "W1", "b": "NOPE", "time": 10, "risk": 0.1, "fuel": 1})
	check(not ScenarioData.validate(s, _events).is_empty(), "edge to an unknown node is caught")
	s = _scenarios.north.duplicate(true)
	s.edges = s.edges.filter(func(e): return e.a != "J2" and e.b != "J2" and e.a != "D3" and e.b != "D3")
	check(not ScenarioData.validate(s, _events).is_empty(), "unreachable district is caught")
	s = _scenarios.north.duplicate(true)
	s.edges[0].risk = 2.0
	check(not ScenarioData.validate(s, _events).is_empty(), "risk above 0.95 is caught")
	s = _scenarios.north.duplicate(true)
	s.events.append("no_such_event")
	check(not ScenarioData.validate(s, _events).is_empty(), "unknown event id is caught")
	check(not ScenarioData.validate_event({"id": "x", "title": "t", "text": "t", "weight": 1, "effect": {"bogus": 1}}).is_empty(),
		"unknown effect key is caught")


func _test_routing() -> void:
	var g := RoadGraph.new(_scenarios.north)
	var fast: Dictionary = Simulation.STANCES.fast
	var safe: Dictionary = Simulation.STANCES.safe
	eq(g.find_route("W1", "D1", fast), ["W1", "X1", "D2", "D1"], "untimed fastest route uses road time only")
	g.windows["X1"] = Vector2i(480, 780)
	eq(g.find_route("W1", "D1", fast, 360), ["W1", "J1", "D1"], "timed fastest route avoids waiting at the checkpoint")
	eq(g.find_route("W1", "D1", safe, 360), ["W1", "X1", "D2", "D1"], "safest route goes through the checkpoint")
	g.windows["X1"] = Vector2i(300, 350)
	check(not g.find_route("W1", "D2", safe, 360).has("X1"), "a checkpoint closed on arrival is avoided")
	g.windows.clear()
	g.edges[g.edge_between("W1", "X1")].closed = true
	eq(g.find_route("W1", "D2", fast), ["W1", "J1", "D2"], "closed road is routed around")
	var stats := g.route_stats(["W1", "J1", "D1"])
	eq(stats.time, 130.0, "route time sums the roads")
	eq(stats.fuel, 14.0, "route fuel sums the roads")
	var r1: float = g.edges[g.edge_between("W1", "J1")].risk
	var r2: float = g.edges[g.edge_between("J1", "D1")].risk
	check(absf(stats.risk - (1.0 - (1.0 - r1) * (1.0 - r2))) < 0.0001, "route risk is the chance of at least one incident")
	g.risk_add = 0.5
	check(absf(g.effective_risk(g.edges[0]) - (g.edges[0].risk + 0.5)) < 0.0001, "risk modifiers add up")
	g.risk_add = 5.0
	eq(g.effective_risk(g.edges[0]), 0.95, "risk is capped at 0.95")


func _test_planning() -> void:
	var sim := _sim("north")
	check(sim.today_event.is_empty(), "day one has no event")
	eq(sim.need.D2, {"food": 170, "med": 25}, "need starts at the daily demand")
	check(not sim.preview("", "D2", "balanced", 10, 0).ok, "no warehouse selected")
	check(not sim.preview("W1", "D2", "balanced", 0, 0).ok, "empty convoy is refused")
	check(not sim.preview("W1", "D2", "balanced", 9999, 0).ok, "more than the stock is refused")
	check(not sim.preview("W1", "D2", "balanced", 520, 90).ok, "more than six trucks is refused")
	var r := sim.add_convoy("W1", "D2", "safe", 170, 25)
	check(r.ok, "convoy added: %s" % r.reason)
	eq(r.trucks, 2, "195 units need two trucks of 100")
	eq(sim.stock.W1, {"food": 350, "med": 65}, "stock is reserved")
	eq(sim.free_trucks(), 4, "trucks are reserved")
	check(sim.free_fuel() < 160.0, "fuel is reserved")
	sim.remove_convoy(sim.plan[0].id)
	eq(sim.stock.W1, {"food": 520, "med": 90}, "removing a convoy gives the stock back")
	eq(sim.free_trucks(), 6, "removing a convoy frees its trucks")
	sim.auto_plan("balanced")
	check(sim.plan.size() >= 3, "suggested plan sends at least three convoys")
	var sent := {}
	for c in sim.plan:
		sent[c.to] = true
	eq(sent.size(), 3, "suggested plan serves every district")


func _test_travel_rules() -> void:
	var sim := _sim("north")
	var held := sim._travel(["W1", "X1", "D2"], 360, false)
	eq(held.status, Simulation.STATUS_DELIVERED, "early convoy waits for the checkpoint and passes")
	eq(held.arrival, 480 + 45, "waits until 08:00 then drives on")
	var late := sim._travel(["W1", "X1", "D2"], 770, false)
	eq(late.status, Simulation.STATUS_HELD, "convoy reaching the checkpoint after it closes is held")
	var curfew := sim._travel(["W1", "J1", "D1"], 1100, false)
	eq(curfew.status, Simulation.STATUS_CURFEW, "convoy arriving after 20:00 turns back")
	var cold := _sim("cold_chain")
	var r := cold.preview("W1", "D2", "fast", 40, 40)
	check(r.ok, "cold chain convoy is possible")
	check(not r.spoils, "fast route avoids the checkpoint wait that spoils medicine")
	var slow := cold._travel(["W1", "X1", "J3", "D1"], 360, false)
	check(slow.arrival - 360 > int(cold.scenario.med_max_minutes), "waiting at the valley checkpoint is too long for medicine")


func _test_run_day() -> void:
	var sim := _sim("north", 5)
	sim.add_convoy("W1", "D2", "safe", 170, 25)
	sim.add_convoy("W1", "D3", "safe", 130, 30)
	var report := sim.run_day()
	eq(report.day, 1, "report is for day one")
	eq(report.convoys.size(), 2, "both convoys reported")
	check(report.people_reached <= report.people_needed, "cannot reach more people than need help")
	check(report.lives > 0.0 and report.lives <= 100.0, "lives score is a percentage")
	check(report.critical.has("D1"), "district with no convoy is critical")
	check(report.equity < 100.0, "skipping a district lowers equity")
	eq(sim.history.size(), 1, "day is recorded")
	check(sim.need.D1.food == 150, "unserved need stays as backlog")
	sim.next_day()
	eq(sim.day, 2, "next day starts")
	eq(sim.need.D1.food, 300, "backlog adds to the new day's demand")
	check(sim.stock.W1.food >= 330, "warehouse is resupplied")
	# Same seed and plan give the same day.
	var a := _sim("north", 9)
	var b := _sim("north", 9)
	for s in [a, b]:
		s.add_convoy("W1", "D1", "fast", 150, 20)
	eq(a.run_day().incidents, b.run_day().incidents, "simulation is deterministic for a seed")


func _test_equity() -> void:
	eq(Simulation.equity([1.0, 1.0, 1.0]), 100.0, "equal coverage is fully fair")
	eq(Simulation.equity([0.5, 0.5]), 100.0, "equal partial coverage is fair")
	eq(Simulation.equity([1.0, 0.0]), 0.0, "all to one district is unfair")
	check(Simulation.equity([1.0, 0.6, 0.8]) < 100.0, "uneven coverage lowers equity")


func _test_events() -> void:
	var sim := _sim("north")
	sim.today_event = _events.escort
	sim.choice_pending = true
	sim.choose(0)
	eq(sim.trucks, 4, "escort takes two trucks")
	eq(sim.graph.risk_mult, 0.5, "escort halves risk")
	eq(sim.values.safety, 1, "choice is recorded in the decision profile")
	check(not sim.choice_pending, "choice is answered")
	sim = _sim("north")
	sim.today_event = _events.hospital
	sim.choice_pending = true
	sim.choose(0)
	check(sim.urgent != "", "hospital choice marks an urgent district")
	eq(sim.need[sim.urgent].med, int(sim.graph.nodes[sim.urgent].demand.med) + 25, "urgent district needs more medicine")
	for seed in 20:
		var s := _sim("two_gates", seed)
		s._apply(_events.road_closed.effect)
		s._refresh_mods()
		var closed := s.graph.edges.filter(func(e): return e.closed).size()
		eq(closed, 1, "road closure closes one road (seed %d)" % seed)
		check(s.graph.all_districts_reachable(), "road closure never cuts off a district (seed %d)" % seed)
	sim = _sim("north")
	sim._apply(_events.window_cut.effect)
	sim._refresh_mods()
	eq(sim.checkpoint_window("X1"), Vector2i(480, 690), "window cut closes the checkpoint earlier")
	sim.next_day()
	eq(sim.checkpoint_window("X1"), Vector2i(480, 780), "one-day effects end the next day")


func _test_full_playthroughs() -> void:
	for id in _scenarios:
		for seed in 6:
			var sim := _sim(id, seed)
			var stances := ["balanced", "safe", "fast"]
			var ok := true
			while not sim.is_over():
				if sim.choice_pending:
					sim.choose(seed % 2)
				sim.auto_plan(stances[sim.day % 3])
				var r := sim.run_day()
				ok = ok and r.lives >= 0.0 and r.lives <= 100.0 and r.equity >= 0.0
				for w in sim.stock:
					ok = ok and sim.stock[w].food >= 0 and sim.stock[w].med >= 0
				for d in sim.need:
					ok = ok and sim.need[d].food >= 0 and sim.need[d].med >= 0
				ok = ok and sim.fuel >= 0.0
				sim.next_day()
			check(ok, "%s seed %d keeps every number in range" % [id, seed])
			eq(sim.history.size(), sim.days_total(), "%s seed %d plays all days" % [id, seed])
			var sum := sim.summary()
			check(sum.stars >= 0 and sum.stars <= 3, "%s seed %d gives 0-3 stars" % [id, seed])
			check(sum.people > 0, "%s seed %d reaches people with the suggested plan" % [id, seed])
		var first := _sim(id)
		first.auto_plan("balanced")
		var day1 := first.run_day()
		check(day1.lives >= 50.0, "%s: suggested plan reaches at least half the need on day one (%d%%)" % [id, day1.lives])


## The Higgsfield files the screens ask for (tools/fetch_assets.sh); a typo here would fall back silently.
func _test_assets() -> void:
	for f in ["menu_bg.jpg", "map_bg.jpg", "event.jpg", "end_bg.jpg", "warehouse.png", "checkpoint.png", "district.png", "truck.png"]:
		check(Art.texture(f) != null, "art %s loads" % f)
	for k in ["tap", "engine", "load", "radio", "success", "alarm", "card", "stars", "music_plan", "music_menu"]:
		check(Sfx.stream(k) != null, "sound %s loads" % k)
	check(Art.texture("missing.png") == null and Sfx.stream("missing") == null, "missing files are skipped")


func _test_ui_flow() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	var menu: Node = main.screen
	eq(menu.name, "menu", "game opens on the menu")
	for id in _scenarios:
		check(menu.find_child("Play_" + id, true, false) != null, "menu lists %s" % id)
	(menu.find_child("HowTo", true, false) as Button).pressed.emit()
	check(menu.find_child("Help", true, false) != null, "how to play opens")
	(menu.find_child("CloseHelp", true, false) as Button).pressed.emit()
	var music_was: bool = Sfx.music_on
	(menu.find_child("Music", true, false) as Button).pressed.emit()
	check(Sfx.music_on != music_was, "music switch toggles")
	(menu.find_child("Music", true, false) as Button).pressed.emit()
	check(menu.find_child("Backdrop", true, false) != null, "menu shows its picture")
	(menu.find_child("Play_north", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var game: Node = main.screen
	eq(game.name, "game", "scenario opens the game screen")
	var add := game.find_child("AddConvoy", true, false) as Button
	check(add.disabled, "nothing to add before choosing a district")
	game.select_node("W1")
	game.select_node("D2")
	check(not add.disabled, "convoy can be added after tapping warehouse and district")
	eq([game.food, game.med], [170, 25], "cargo is filled with the district's need")
	(game.find_child("FoodMinus", true, false) as Button).pressed.emit()
	eq(game.food, 150, "food stepper lowers the load")
	(game.find_child("Stance_safe", true, false) as Button).pressed.emit()
	eq(game.stance, "safe", "stance button switches routing")
	add.pressed.emit()
	eq(game.sim.plan.size(), 1, "add button plans the convoy")
	check(game.find_child("Remove_1", true, false) != null, "planned convoy can be removed")
	(game.find_child("Suggest", true, false) as Button).pressed.emit()
	check(game.sim.plan.size() >= 3, "suggested plan fills the day")
	(game.find_child("StartDay", true, false) as Button).pressed.emit()
	check(game.playing, "starting the day plays the convoys")
	for i in 5:
		await get_tree().process_frame
	(game.find_child("StartDay", true, false) as Button).pressed.emit()
	check(not game.playing, "skip ends the playback")
	check(game.find_child("Report", true, false) != null, "day report is shown")
	check(game.find_child("ImpactBoard", true, false) != null, "report has the impact board")
	var guard := 0
	while main.screen.name == "game" and guard < 20:
		guard += 1
		game = main.screen
		var next := game.find_child("NextDay", true, false) as Button
		if next != null:
			next.pressed.emit()
			await get_tree().process_frame
			continue
		var choice := game.find_child("Choice0", true, false) as Button
		if choice != null:
			choice.pressed.emit()
			check(not game.sim.choice_pending, "dilemma choice is applied")
		var ok := game.find_child("EventOk", true, false) as Button
		if ok != null:
			ok.pressed.emit()
		check(game.overlay == null, "event card closes")
		(game.find_child("Suggest", true, false) as Button).pressed.emit()
		game.start_day(false)
		await get_tree().process_frame
	var end: Node = main.screen
	eq(end.name, "end", "scenario ends on the result screen")
	check(end.find_child("Stars", true, false) != null, "result shows stars")
	check(end.find_child("Style", true, false) != null, "result names the decision style")
	check(Progress.best.has("north") or end.args.summary.stars == 0, "result is saved")
	(end.find_child("Menu", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	eq(main.screen.name, "menu", "back to the menu")
	main.queue_free()
