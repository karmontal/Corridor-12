class_name Simulation
extends RefCounted
## One scenario played day by day: plan convoys, resolve the day, score its impact.
## Pure rules with no nodes, deterministic for a given seed, so tests can replay a whole scenario.

const DAY_START := 360  # 06:00, first convoy leaves
const CURFEW := 1200  # 20:00, convoys still on the road turn back
const DEFAULT_DEADLINE := 840  # 14:00, later deliveries count as late
const DEPART_GAP := 10  # minutes between departures
const INCIDENT_DELAY := 30
const INCIDENT_LOSS := 0.5  # share of cargo lost in an incident
const STANCES := {
	"fast": {"time": 1.0, "risk": 0.0, "fuel": 0.2},
	"balanced": {"time": 1.0, "risk": 150.0, "fuel": 0.5},
	"safe": {"time": 0.3, "risk": 500.0, "fuel": 0.2},
}
const STATUS_DELIVERED := "delivered"
const STATUS_HELD := "held"  # reached a checkpoint after it closed
const STATUS_CURFEW := "curfew"  # would arrive after curfew

var scenario: Dictionary
var graph: RoadGraph
var events: Dictionary
var rng := RandomNumberGenerator.new()
var day := 1
var fuel := 0.0
var trucks := 0  # trucks available today
var stock := {}  # warehouse id -> {food, med}
var need := {}  # district id -> {food, med} still needed (today's demand + backlog)
var plan: Array[Dictionary] = []
var today_event: Dictionary = {}
var event_target := ""  # district an event picked, for the card text
var choice_pending := false
var urgent := ""  # district whose aid counts double today
var mods := {}
var history: Array[Dictionary] = []
var values := {"lives": 0, "speed": 0, "fairness": 0, "safety": 0}  # from dilemma choices
var stance_counts := {"fast": 0, "balanced": 0, "safe": 0}
var _active: Array[Dictionary] = []  # running event effects: {effect, days_left, edge}
var _last_event_id := ""
var _next_id := 1


func _init(s: Dictionary, event_cards: Dictionary, seed_override: int = -1) -> void:
	scenario = s
	events = event_cards
	graph = RoadGraph.new(s)
	rng.seed = int(s.seed) if seed_override < 0 else seed_override
	fuel = float(s.start.fuel)
	for id in warehouses():
		var st: Dictionary = graph.nodes[id].stock
		stock[id] = {"food": int(st.get("food", 0)), "med": int(st.get("med", 0))}
	for id in districts():
		need[id] = {"food": 0, "med": 0}
	_begin_day()


func warehouses() -> Array:
	return graph.ids_of_type("warehouse")


func districts() -> Array:
	return graph.ids_of_type("district")


func days_total() -> int:
	return int(scenario.days)


func is_over() -> bool:
	return history.size() >= days_total()


func truck_capacity() -> int:
	return int(scenario.start.truck_capacity)


func name_of(id: String) -> String:
	return str(graph.nodes[id].get("name", id))


# --- Day start and events ---------------------------------------------------------------------

func _begin_day() -> void:
	plan.clear()
	urgent = ""
	event_target = ""
	for id in districts():
		var d: Dictionary = graph.nodes[id].demand
		need[id].food += int(d.get("food", 0))
		need[id].med += int(d.get("med", 0))
	if day > 1:
		var r: Dictionary = scenario.resupply
		fuel += float(r.get("fuel", 0))
		var w: String = warehouses()[0]
		stock[w].food += int(r.get("food", 0))
		stock[w].med += int(r.get("med", 0))
		for a in _active:
			a.days_left -= 1
		_active.assign(_active.filter(func(a): return a.days_left > 0))
	_refresh_mods()
	today_event = _draw_event()
	choice_pending = today_event.has("choices")
	if not today_event.is_empty() and not choice_pending:
		_apply(today_event.effect)
	_refresh_mods()


