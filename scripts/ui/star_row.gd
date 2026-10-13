class_name StarRow
extends Control
## Earned stars drawn as polygons (the Cairo font has no star glyph).

var stars := 0
var total := 3
var star_size := 40.0


func _init(earned: int = 0, out_of: int = 3, px: float = 40.0) -> void:
	stars = earned
	total = out_of
	star_size = px
	custom_minimum_size = Vector2(total * px * 1.2, px)


func _draw() -> void:
	var r := star_size * 0.5
	for i in total:
		var c := Vector2(r + i * star_size * 1.2, r)
		var pts := PackedVector2Array()
		for k in 10:
			var rad := r if k % 2 == 0 else r * 0.45
			var a := -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
		draw_colored_polygon(pts, UI.ACCENT if i < stars else UI.PANEL_LIGHT)
