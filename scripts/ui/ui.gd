class_name UI
extends RefCounted
## Colors, the theme and small widget helpers shared by all screens.

const BG := Color("1b2129")
const PANEL := Color("27303b")
const PANEL_LIGHT := Color("33404e")
const GLASS := Color(0.153, 0.188, 0.231, 0.86)  # PANEL, see-through over pictures
const MAP_BG := Color("202832")
const TEXT := Color("eef1f4")
const MUTED := Color("9aa7b4")
const ACCENT := Color("f2a541")
const GOOD := Color("5cc38a")
const BAD := Color("e5625e")
const BLUE := Color("5aa9e6")
const FONT := preload("res://assets/fonts/Cairo.ttf")
const METRICS := [
	["lives", "إنقاذ الأرواح"],
	["equity", "العدالة"],
	["on_time", "السرعة"],
	["safety", "السلامة"],
]


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 30
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color: Color = {"normal": PANEL_LIGHT, "hover": PANEL_LIGHT.lightened(0.1), "pressed": ACCENT.darkened(0.25),
			"disabled": PANEL_LIGHT.darkened(0.3), "focus": PANEL_LIGHT}[state]
		var sb := box(color, 14)
		if state == "focus":
			sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.2))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 18))
	return t


static func box(color: Color, radius: int = 14, pad: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func label(text: String, size: int = 30, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(node_name: String, text: String, size: int = 30) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", size)
	return b


static func panel(color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, 18, 22))
	return p


static func clock(minutes: float) -> String:
	var m := int(minutes)
	return "%02d:%02d" % [(m / 60) % 24, m % 60]


static func pct(v: float) -> String:
	return "%d%%" % roundi(v)


## Green for safe roads, amber for risky ones, red from about 16%.
static func risk_color(p: float) -> Color:
	if p < 0.07:
		return GOOD.lerp(ACCENT, p / 0.07)
	return ACCENT.lerp(BAD, clampf((p - 0.07) / 0.09, 0.0, 1.0))


static func metric_color(v: float) -> Color:
	return BAD if v < 40.0 else ACCENT if v < 70.0 else GOOD


## The "impact board": one bar per value the player is trading off.
static func impact_board(values: Dictionary) -> VBoxContainer:
	var box_ := VBoxContainer.new()
	box_.name = "ImpactBoard"
	box_.add_theme_constant_override("separation", 6)
	for m in METRICS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_l := label(m[1], 28, MUTED)
		name_l.custom_minimum_size.x = 210
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.name = "Bar_" + m[0]
		bar.min_value = 0
		bar.max_value = 100
		bar.value = values.get(m[0], 0.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(320, 26)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", box(PANEL_LIGHT, 8, 0))
		bar.add_theme_stylebox_override("fill", box(metric_color(bar.value), 8, 0))
		row.add_child(bar)
		var v := label(pct(bar.value), 28)
		v.custom_minimum_size.x = 90
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(v)
		box_.add_child(row)
	return box_