func _draw_event() -> Dictionary:
	# Day one is calm so the player can learn the map.
	if day == 1 or scenario.events.is_empty() or rng.randf() >= float(scenario.event_chance):
		return {}
	var pool: Array = scenario.events.filter(func(id): return id != _last_event_id and events.has(id))
	if pool.is_empty():
		return {}
	var total := 0.0
	for id in pool:
		total += float(events[id].weight)
	var roll := rng.randf() * total
	var pick: String = pool[-1]
	for id in pool:
		roll -= float(events[id].weight)
		if roll <= 0.0:
			pick = id
			break
	_last_event_id = pick
	return events[pick]


## Answers today's dilemma card with choice 0 or 1.
func choose(index: int) -> void:
	if not choice_pending:
		return
	var c: Dictionary = today_event.choices[index]
	for k in c.get("values", {}):
		values[k] += int(c.values[k])
	_apply(c.get("effect", {}))
	choice_pending = false
	_refresh_mods()


func _apply(effect: Dictionary) -> void:
	var target := ""
	if effect.has("surge") or effect.has("urgent"):
		var pool := districts()
		target = pool[rng.randi_range(0, pool.size() - 1)]
		event_target = name_of(target)
	if effect.has("surge"):
		need[target].food += int(effect.surge.get("food", 0))
		need[target].med += int(effect.surge.get("med", 0))
	if effect.get("urgent", false):
		urgent = target
	if effect.has("stock"):
		var w: String = warehouses()[0]
		stock[w].food = maxi(0, stock[w].food + int(effect.stock.get("food", 0)))
		stock[w].med = maxi(0, stock[w].med + int(effect.stock.get("med", 0)))
	if effect.has("fuel"):
		fuel = maxf(0.0, fuel + float(effect.fuel))
	for k in ["risk_add", "risk_mult", "fuel_mult", "window_cut", "window_extend", "checkpoint_delay", "trucks", "close_random_edge"]:
		if effect.has(k):
			var entry := {"effect": effect, "days_left": int(effect.get("days", 1)), "edge": -1}
			if effect.get("close_random_edge", false):
				entry.edge = _pick_closable_edge()
			_active.append(entry)
			break


