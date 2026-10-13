class_name ScenarioData
extends RefCounted
## Loads scenarios (data/scenarios/*.json) and event cards (data/events.json) and checks their schema.

const SCENARIO_DIR := "res://data/scenarios"
const EVENTS_PATH := "res://data/events.json"
const NODE_TYPES := ["warehouse", "checkpoint", "junction", "district"]
const EFFECT_KEYS := [
	"days", "risk_add", "risk_mult", "fuel_mult", "window_cut", "window_extend", "checkpoint_delay",
	"trucks", "close_random_edge", "stock", "fuel", "surge", "urgent",
]
const VALUE_KEYS := ["lives", "speed", "fairness", "safety"]


static func read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)


## All scenarios, sorted by their "order" field.
static func load_all() -> Array:
	var out := []
	for f in DirAccess.get_files_at(SCENARIO_DIR):
		# Exported builds may list "x.json.remap"; only plain JSON files are scenarios.
		if f.ends_with(".json"):
			var s: Variant = read_json(SCENARIO_DIR + "/" + f)
			if s is Dictionary:
				out.append(s)
	out.sort_custom(func(a, b): return a.get("order", 0) < b.get("order", 0))
	return out


static func load_events() -> Dictionary:
	var out := {}
	var list: Variant = read_json(EVENTS_PATH)
	if list is Array:
		for e in list:
			out[e.id] = e
	return out


## Every problem found in a scenario, as readable strings. Empty means valid.
static func validate(s: Dictionary, events: Dictionary) -> Array:
	var errs := []
	for key in ["id", "title", "brief", "days", "seed", "start", "resupply", "people_per_unit", "med_max_minutes", "nodes", "edges", "events", "event_chance"]:
		if not s.has(key):
			errs.append("missing '%s'" % key)
	if not errs.is_empty():
		return errs
	for key in ["fuel", "trucks", "truck_capacity"]:
		if float(s.start.get(key, 0)) <= 0:
			errs.append("start.%s must be > 0" % key)
	for key in ["food", "med"]:
		if float(s.people_per_unit.get(key, 0)) <= 0:
			errs.append("people_per_unit.%s must be > 0" % key)
	var ids := {}
	for n in s.nodes:
		var label := str(n.get("id", "?"))
		if ids.has(label):
			errs.append("duplicate node id %s" % label)
		ids[label] = n
		if not NODE_TYPES.has(n.get("type", "")):
			errs.append("%s has unknown type '%s'" % [label, n.get("type", "")])
		if not (n.get("pos") is Array and n.pos.size() == 2):
			errs.append("%s needs pos [x, y]" % label)
		elif n.pos[0] < 0 or n.pos[0] > 1000 or n.pos[1] < 0 or n.pos[1] > 640:
			errs.append("%s pos is outside the 1000x640 map" % label)
		if n.get("type") != "junction" and str(n.get("name", "")).is_empty():
			errs.append("%s needs a name" % label)
		match n.get("type"):
			"warehouse":
				if not (n.get("stock") is Dictionary):
					errs.append("%s needs stock" % label)
			"district":
				var d: Variant = n.get("demand")
				if not (d is Dictionary) or float(d.get("food", 0)) + float(d.get("med", 0)) <= 0:
					errs.append("%s needs a demand" % label)
			"checkpoint":
				var w: Variant = n.get("window")
				if not (w is Array and w.size() == 2 and w[0] < w[1]):
					errs.append("%s needs window [open, close] in minutes" % label)
	if Array(s.nodes).filter(func(n): return n.get("type") == "warehouse").is_empty():
		errs.append("no warehouse")
	if Array(s.nodes).filter(func(n): return n.get("type") == "district").is_empty():
		errs.append("no district")
	var pairs := {}
	for e in s.edges:
		var a := str(e.get("a", ""))
		var b := str(e.get("b", ""))
		if not ids.has(a) or not ids.has(b) or a == b:
			errs.append("edge %s-%s joins unknown nodes" % [a, b])
			continue
		var key := "%s|%s" % ([a, b] if a < b else [b, a])
		if pairs.has(key):
			errs.append("duplicate edge %s-%s" % [a, b])
		pairs[key] = true
		if float(e.get("time", 0)) <= 0 or float(e.get("fuel", -1)) < 0:
			errs.append("edge %s-%s needs time > 0 and fuel >= 0" % [a, b])
		var r := float(e.get("risk", -1))
		if r < 0.0 or r > 0.95:
			errs.append("edge %s-%s risk must be 0..0.95" % [a, b])
	if errs.is_empty() and not RoadGraph.new(s).all_districts_reachable():
		errs.append("a district cannot be reached from any warehouse")
	for id in s.events:
		if not events.has(id):
			errs.append("unknown event '%s'" % id)
	return errs


static func validate_event(e: Dictionary) -> Array:
	var errs := []
	var label := str(e.get("id", "?"))
	for key in ["id", "title", "text", "weight"]:
		if not e.has(key):
			errs.append("%s missing '%s'" % [label, key])
	var effects := []
	if e.has("choices"):
		if not (e.choices is Array and e.choices.size() == 2):
			errs.append("%s needs exactly 2 choices" % label)
		else:
			for c in e.choices:
				if str(c.get("label", "")).is_empty() or str(c.get("hint", "")).is_empty():
					errs.append("%s choice needs label and hint" % label)
				effects.append(c.get("effect", {}))
				for k in c.get("values", {}):
					if not VALUE_KEYS.has(k):
						errs.append("%s choice has unknown value '%s'" % [label, k])
	elif e.has("effect"):
		effects.append(e.effect)
	else:
		errs.append("%s needs an effect or choices" % label)
	for eff in effects:
		for k in eff:
			if not EFFECT_KEYS.has(k):
				errs.append("%s has unknown effect key '%s'" % [label, k])
	return errs
