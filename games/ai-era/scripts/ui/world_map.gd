extends Control
## Pixel world map. Each land cell shows the selected overlay with BOTH brightness and
## dither density (more lit sub-pixels = higher), and each region carries a text label
## with its value and trend, so the map never relies on color alone.
## Sprites: datacenters (compute), city lights (prosperity), "!" markers (unrest).

const D := preload("res://scripts/sim/sim_data.gd")

const GRID_W := 96
const GRID_H := 46
const OCEAN := Color("0b1e3a")
const OCEAN_WAVE := Color("1d3d66")
const BORDER := Color("0a0f18")
## Overlay ramps: low -> high.
const RAMPS := {
	"prosperity": [Color("3b2f1e"), Color("e8c547")],
	"jobs": [Color("2d1f3d"), Color("7ee08a")],
	"unrest": [Color("1f2d2a"), Color("ff6b4a")],
	"compute": [Color("1a2238"), Color("6ec6ff")],
	"adoption": [Color("2a2238"), Color("d58cff")],
}
const OVERLAY_NAMES := {"prosperity": "Prosperity", "jobs": "Jobs", "unrest": "Unrest", "compute": "Compute", "adoption": "AI adoption"}
const BAYER := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1)]

var overlay := "prosperity"
var reduced_motion := false
var cells: PackedInt32Array
var region_cells: Array = [] # per region: Array[Vector2i] in a fixed shuffled order
var target: Array = [] # per region: Dictionary of stats
var shown: Array = [] # per region: smoothed display values
var previous: Array = []
var _time := 0.0
var _pulses: Dictionary = {} # region index -> seconds left
var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_cells()


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10000) / 10000.0


func _build_cells() -> void:
	cells = PackedInt32Array()
	cells.resize(GRID_W * GRID_H)
	cells.fill(-1)
	region_cells = []
	for ri in D.REGIONS.size():
		region_cells.append([])
	for y in GRID_H:
		for x in GRID_W:
			var n := _hash(x, y) * 0.5 - 0.25
			for ri in D.REGIONS.size():
				var hit := false
				for s in D.REGIONS[ri].shapes:
					var dx: float = float(x - s[0]) / s[2]
					var dy: float = float(y - s[1]) / s[3]
					if dx * dx + dy * dy <= 1.0 + n:
						hit = true
						break
				if hit:
					cells[y * GRID_W + x] = ri
					region_cells[ri].append(Vector2i(x, y))
					break
	for ri in region_cells.size():
		region_cells[ri].sort_custom(func(a, b): return _hash(a.x + 7, a.y + 3) < _hash(b.x + 7, b.y + 3))


func set_state(regions: Array) -> void:
	previous = target.duplicate(true) if not target.is_empty() else regions.duplicate(true)
	target = regions.duplicate(true)
	if shown.is_empty():
		shown = regions.duplicate(true)


func pulse(region_id: String) -> void:
	for i in target.size():
		if target[i].id == region_id:
			_pulses[i] = 2.0


func _process(delta: float) -> void:
	_time += delta
	var k := 1.0 if reduced_motion else clampf(delta * 3.0, 0.0, 1.0)
	for i in shown.size():
		for s in D.REGION_STATS:
			shown[i][s] = lerpf(shown[i][s], target[i][s], k)
	for i in _pulses.keys():
		_pulses[i] -= delta
		if _pulses[i] <= 0.0:
			_pulses.erase(i)
	queue_redraw()


func cell_size() -> int:
	return maxi(2, int(floor(minf(size.x / GRID_W, size.y / GRID_H))))


func origin() -> Vector2:
	var c := cell_size()
	return ((size - Vector2(GRID_W * c, GRID_H * c)) / 2.0).floor()


func _draw() -> void:
	if shown.is_empty():
		return
	var c := cell_size()
	var o := origin()
	var half := maxi(1, c / 2)
	draw_rect(Rect2(o, Vector2(GRID_W * c, GRID_H * c)), OCEAN)
	if not reduced_motion:
		var shift := int(_time * 2.0)
		for y in range(1, GRID_H, 3):
			for x in range(0, GRID_W, 7):
				var xx := (x + shift + y * 3) % GRID_W
				if cells[y * GRID_W + xx] == -1:
					draw_rect(Rect2(o + Vector2(xx * c, y * c + half), Vector2(c, 1)), OCEAN_WAVE)
	var ramp: Array = RAMPS[overlay]
	for y in GRID_H:
		for x in GRID_W:
			var ri := cells[y * GRID_W + x]
			if ri < 0:
				continue
			var v: float = shown[ri][overlay] / 100.0
			var p := Vector2(o.x + x * c, o.y + y * c)
			var base: Color = ramp[0].lerp(ramp[1], v * 0.45)
			draw_rect(Rect2(p, Vector2(c, c)), base)
			var lit := clampi(int(round(v * 4.0)), 0, 4)
			var bright: Color = ramp[0].lerp(ramp[1], 0.55 + v * 0.45)
			for b in lit:
				draw_rect(Rect2(p + Vector2(BAYER[b]) * half, Vector2(half, half)), bright)
			if x + 1 < GRID_W and cells[y * GRID_W + x + 1] != ri:
				draw_rect(Rect2(p + Vector2(c - 1, 0), Vector2(1, c)), BORDER)
			if y + 1 < GRID_H and cells[(y + 1) * GRID_W + x] != ri:
				draw_rect(Rect2(p + Vector2(0, c - 1), Vector2(c, 1)), BORDER)
	for ri in shown.size():
		_draw_sprites(ri, c, o)
	for ri in shown.size():
		_draw_label(ri, c, o)


