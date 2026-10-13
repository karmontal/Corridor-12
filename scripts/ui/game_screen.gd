extends Screen
## One scenario: the map, the planning panel, the morning event card, playback and the day report.

const PLAY_SPEED := 100.0  # simulated minutes per second
const FOOD_STEP := 20
const MED_STEP := 10
const STANCE_NAMES := {"fast": "أسرع", "balanced": "متوازن", "safe": "أأمن"}
const STATUS_TEXT := {
	Simulation.STATUS_DELIVERED: "وصلت",
	Simulation.STATUS_HELD: "أُعيدت من الحاجز (وصلت بعد الإغلاق)",
	Simulation.STATUS_CURFEW: "عادت: لن تصل قبل حظر التجول",
}

var sim: Simulation
var map: MapView
var from_id := ""
var to_id := ""
var stance := "balanced"
var food := 0
var med := 0
var playing := false
var report := {}
var overlay: Control

var _header: Label
var _event_line: Label
var _needs: VBoxContainer
var _route_line: Label
var _food_label: Label
var _med_label: Label
var _preview: Label
var _add: Button
var _convoys: VBoxContainer
var _start: Button
var _stance_buttons := {}
var _end_clock := 0.0
var _alarms: Array = []  # incident times still to sound during playback


func build() -> void:
	sim = Simulation.new(args.scenario, ScenarioData.load_events())
	Sfx.music("music_plan")
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	var side_panel := UI.panel()
	side_panel.custom_minimum_size.x = 680
	row.add_child(side_panel)
	var side_col := VBoxContainer.new()
	side_col.add_theme_constant_override("separation", 12)
	side_panel.add_child(side_col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_col.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	scroll.add_child(side)
	map = MapView.new()
	map.name = "Map"
	map.sim = sim
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.node_tapped.connect(select_node)
	row.add_child(map)
	_build_side(side)
	side_col.add_child(_start)
	refresh()
	show_event()


func _build_side(side: VBoxContainer) -> void:
	var top := HBoxContainer.new()
	var back := UI.button("Menu", "القائمة", 26)
	back.custom_minimum_size = Vector2(150, 64)
	back.pressed.connect(func(): main.goto("menu"))
	top.add_child(back)
	var title := UI.label(sim.scenario.title, 36, UI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	side.add_child(top)
	_header = UI.label("", 26)
	side.add_child(_header)
	_event_line = UI.label("", 26, UI.ACCENT)
	side.add_child(_event_line)
	_needs = VBoxContainer.new()
	side.add_child(_needs)
	side.add_child(HSeparator.new())
	_route_line = UI.label("", 26)
	side.add_child(_route_line)
	var stances := HBoxContainer.new()
	var group := ButtonGroup.new()
	for key in ["fast", "balanced", "safe"]:
		var b := UI.button("Stance_" + key, STANCE_NAMES[key], 26)
		b.custom_minimum_size.y = 64
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == stance
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_stance.bind(key))
		_stance_buttons[key] = b
		stances.add_child(b)
	side.add_child(stances)
	_food_label = _stepper(side, "Food", func(d): set_cargo(food + d * FOOD_STEP, med))
	_med_label = _stepper(side, "Med", func(d): set_cargo(food, med + d * MED_STEP))
	_preview = UI.label("", 24, UI.MUTED)
	side.add_child(_preview)
	var actions := HBoxContainer.new()
	_add = UI.button("AddConvoy", "أضف القافلة", 28)
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.set_meta("sfx", "load")
	_add.pressed.connect(add_convoy)
	actions.add_child(_add)
	var suggest := UI.button("Suggest", "خطة مقترحة", 26)
	suggest.pressed.connect(suggest_plan)
	actions.add_child(suggest)
	side.add_child(actions)
	side.add_child(HSeparator.new())
	_convoys = VBoxContainer.new()
	side.add_child(_convoys)
	_start = UI.button("StartDay", "ابدأ اليوم", 32)
	_start.add_theme_stylebox_override("normal", UI.box(UI.ACCENT.darkened(0.35), 14))
	_start.add_theme_stylebox_override("hover", UI.box(UI.ACCENT.darkened(0.25), 14))
	_start.set_meta("sfx", "engine")
	_start.pressed.connect(func(): skip_playback() if playing else start_day())


func _stepper(parent: Control, key: String, on_step: Callable) -> Label:
	var row := HBoxContainer.new()
	var name_l := UI.label("غذاء" if key == "Food" else "دواء", 28)
	name_l.custom_minimum_size.x = 110
	row.add_child(name_l)
	var minus := UI.button(key + "Minus", "−", 34)
	minus.custom_minimum_size = Vector2(90, 64)
	minus.pressed.connect(on_step.bind(-1))
	row.add_child(minus)
	var value := UI.label("0", 30)
	value.custom_minimum_size.x = 120
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := UI.button(key + "Plus", "+", 34)
	plus.custom_minimum_size = Vector2(90, 64)
	plus.pressed.connect(on_step.bind(1))
	row.add_child(plus)
	parent.add_child(row)
	return value


# --- Planning -------------------------------------------------------------------------------

func select_node(id: String) -> void:
	if playing or overlay != null:
		return
	Sfx.play("tap", -4.0)
	match sim.graph.nodes[id].type:
		"warehouse":
			from_id = id
			_autofill()
		"district":
			to_id = id
			if from_id == "":
				from_id = sim.warehouses()[0]
			_autofill()
		"checkpoint":
			var w := sim.checkpoint_window(id)
			_event_line.text = "%s: يفتح %s ويغلق %s" % [sim.name_of(id), UI.clock(w.x), UI.clock(w.y)]
	refresh()


func set_stance(key: String) -> void:
	stance = key
	refresh()


func set_cargo(f: int, m: int) -> void:
	var st: Dictionary = sim.stock.get(from_id, {"food": 0, "med": 0})
	food = clampi(f, 0, st.food)
	med = clampi(m, 0, st.med)
	refresh()


## Loads what the chosen district still needs, within stock and free truck space.
func _autofill() -> void:
	if from_id == "" or to_id == "":
		return
	var st: Dictionary = sim.stock[from_id]
	var nd: Dictionary = sim.need[to_id]
	var f: int = mini(nd.food, st.food)
	var m: int = mini(nd.med, st.med)
	var cap := sim.free_trucks() * sim.truck_capacity()
	if f + m > cap:
		m = mini(m, cap)
		f = cap - m
	food = maxi(0, f)
	med = maxi(0, m)


func add_convoy() -> void:
	var r := sim.add_convoy(from_id, to_id, stance, food, med)
	if r.ok:
		to_id = ""
		food = 0
		med = 0
	refresh()


func remove_convoy(id: int) -> void:
	sim.remove_convoy(id)
	refresh()


func suggest_plan() -> void:
	if playing:
		return
	for c in sim.plan.duplicate():
		sim.remove_convoy(c.id)
	sim.auto_plan(stance)
	refresh()


func refresh() -> void:
	_header.text = "اليوم %d من %d · وقود %d · شاحنات %d/%d (كل شاحنة %d)" % [
		sim.day, sim.days_total(), int(sim.free_fuel()), sim.free_trucks(), sim.trucks, sim.truck_capacity()]
	if not sim.today_event.is_empty():
		_event_line.text = "حدث اليوم: " + sim.today_event.title + (" (%s)" % sim.event_target if sim.event_target != "" else "")
	for c in _needs.get_children():
		_needs.remove_child(c)
		c.queue_free()
	if sim.urgent != "":
		_needs.add_child(UI.label("عاجل: كل ما يصل %s اليوم يُحسب مضاعفاً" % sim.name_of(sim.urgent), 26, UI.BAD))
	_event_line.visible = _event_line.text != ""
	_route_line.text = "من: %s   إلى: %s" % [
		sim.name_of(from_id) if from_id != "" else "اضغط مستودعاً",
		sim.name_of(to_id) if to_id != "" else "اضغط حياً"]
	for key in _stance_buttons:
		_stance_buttons[key].button_pressed = key == stance
	_food_label.text = str(food)
	_med_label.text = str(med)
	var r := sim.preview(from_id, to_id, stance, food, med)
	map.route = r.path
	map.selected = [from_id, to_id]
	if r.path.is_empty():
		_preview.text = r.reason
	else:
		var when := UI.clock(r.arrival)
		var lines := ["الوصول %s · مدة الطريق %d د · خطر حادث %s" % [when, int(r.time), UI.pct(r.risk * 100.0)]]
		if r.status == Simulation.STATUS_HELD:
			lines.append("تحذير: ستصل إلى الحاجز بعد إغلاقه")
		elif r.status == Simulation.STATUS_CURFEW:
			lines.append("تحذير: لن تصل قبل حظر التجول")
		elif to_id != "" and r.arrival > sim.deadline(to_id):
			lines.append("ستصل متأخرة (بعد %s)" % UI.clock(sim.deadline(to_id)))
		if r.spoils:
			lines.append("تحذير: الدواء سيتلف على هذا الطريق")
		if r.ok:
			lines.append("شاحنات %d · وقود %d" % [r.trucks, roundi(r.fuel)])
		else:
			lines.append(r.reason)
		_preview.text = "\n".join(lines)
	_add.disabled = not r.ok or playing
	for c in _convoys.get_children():
		_convoys.remove_child(c)
		c.queue_free()
	for c in sim.plan:
		var item := HBoxContainer.new()
		var text := UI.label("%d. %s ← %s · غذاء %d · دواء %d · %s" % [
			c.id, sim.name_of(c.from), sim.name_of(c.to), c.food, c.med, STANCE_NAMES[c.stance]], 24)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_child(text)
		var rm := UI.button("Remove_%d" % c.id, "حذف", 24)
		rm.custom_minimum_size = Vector2(100, 60)
		rm.disabled = playing
		rm.pressed.connect(remove_convoy.bind(c.id))
		item.add_child(rm)
		_convoys.add_child(item)
	if sim.plan.is_empty():
		_convoys.add_child(UI.label("لا قوافل بعد", 24, UI.MUTED))
	_start.text = "تخطَّ إلى نهاية اليوم" if playing else "ابدأ اليوم"
	_start.disabled = sim.choice_pending
	map.queue_redraw()


# --- Morning event --------------------------------------------------------------------------

func show_event() -> void:
	var e := sim.today_event
	if e.is_empty():
		return
	var col := _open_overlay("EventCard")
	Sfx.play("radio" if e.has("choices") else "card")
	var banner := Art.banner("event.jpg", 220)
	if banner != null:
		col.add_child(banner)
	col.add_child(UI.label("حدث اليوم %d" % sim.day, 26, UI.MUTED))
	col.add_child(UI.label(e.title, 44, UI.ACCENT))
	var text: String = e.text
	if sim.event_target != "" and not e.has("choices"):
		text += "\nالحي: " + sim.event_target
	col.add_child(UI.label(text, 30))
	if e.has("choices"):
		for i in e.choices.size():
			var c: Dictionary = e.choices[i]
			var b := UI.button("Choice%d" % i, c.label, 30)
			b.pressed.connect(choose.bind(i))
			col.add_child(b)
			col.add_child(UI.label(c.hint, 24, UI.MUTED))
	else:
		var ok := UI.button("EventOk", "فهمت", 30)
		ok.pressed.connect(close_overlay)
		col.add_child(ok)


func choose(index: int) -> void:
	sim.choose(index)
	close_overlay()


# --- Running the day ------------------------------------------------------------------------

func start_day(animate: bool = true) -> void:
	if playing or sim.choice_pending or overlay != null:
		return
	report = sim.run_day()
	map.route = []
	map.tracks = report.convoys
	if not animate or report.convoys.is_empty():
		_finish_playback()
		return
	playing = true
	map.clock = Simulation.DAY_START
	_end_clock = Simulation.DAY_START + 60.0
	_alarms.clear()
	for c in report.convoys:
		_end_clock = maxf(_end_clock, c.points[-1].t + 30.0)
		for p in c.points:
			if c.incident_nodes.has(p.node):
				_alarms.append(p.t)
	_alarms.sort()
	refresh()


func _process(delta: float) -> void:
	if not playing:
		return
	map.clock += delta * PLAY_SPEED
	while not _alarms.is_empty() and map.clock >= _alarms[0]:
		_alarms.pop_front()
		Sfx.play("alarm", -3.0)
	_header.text = "اليوم %d · الساعة %s" % [sim.day, UI.clock(map.clock)]
	map.queue_redraw()
	if map.clock >= _end_clock:
		_finish_playback()


func skip_playback() -> void:
	if playing:
		_finish_playback()


func _finish_playback() -> void:
	playing = false
	map.clock = -1.0
	map.tracks = []
	refresh()
	_show_report()


func _show_report() -> void:
	var col := _open_overlay("Report")
	Sfx.play("success" if report.incidents == 0 and report.lives >= 60.0 else "card")
	col.add_child(UI.label("تقرير اليوم %d" % report.day, 44, UI.ACCENT))
	col.add_child(UI.label("وصل الدعم إلى %d شخص من %d يحتاجونه" % [report.people_reached, report.people_needed], 30))
	col.add_child(UI.impact_board(report))
	var facts := ["حوادث: %d" % report.incidents, "وقود مستخدم: %d" % roundi(report.fuel_used)]
	if report.spoiled > 0:
		facts.append("دواء تلف: %d" % report.spoiled)
	col.add_child(UI.label(" · ".join(facts), 26, UI.MUTED))
	for c in report.convoys:
		var line := "%d. %s: %s" % [c.id, sim.name_of(c.to), STATUS_TEXT[c.status]]
		if c.status == Simulation.STATUS_DELIVERED:
			line += " %s%s" % [UI.clock(c.arrival), "" if c.on_time else " (متأخرة)"]
		if c.incidents > 0:
			line += " · حادث، خسارة %d" % c.lost
		if c.spoiled > 0:
			line += " · تلف الدواء"
		col.add_child(UI.label(line, 24, UI.TEXT if c.status == Simulation.STATUS_DELIVERED else UI.BAD))
	if not report.critical.is_empty():
		var names := []
		for d in report.critical:
			names.append(sim.name_of(d))
		col.add_child(UI.label("أحياء في وضع حرج: " + "، ".join(names), 26, UI.BAD))
	var next := UI.button("NextDay", "النتيجة النهائية" if sim.is_over() else "اليوم التالي", 30)
	next.pressed.connect(next_day)
	col.add_child(next)


func next_day() -> void:
	close_overlay()
	if sim.is_over():
		main.goto("end", {"scenario": sim.scenario, "summary": sim.summary(), "history": sim.history})
		return
	sim.next_day()
	from_id = ""
	to_id = ""
	food = 0
	med = 0
	_event_line.text = ""
	refresh()
	show_event()


# --- Overlay ----------------------------------------------------------------------------------

func _open_overlay(node_name: String) -> VBoxContainer:
	close_overlay()
	var dim := ColorRect.new()
	dim.name = node_name
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	overlay = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.panel()
	card.custom_minimum_size.x = 1000
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	return col


func close_overlay() -> void:
	if overlay != null:
		remove_child(overlay)
		overlay.queue_free()
		overlay = null
	refresh()
