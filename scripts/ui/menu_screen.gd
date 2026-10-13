extends Screen
## Title, the scenario cards and how to play.

const HOW_TO := """• اضغط مستودعاً (مربع أزرق) ثم حياً (دائرة) على الخريطة لتبني قافلة.
• اختر طريقة التوجيه: أسرع، متوازن، أو أأمن. لون الطريق يدل على خطره: أخضر آمن، أحمر خطِر.
• الحواجز (معيّن برتقالي) لها ساعات فتح. إذا وصلت القافلة بعد الإغلاق تُعاد بحمولتها.
• حدّد كمية الغذاء والدواء. كل شاحنة تحمل كمية محددة وتستهلك وقوداً.
• اضغط «ابدأ اليوم» وتابع القوافل. كل صباح قد تصلك بطاقة حدث أو قرار صعب.
• لوح الأثر يقيس أربعة أشياء: إنقاذ الأرواح، العدالة بين الأحياء، السرعة، والسلامة. لا يمكنك أن تكسبها كلها دائماً."""

var _overlay: Control


func build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	margin.add_child(col)
	var title := UI.label("الممر 12", 84, UI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UI.label("لوجستيات إنسانية تكتيكية: خطّط قوافل المساعدات بين الحواجز والمخاطر، وقرّر بين إنقاذ أكثر وسرعة وعدالة.", 30, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 30)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cards)
	for s in ScenarioData.load_all():
		cards.add_child(_card(s))
	var help := UI.button("HowTo", "كيف ألعب؟")
	help.custom_minimum_size.x = 360
	help.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	help.pressed.connect(show_help)
	col.add_child(help)


func _card(s: Dictionary) -> Control:
	var card := UI.panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	col.add_child(UI.label(s.title, 40, UI.TEXT))
	col.add_child(StarRow.new(Progress.stars_for(s.id), 3, 36))
	var brief := UI.label(s.brief, 26, UI.MUTED)
	brief.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(brief)
	col.add_child(UI.label("%d أيام · %d شاحنات" % [int(s.days), int(s.start.trucks)], 24, UI.MUTED))
	var play := UI.button("Play_" + s.id, "ابدأ")
	play.pressed.connect(func(): main.goto("game", {"scenario": s}))
	col.add_child(play)
	return card


func show_help() -> void:
	var dim := ColorRect.new()
	dim.name = "Help"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_overlay = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.panel()
	card.custom_minimum_size.x = 1200
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	card.add_child(col)
	col.add_child(UI.label("كيف ألعب؟", 44, UI.ACCENT))
	col.add_child(UI.label(HOW_TO, 28))
	var ok := UI.button("CloseHelp", "فهمت")
	ok.pressed.connect(func():
		remove_child(_overlay)
		_overlay.queue_free())
	col.add_child(ok)