func _draw_sprites(ri: int, c: int, o: Vector2) -> void:
	var r: Dictionary = shown[ri]
	var spots: Array = region_cells[ri]
	var idx := 0
	var blink := reduced_motion or int(_time * 2.0 + ri) % 2 == 0
	var lights := int(round(r.prosperity / 9.0))
	for i in mini(lights, spots.size()):
		var p: Vector2 = o + Vector2(spots[idx]) * c
		draw_rect(Rect2(p + Vector2(c * 0.5, c * 0.25), Vector2(maxf(1, c / 4.0), maxf(1, c / 4.0))), Color("fff2b3"))
		idx += 1
	var dcs := int(round(r.compute / 12.0))
	for i in mini(dcs, maxi(0, spots.size() - idx)):
		var p: Vector2 = o + Vector2(spots[idx]) * c
		draw_rect(Rect2(p, Vector2(c, c)), Color("d9e2f2"))
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(c - 2, c - 2)), Color("4a5a7a"))
		if blink:
			draw_rect(Rect2(p + Vector2(c * 0.5, c * 0.5) - Vector2(1, 1), Vector2(2, 2)), Color("6ef0ff"))
		idx += 3
	var fires := maxi(0, int(round((r.unrest - 25.0) / 12.0)))
	for i in mini(fires, maxi(0, spots.size() - idx)):
		var p: Vector2 = o + Vector2(spots[idx]) * c
		if reduced_motion or int(_time * 3.0 + i) % 3 != 0:
			var w := maxf(2.0, c / 3.0)
			draw_rect(Rect2(p + Vector2(c * 0.5 - w / 2, -c * 0.4), Vector2(w, c * 0.9)), Color("ff4a2e"))
			draw_rect(Rect2(p + Vector2(c * 0.5 - w / 2, c * 0.7), Vector2(w, w)), Color("ff4a2e"))
		idx += 2
	if _pulses.has(ri):
		for cell in spots:
			if int(_time * 6.0) % 2 == 0 or reduced_motion:
				draw_rect(Rect2(o + Vector2(cell) * c, Vector2(c, c)), Color(1, 1, 1, 0.18))


func _draw_label(ri: int, c: int, o: Vector2) -> void:
	var meta: Dictionary = D.REGIONS[ri]
	var v: float = target[ri][overlay]
	var prev: float = previous[ri][overlay] if ri < previous.size() else v
	var arrow := ""
	if v - prev >= 0.5:
		arrow = " ▲"
	elif prev - v >= 0.5:
		arrow = " ▼"
	var text := "%s %d%s" % [meta.code, int(round(v)), arrow]
	var fs := 14 if c >= 7 else 11
	var tsize := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := o + Vector2(meta.label[0] * c, meta.label[1] * c)
	draw_rect(Rect2(p - Vector2(4, tsize.y - 2), tsize + Vector2(8, 4)), Color(0.04, 0.06, 0.1, 0.85))
	draw_rect(Rect2(p - Vector2(4, tsize.y - 2), tsize + Vector2(8, 4)), Color("eef1f7"), false, 1.0)
	draw_string(_font, p + Vector2(0, -1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("eef1f7"))


func _get_tooltip(at_position: Vector2) -> String:
	if target.is_empty():
		return ""
	var c := cell_size()
	var g := ((at_position - origin()) / c).floor()
	if g.x < 0 or g.y < 0 or g.x >= GRID_W or g.y >= GRID_H:
		return ""
	var ri := cells[int(g.y) * GRID_W + int(g.x)]
	if ri < 0:
		return ""
	var r: Dictionary = target[ri]
	return "%s\nPopulation %.0f M\nProsperity %d  Jobs %d  Unrest %d\nCompute %d  AI adoption %d" % [
		r.name, r.pop, r.prosperity, r.jobs, r.unrest, r.compute, r.adoption]