func _pick_closable_edge() -> int:
	var order := range(graph.edges.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for i in order:
		var e: Dictionary = graph.edges[i]
		if e.closed:
			continue
		e.closed = true
		var ok := graph.all_districts_reachable()
		e.closed = false
		if ok:
			return i
	return -1


func _refresh_mods() -> void:
	mods = {"risk_add": 0.0, "risk_mult": 1.0, "fuel_mult": 1.0, "window_cut": 0, "window_extend": 0, "checkpoint_delay": 0, "trucks": 0}
	for e in graph.edges:
		e.closed = false
	for a in _active:
		var eff: Dictionary = a.effect
		mods.risk_add += float(eff.get("risk_add", 0.0))
		mods.risk_mult *= float(eff.get("risk_mult", 1.0))
		mods.fuel_mult *= float(eff.get("fuel_mult", 1.0))
		mods.window_cut += int(eff.get("window_cut", 0))
		mods.window_extend += int(eff.get("window_extend", 0))
		mods.checkpoint_delay += int(eff.get("checkpoint_delay", 0))
		mods.trucks += int(eff.get("trucks", 0))
		if a.edge >= 0:
			graph.edges[a.edge].closed = true
	graph.risk_add = mods.risk_add
	graph.risk_mult = mods.risk_mult
	graph.checkpoint_delay = mods.checkpoint_delay
	graph.windows.clear()
	for id in graph.ids_of_type("checkpoint"):
		graph.windows[id] = checkpoint_window(id)
	trucks = maxi(1, int(scenario.start.trucks) + mods.trucks)


## Today's opening hours of a checkpoint in minutes since midnight; x == y means closed all day.
func checkpoint_window(id: String) -> Vector2i:
	var w: Array = graph.nodes[id].window
	var open := int(w[0])
	var close := maxi(open, int(w[1]) - mods.window_cut + mods.window_extend)
	return Vector2i(open, close)


func deadline(id: String) -> int:
	return int(graph.nodes[id].get("deadline", DEFAULT_DEADLINE))


# --- Planning ---------------------------------------------------------------------------------

func next_departure() -> int:
	return DAY_START + DEPART_GAP * plan.size()


func free_trucks() -> int:
	var used := 0
	for c in plan:
		used += c.trucks
	return trucks - used


func free_fuel() -> float:
	var used := 0.0
	for c in plan:
		used += c.fuel
	return fuel - used


## What a convoy would need and when it would arrive (without incidents). `ok` false comes with an Arabic reason.
func preview(from: String, to: String, stance: String, food: int, med: int) -> Dictionary:
	var r := {"ok": false, "reason": "", "path": [], "trucks": 0, "fuel": 0.0, "time": 0.0, "risk": 0.0, "arrival": 0, "status": "", "spoils": false}
	if not stock.has(from):
		r.reason = "اختر مستودعاً على الخريطة"
		return r
	if not need.has(to):
		r.reason = "اختر حياً على الخريطة"
		return r
	var depart := next_departure()
	var path := graph.find_route(from, to, STANCES[stance], depart)
	if path.is_empty():
		var blocked := not graph.find_route(from, to, STANCES[stance]).is_empty()
		r.reason = "الحاجز يكون مغلقاً عند الوصول" if blocked else "لا يوجد طريق مفتوح"
		return r
	r.path = path
	var stats := graph.route_stats(path)
	r.time = stats.time
	r.risk = stats.risk
	var units := food + med
	var trip := _travel(path, depart, false)
	r.arrival = trip.arrival
	r.status = trip.status
	r.spoils = med > 0 and trip.arrival - depart > int(scenario.med_max_minutes)
	if units <= 0:
		r.reason = "حمّل غذاءً أو دواءً"
		return r
	if food > stock[from].food or med > stock[from].med:
		r.reason = "المخزون لا يكفي"
		return r
	r.trucks = ceili(float(units) / truck_capacity())
	r.fuel = stats.fuel * r.trucks * mods.fuel_mult
	if r.trucks > free_trucks():
		r.reason = "لا توجد شاحنات كافية"
		return r
	if r.fuel > free_fuel() + 0.001:
		r.reason = "الوقود لا يكفي"
		return r
	r.ok = true
	return r


func add_convoy(from: String, to: String, stance: String, food: int, med: int) -> Dictionary:
	var r := preview(from, to, stance, food, med)
	if r.ok:
		stock[from].food -= food
		stock[from].med -= med
		plan.append({"id": _next_id, "from": from, "to": to, "stance": stance, "food": food, "med": med,
			"path": r.path, "trucks": r.trucks, "fuel": r.fuel})
		_next_id += 1
	return r


func remove_convoy(id: int) -> void:
	for i in plan.size():
		if plan[i].id == id:
			stock[plan[i].from].food += plan[i].food
			stock[plan[i].from].med += plan[i].med
			plan.remove_at(i)
			return


## Fills the plan with a fair split of each warehouse's stock across the districts it serves best.
func auto_plan(stance: String = "balanced") -> void:
	var w_stance: Dictionary = STANCES[stance]
	var home := {}
	for d in districts():
		var best := INF
		for w in warehouses():
			var path := graph.find_route(w, d, w_stance, DAY_START)
			if not path.is_empty() and graph.route_stats(path).time < best:
				best = graph.route_stats(path).time
				home[d] = w
	for w in warehouses():
		var mine := districts().filter(func(d): return home.get(d) == w and need[d].food + need[d].med > 0)
		mine.sort_custom(func(a, b): return (a == urgent) or (b != urgent and need[a].food + need[a].med > need[b].food + need[b].med))
		var total_food := 0
		var total_med := 0
		for d in mine:
			total_food += need[d].food
			total_med += need[d].med
		var share_food := {}
		var share_med := {}
		for d in mine:
			share_food[d] = mini(need[d].food, int(stock[w].food * need[d].food / maxf(1.0, total_food)))
			share_med[d] = mini(need[d].med, int(stock[w].med * need[d].med / maxf(1.0, total_med)))
		for d in mine:
			var food: int = share_food[d]
			var med: int = share_med[d]
			var path := graph.find_route(w, d, w_stance, next_departure())
			if path.is_empty():
				continue
			var per_truck: float = graph.route_stats(path).fuel * mods.fuel_mult
			var affordable := free_trucks()
			if per_truck > 0.0:
				affordable = mini(affordable, int(free_fuel() / per_truck))
			var cap := affordable * truck_capacity()
			if cap <= 0 or food + med <= 0:
				continue
			if food + med > cap:
				var k := float(cap) / (food + med)
				food = int(food * k)
				med = mini(cap - food, int(med * k))
			add_convoy(w, d, stance, food, med)


# --- Running a day ------------------------------------------------------------------------------

## Moves along a path from `depart`. With `roll` true, each road may cause an incident.
func _travel(path: Array, depart: int, roll: bool) -> Dictionary:
	var t := depart
	var points := [{"node": path[0], "t": t}]
	var incidents := []
	var status := STATUS_DELIVERED
	for i in range(1, path.size()):
		var e: Dictionary = graph.edges[graph.edge_between(path[i - 1], path[i])]
		t += int(e.time)
		if roll and rng.randf() < graph.effective_risk(e):
			incidents.append(path[i])
			t += INCIDENT_DELAY
		points.append({"node": path[i], "t": t})
		if graph.nodes[path[i]].type == "checkpoint":
			var w := checkpoint_window(path[i])
			if t > w.y or w.x == w.y:
				status = STATUS_HELD
				break
			t = maxi(t, w.x) + mods.checkpoint_delay
			points.append({"node": path[i], "t": t})
	if status == STATUS_DELIVERED and t > CURFEW:
		status = STATUS_CURFEW
	return {"points": points, "arrival": t, "status": status, "incidents": incidents}


## Resolves the planned convoys and returns the day report. Call next_day() after showing it.
func run_day() -> Dictionary:
	if choice_pending:
		choose(0)
	var start_need := {}
	var people_needed := 0.0
	var need_units := {"food": 0, "med": 0}
	for d in districts():
		start_need[d] = need[d].duplicate()
		people_needed += _people(d, need[d].food, need[d].med)
		need_units.food += need[d].food
		need_units.med += need[d].med
	# What today's stock could have covered at best: the lives score is measured against this.
	var stock_units := {"food": 0, "med": 0}
	for c in plan:
		stock_units.food += c.food
		stock_units.med += c.med
	for w in warehouses():
		stock_units.food += stock[w].food
		stock_units.med += stock[w].med
	var ppu: Dictionary = scenario.people_per_unit
	var people_possible: float = mini(need_units.food, stock_units.food) * float(ppu.food) + mini(need_units.med, stock_units.med) * float(ppu.med)
	var results := []
	var fuel_used := 0.0
	for i in plan.size():
		var c: Dictionary = plan[i]
		stance_counts[c.stance] += 1
		fuel_used += c.fuel
		var depart := DAY_START + DEPART_GAP * i
		var trip := _travel(c.path, depart, true)
		var food: int = c.food
		var med: int = c.med
		for _n in trip.incidents:
			food -= int(food * INCIDENT_LOSS)
			med -= int(med * INCIDENT_LOSS)
		var spoiled := 0
		if trip.status == STATUS_DELIVERED and med > 0 and trip.arrival - depart > int(scenario.med_max_minutes):
			spoiled = med
			med = 0
		results.append({"id": c.id, "from": c.from, "to": c.to, "stance": c.stance, "status": trip.status,
			"arrival": trip.arrival, "points": trip.points, "incidents": trip.incidents.size(),
			"incident_nodes": trip.incidents, "lost": (c.food - food) + (c.med - med - spoiled), "spoiled": spoiled,
			"cargo_food": food, "cargo_med": med, "delivered_food": 0, "delivered_med": 0, "on_time": false})
	fuel = maxf(0.0, fuel - fuel_used)
	var by_arrival := results.duplicate()
	by_arrival.sort_custom(func(a, b): return a.arrival < b.arrival)
	var people := 0.0
	var on_time := 0
	var incidents := 0
	var spoiled_total := 0
	for r in by_arrival:
		incidents += r.incidents
		spoiled_total += r.spoiled
		if r.status != STATUS_DELIVERED:
			stock[r.from].food += r.cargo_food
			stock[r.from].med += r.cargo_med
			continue
		var d: String = r.to
		r.delivered_food = mini(r.cargo_food, need[d].food)
		r.delivered_med = mini(r.cargo_med, need[d].med)
		need[d].food -= r.delivered_food
		need[d].med -= r.delivered_med
		stock[r.from].food += r.cargo_food - r.delivered_food
		stock[r.from].med += r.cargo_med - r.delivered_med
		people += _people(d, r.delivered_food, r.delivered_med)
		r.on_time = r.arrival <= deadline(d)
		if r.on_time:
			on_time += 1
	var coverage := []
	var critical := []
	for d in districts():
		var wanted: int = start_need[d].food + start_need[d].med
		if wanted > 0:
			coverage.append(1.0 - float(need[d].food + need[d].med) / wanted)
		var daily: Dictionary = graph.nodes[d].demand
		if need[d].food + need[d].med >= int(daily.get("food", 0)) + int(daily.get("med", 0)):
			critical.append(d)
	var sent := plan.size()
	var report := {
		"day": day,
		"convoys": results,
		"people_reached": int(people),
		"people_needed": int(people_needed),
		"people_possible": int(people_possible),
		"lives": 100.0 if people_possible <= 0.0 else minf(100.0, 100.0 * people / people_possible),
		"on_time": 0.0 if sent == 0 else 100.0 * on_time / sent,
		"equity": equity(coverage),
		"safety": 100.0 if sent == 0 else clampf(100.0 - 100.0 * incidents / sent, 0.0, 100.0),
		"incidents": incidents,
		"spoiled": spoiled_total,
		"fuel_used": fuel_used,
		"critical": critical,
		"urgent": urgent,
	}
	history.append(report)
	return report


func _people(district: String, food: int, med: int) -> float:
	var ppu: Dictionary = scenario.people_per_unit
	var p := food * float(ppu.food) + med * float(ppu.med)
	return p * 2.0 if district == urgent else p


## 100 when every district got the same share of what it needed, lower the more uneven it is.
static func equity(coverage: Array) -> float:
	if coverage.size() < 2:
		return 100.0
	var mean := 0.0
	for c in coverage:
		mean += c
	mean /= coverage.size()
	var variance := 0.0
	for c in coverage:
		variance += (c - mean) * (c - mean)
	variance /= coverage.size()
	return clampf(100.0 * (1.0 - 2.0 * sqrt(variance)), 0.0, 100.0)


func next_day() -> void:
	if is_over():
		return
	day += 1
	_begin_day()


# --- Scenario result ----------------------------------------------------------------------------

func summary() -> Dictionary:
	var keys := ["lives", "on_time", "equity", "safety"]
	var avg := {}
	for k in keys:
		avg[k] = 0.0
	var people := 0
	var needed := 0
	for r in history:
		for k in keys:
			avg[k] += r[k] / maxf(1.0, history.size())
		people += r.people_reached
		needed += r.people_needed
	var score: float = 0.45 * avg.lives + 0.2 * avg.equity + 0.15 * avg.on_time + 0.2 * avg.safety
	var stars := 3 if score >= 80.0 else 2 if score >= 62.0 else 1 if score >= 40.0 else 0
	var tally := values.duplicate()
	tally.speed += stance_counts.fast
	tally.safety += stance_counts.safe
	if avg.equity >= 75.0:
		tally.fairness += 2
	if avg.lives >= 70.0:
		tally.lives += 2
	var style := "lives"
	for k in ["lives", "fairness", "safety", "speed"]:
		if tally[k] > tally[style]:
			style = k
	return {"avg": avg, "people": people, "needed": needed, "score": score, "stars": stars, "style": style}
