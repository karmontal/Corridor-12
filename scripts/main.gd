extends Control
## Root of the game: the Arabic theme, a background and one screen at a time.

const SCREENS := {
	"menu": preload("res://scripts/ui/menu_screen.gd"),
	"game": preload("res://scripts/ui/game_screen.gd"),
	"end": preload("res://scripts/ui/end_screen.gd"),
}

var screen: Screen


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	goto("menu")


func goto(screen_name: String, screen_args: Dictionary = {}) -> void:
	if screen != null:
		# Out of the tree first, so a screen opened again keeps its name.
		remove_child(screen)
		screen.queue_free()
	screen = SCREENS[screen_name].new()
	screen.name = screen_name
	screen.main = self
	screen.args = screen_args
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.build()
