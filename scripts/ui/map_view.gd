class_name MapView
extends Control
## The road map: roads colored by risk, checkpoints with their hours, districts with their needs.
## Tap a node to select it; during playback convoys move along their tracks by `clock`.

signal node_tapped(id: String)

const MAP_SIZE := Vector2(1000, 640)
const MARGIN := 70.0
const HIT_RADIUS := 60.0

var sim: Simulation
var route: Array = []  # preview path
var selected := []  # highlighted node ids
var tracks: Array = []  # day report convoys during playback
var clock := -1.0  # minute of day during playback, -1 while planning


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


func _scale() -> float:
	return minf((size.x - 2.0 * MARGIN) / MAP_SIZE.x, (size.y - 2.0 * MARGIN) / MAP_SIZE.y)


func to_screen(p: Vector2) -> Vector2:
	var s := _scale()
	return (size - MAP_SIZE * s) / 2.0 + p * s


func node_at(screen_pos: Vector2) -> String:
	var best := ""
	var best_d := HIT_RADIUS
	for id in sim.graph.nodes:
		var d := to_screen(sim.graph.nodes[id].pos).distance_to(screen_pos)
		if d < best_d and sim.graph.nodes[id].type != "junction":
			best_d = d
			best = id
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := node_at(event.position)
		if id != "":
			node_tapped.emit(id)
			accept_event()


func _draw() -> void:
	draw_style_box(UI.box(UI.MAP_BG, 22), Rect2(Vector2.ZERO, size))
	if sim == null:
		return
	var g := sim.graph
	var font := get_theme_default_font()
	# Roads.
	for e in g.edges:
		var a := to_screen(g.nodes[e.a].pos)
		var b := to_screen(g.nodes[e.b].pos)
		if e.closed:
			draw_dashed_line(a, b, UI.MUTED.darkened(0.3), 6.0, 16.0)
			_text(font, (a + b) / 2.0 + Vector2(0, -12), "مغلق", 22, UI.BAD)
			continue
		draw_line(a, b, UI.risk_color(g.effective_risk(e)), 7.0, true)
		_text(font, (a + b) / 2.0 + Vector2(0, -12), "%d د" % int(e.time), 20, UI.MUTED)
	# Planned convoys and the route being built.
	if clock < 0.0:
		for c in sim.plan:
			_path(c.path, Color(UI.BLUE, 0.45), 12.0)
	_path(route, UI.TEXT, 5.0)
	# Nodes.
	for id in g.nodes:
		var n: Dictionary = g.nodes[id]
		var p := to_screen(n.pos)
		if selected.has(id):
			draw_circle(p, 38.0, UI.TEXT, false, 4.0, true)
		match n.type:
			"warehouse":
				draw_rect(Rect2(p - Vector2(24, 24), Vector2(48, 48)), UI.BLUE)
				var st: Dictionary = sim.stock[id]
				_text(font, p + Vector2(0, 58), n.name, 24, UI.TEXT)
				_text(font, p + Vector2(0, 88), "غذاء %d · دواء %d" % [st.food, st.med], 20, UI.MUTED)
			"checkpoint":
				var w := sim.checkpoint_window(id)
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -28), p + Vector2(28, 0), p + Vector2(0, 28), p + Vector2(-28, 0)]), UI.ACCENT)
				_text(font, p + Vector2(0, 58), n.name, 24, UI.TEXT)
				var hours := "مغلق اليوم" if w.x == w.y else "%s – %s" % [UI.clock(w.x), UI.clock(w.y)]
				_text(font, p + Vector2(0, 88), hours, 20, UI.ACCENT)
			"district":
				var nd: Dictionary = sim.need[id]
				var daily: Dictionary = n.demand
				var behind: bool = nd.food + nd.med > int(daily.get("food", 0)) + int(daily.get("med", 0))
				draw_circle(p, 26.0, UI.BAD if behind else UI.GOOD, true, -1.0, true)
				if id == sim.urgent:
					draw_circle(p, 32.0, UI.BAD, false, 4.0, true)
				_text(font, p + Vector2(0, 60), n.name, 24, UI.TEXT)
				_text(font, p + Vector2(0, 90), "غذاء %d · دواء %d" % [nd.food, nd.med], 20, UI.MUTED)
			_:
				draw_circle(p, 8.0, UI.MUTED, true, -1.0, true)
	# Convoys during playback.
	if clock >= 0.0:
		for t in tracks:
			_draw_convoy(t, font)


func _draw_convoy(t: Dictionary, font: Font) -> void:
	var pts: Array = t.points
	var pos := to_screen(sim.graph.nodes[pts[0].node].pos)
	for i in range(1, pts.size()):
		var a: Dictionary = pts[i - 1]
		var b: Dictionary = pts[i]
		if clock >= b.t:
			pos = to_screen(sim.graph.nodes[b.node].pos)
		elif clock > a.t:
			var k: float = (clock - a.t) / maxf(1.0, b.t - a.t)
			pos = to_screen(sim.graph.nodes[a.node].pos).lerp(to_screen(sim.graph.nodes[b.node].pos), k)
			break
		else:
			break
	var done: bool = clock >= pts[-1].t
	var color := UI.BLUE
	if done:
		color = UI.GOOD if t.status == Simulation.STATUS_DELIVERED else UI.BAD
	draw_circle(pos, 16.0, color, true, -1.0, true)
	draw_circle(pos, 16.0, UI.TEXT, false, 3.0, true)
	_text(font, pos + Vector2(0, 8), str(t.id), 20, UI.BG)
	for i in t.incident_nodes.size():
		var node: String = t.incident_nodes[i]
		for p in pts:
			if p.node == node and clock >= p.t:
				var at := to_screen(sim.graph.nodes[node].pos)
				draw_circle(at, 40.0, Color(UI.BAD, 0.8), false, 5.0, true)
				break


func _path(path: Array, color: Color, width: float) -> void:
	for i in range(1, path.size()):
		draw_line(to_screen(sim.graph.nodes[path[i - 1]].pos), to_screen(sim.graph.nodes[path[i]].pos), color, width, true)


func _text(font: Font, center: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(font, center - Vector2(200, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 400, font_size, color)
