class_name RoadGraph
extends RefCounted
## The road network: nodes (warehouse, checkpoint, junction, district) joined by two-way roads.
## find_route() is a multi-criteria A*: cost(edge) = w.time·time + w.risk·risk + w.fuel·fuel.

var nodes := {}  # id -> {id, type, name, pos: Vector2, ...}
var edges: Array[Dictionary] = []  # {a, b, time, risk, fuel, closed}
## Today's risk modifiers, set by the simulation from active events.
var risk_add := 0.0
var risk_mult := 1.0
## Checkpoint opening hours (id -> Vector2i minutes) and the wait at each, for time-aware routing.
var windows := {}
var checkpoint_delay := 0
var _adj := {}  # id -> Array of edge indices
var _min_time_per_unit := 0.0  # lowest minutes per map unit over all roads (keeps the heuristic admissible)


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_data(data)


func load_data(data: Dictionary) -> void:
	nodes.clear()
	edges.clear()
	_adj.clear()
	for n in data.nodes:
		var node: Dictionary = n.duplicate(true)
		node.pos = Vector2(n.pos[0], n.pos[1])
		nodes[n.id] = node
		_adj[n.id] = []
	for e in data.edges:
		_adj[e.a].append(edges.size())
		_adj[e.b].append(edges.size())
		edges.append({"a": e.a, "b": e.b, "time": float(e.time), "risk": float(e.risk), "fuel": float(e.fuel), "closed": false})
	_min_time_per_unit = INF
	for edge in edges:
		var d: float = nodes[edge.a].pos.distance_to(nodes[edge.b].pos)
		if d > 0.0:
			_min_time_per_unit = minf(_min_time_per_unit, edge.time / d)
	if _min_time_per_unit == INF:
		_min_time_per_unit = 0.0


func ids_of_type(type: String) -> Array:
	var out := []
	for id in nodes:
		if nodes[id].type == type:
			out.append(id)
	return out


func edge_between(a: String, b: String) -> int:
	for i in _adj.get(a, []):
		var e: Dictionary = edges[i]
		if (e.a == a and e.b == b) or (e.a == b and e.b == a):
			return i
	return -1


func edges_of(id: String) -> Array:
	return _adj.get(id, [])


func other_end(edge: Dictionary, id: String) -> String:
	return edge.b if edge.a == id else edge.a


func effective_risk(edge: Dictionary) -> float:
	return clampf((edge.risk + risk_add) * risk_mult, 0.0, 0.95)


func edge_cost(edge: Dictionary, w: Dictionary) -> float:
	return w.time * edge.time + w.risk * effective_risk(edge) + w.fuel * edge.fuel


## Cheapest open path from `from` to `to` as a list of node ids, or [] when there is none.
## With `depart` (minutes since midnight) the time cost includes waiting at checkpoints,
## and checkpoints that are closed on arrival block the way.
func find_route(from: String, to: String, w: Dictionary, depart: int = -1) -> Array:
	if not nodes.has(from) or not nodes.has(to):
		return []
	var goal: Vector2 = nodes[to].pos
	var g := {from: 0.0}
	var at := {from: float(depart)}
	var came := {}
	var open := {from: _h(from, goal, w)}
	var closed := {}
	while not open.is_empty():
		var cur := ""
		var best := INF
		for id in open:
			if open[id] < best:
				best = open[id]
				cur = id
		if cur == to:
			var path := [to]
			while came.has(path[0]):
				path.push_front(came[path[0]])
			return path
		open.erase(cur)
		closed[cur] = true
		for i in _adj[cur]:
			var e: Dictionary = edges[i]
			if e.closed:
				continue
			var nxt := other_end(e, cur)
			if closed.has(nxt):
				continue
			var step: float = e.time
			if depart >= 0:
				var t: float = at[cur] + e.time
				if windows.has(nxt):
					var win: Vector2i = windows[nxt]
					if t > win.y or win.x == win.y:
						continue
					t = maxf(t, win.x) + checkpoint_delay
				step = t - at[cur]
			var cost: float = g[cur] + edge_cost(e, w) + w.time * (step - e.time)
			if cost < g.get(nxt, INF):
				g[nxt] = cost
				at[nxt] = at[cur] + step
				came[nxt] = cur
				open[nxt] = cost + _h(nxt, goal, w)
	return []


func _h(id: String, goal: Vector2, w: Dictionary) -> float:
	return w.time * nodes[id].pos.distance_to(goal) * _min_time_per_unit


## Totals for a path: minutes on the road, fuel per truck, chance of at least one incident.
func route_stats(path: Array) -> Dictionary:
	var time := 0.0
	var fuel := 0.0
	var safe := 1.0
	var checkpoints := []
	for i in range(1, path.size()):
		var e: Dictionary = edges[edge_between(path[i - 1], path[i])]
		time += e.time
		fuel += e.fuel
		safe *= 1.0 - effective_risk(e)
		if nodes[path[i]].type == "checkpoint":
			checkpoints.append(path[i])
	return {"time": time, "fuel": fuel, "risk": 1.0 - safe, "checkpoints": checkpoints}


## True when every district can still be reached from some warehouse over open roads.
func all_districts_reachable() -> bool:
	var seen := {}
	var queue := ids_of_type("warehouse")
	for id in queue:
		seen[id] = true
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for i in _adj[cur]:
			var e: Dictionary = edges[i]
			if e.closed:
				continue
			var nxt := other_end(e, cur)
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	for id in ids_of_type("district"):
		if not seen.has(id):
			return false
	return true
