extends Screen
## Scenario result: stars, the average impact board, the player's decision style, day by day.

const STYLES := {
	"lives": ["إنقاذ أكبر عدد", "ركّزت على إيصال أكبر كمية من المساعدات إلى أكبر عدد من الناس، حتى لو على حساب التوازن بين الأحياء."],
	"fairness": ["العدالة أولاً", "حرصت أن ينال كل حي نصيبه، ولو وصلت المساعدات لعدد أقل في المجموع."],
	"safety": ["السلامة أولاً", "حميت السائقين والحمولة، ولو تأخرت القوافل أو قلّ عددها."],
	"speed": ["السرعة", "فضّلت الوصول المبكر وتحمّلت مخاطرة أعلى على الطرق."],
}


func build() -> void:
	var s: Dictionary = args.scenario
	var sum: Dictionary = args.summary
	var new_best := Progress.record(s.id, sum.stars)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UI.panel()
	card.custom_minimum_size.x = 1200
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	card.add_child(col)
	col.add_child(UI.label("انتهى سيناريو «%s»" % s.title, 44, UI.ACCENT))
	var stars := StarRow.new(sum.stars, 3, 56)
	stars.name = "Stars"
	col.add_child(stars)
	if new_best:
		col.add_child(UI.label("أفضل نتيجة لك في هذا السيناريو", 26, UI.GOOD))
	col.add_child(UI.label("وصل الدعم إلى %d شخص من أصل %d احتاجوه خلال %d أيام." % [sum.people, sum.needed, args.history.size()], 30))
	col.add_child(UI.impact_board(sum.avg))
	var style: Array = STYLES[sum.style]
	var style_l := UI.label("أسلوبك: " + style[0], 34, UI.ACCENT)
	style_l.name = "Style"
	col.add_child(style_l)
	col.add_child(UI.label(style[1], 28, UI.MUTED))
	for r in args.history:
		col.add_child(UI.label("اليوم %d: أرواح %s · عدالة %s · سرعة %s · سلامة %s" % [
			r.day, UI.pct(r.lives), UI.pct(r.equity), UI.pct(r.on_time), UI.pct(r.safety)], 24, UI.MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	var again := UI.button("Replay", "أعد السيناريو")
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func(): main.goto("game", {"scenario": s}))
	buttons.add_child(again)
	var menu := UI.button("Menu", "القائمة")
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func(): main.goto("menu"))
	buttons.add_child(menu)
	col.add_child(buttons)
