# Corridor 12 — notes for Claude

- Humanitarian convoy logistics game (design in `README.md`). Owner: Karam, writes Arabic; the UI is Arabic RTL
  with the Cairo font (no star glyph: stars are drawn by `StarRow`).
- Godot 4.7, GDScript, landscape 1920×1080 (`sensor_landscape`), Android first. APK is built in CI
  (`.github/workflows/android.yml`); the "latest" release on `main` carries it.
- Rules live in `scripts/core/` and touch no nodes, so tests can replay them:
  - `road_graph.gd`: the map and the multi-criteria A* (`time·w.time + risk·w.risk + fuel·w.fuel`). With a departure
    time it counts waiting at checkpoints and avoids checkpoints that are closed on arrival.
  - `simulation.gd`: one scenario day by day (plan, `run_day()` report, `next_day()`), event effects, the impact
    metrics (lives, equity, on time, safety) and `summary()`. Seeded RNG: same seed and plan, same day.
  - `scenario_data.gd`: loads and validates `data/scenarios/*.json` and `data/events.json`.
- Content is data: scenarios in `data/scenarios/` (map is 1000×640 units, times in minutes since midnight),
  event cards in `data/events.json` (effect keys are listed in `ScenarioData.EFFECT_KEYS`). The tests validate
  every file and replay every scenario with the suggested plan.
- Screens (`scripts/ui/`): menu, game (map + planning panel + event card + report), end. Node names inside a screen
  must be unique (tests press buttons by name); clear containers with `remove_child` before rebuilding.
- Before pushing run: `godot --headless --path . --import` then
  `godot --headless --path . res://tests/test_runner.tscn` (must exit 0).
- App icon: `python3 tools/make_icon.py` (Pillow) writes `assets/icon/`.
