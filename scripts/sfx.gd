extends Node
## Autoload "Sfx": sound effects and music from assets/audio/ (Higgsfield, fetched by tools/fetch_assets.sh).
## Missing files are skipped silently. Every Button clicks on press; a button with the meta "sfx" plays that
## sound instead. The music and sound switches are kept in user://settings.cfg.

const SETTINGS := "user://settings.cfg"
const VOICES := 6
const MUSIC_DB := -9.0

var sounds_on := true
var music_on := true
var current_music := ""
## Headless runs (tests, CI) have no speakers, and their audio server never frees started sounds.
var silent := DisplayServer.get_name() == "headless"

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		sounds_on = cfg.get_value("audio", "sounds", true)
		music_on = cfg.get_value("audio", "music", true)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	get_tree().node_added.connect(_on_node_added)


func stream(key: String) -> AudioStream:
	if not _streams.has(key):
		var path := "res://assets/audio/%s.ogg" % key
		_streams[key] = load(path) if ResourceLoader.exists(path) else null
	return _streams[key]


func play(key: String, volume_db: float = 0.0) -> void:
	if not sounds_on or silent:
		return
	var s := stream(key)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = s
	p.volume_db = volume_db
	p.play()


## Loops a music track; the same track keeps playing across screens.
func music(key: String) -> void:
	if key == current_music and (_music.playing or not music_on):
		return
	current_music = key
	_music.stop()
	var s := stream(key)
	if s == null or not music_on or silent:
		return
	if s is AudioStreamOggVorbis:
		s.loop = true
	_music.stream = s
	_music.play()


func set_sounds(on: bool) -> void:
	sounds_on = on
	_save()


func set_music(on: bool) -> void:
	music_on = on
	_save()
	if on:
		var key := current_music
		current_music = ""
		music(key)
	else:
		_music.stop()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sounds", sounds_on)
	cfg.set_value("audio", "music", music_on)
	cfg.save(SETTINGS)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(func(): play(node.get_meta("sfx", "tap"), 0.0 if node.has_meta("sfx") else -4.0))


func _exit_tree() -> void:
	# Let go of playing and cached sounds and the pictures so nothing is left loaded at exit.
	for p in _players + [_music]:
		p.stop()
		p.stream = null
	_streams.clear()
	Art.clear_cache()
