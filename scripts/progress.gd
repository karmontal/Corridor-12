extends Node
## Best stars per scenario, saved as {"scenario_id": stars} in user://progress.json.

var path := "user://progress.json"
var best := {}


func _ready() -> void:
	load_file()


func load_file() -> void:
	best = {}
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			best = d


func stars_for(id: String) -> int:
	return int(best.get(id, 0))


## Keeps the result when it beats the best so far. Returns true on a new best.
func record(id: String, stars: int) -> bool:
	if stars <= stars_for(id):
		return false
	best[id] = stars
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(best))
	return true


func reset() -> void:
	best = {}
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
