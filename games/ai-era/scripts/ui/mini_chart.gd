extends Control
## Small single-series line chart with its own title and start/end values, so
## each chart is readable without a color legend.

var title := ""
var values: PackedFloat32Array = []
var fmt := "%.0f"
var line_color := Color("6ec6ff")


func setup(p_title: String, p_values: Array, p_fmt: String, p_color: Color) -> void:
	title = p_title
	values = PackedFloat32Array(p_values)
	fmt = p_fmt
	line_color = p_color
	custom_minimum_size = Vector2(150, 96)
	tooltip_text = "%s: %s → %s" % [title, fmt % values[0], fmt % values[-1]] if values.size() > 0 else title
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c111b"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("3a4766"), false, 1.0)
	draw_string(font, Vector2(8, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("eef1f7"))
	if values.size() < 2:
		return
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 0.001:
		hi = lo + 1.0
	var area := Rect2(8, 26, size.x - 16, size.y - 48)
	var pts := PackedVector2Array()
	for i in values.size():
		var x := area.position.x + area.size.x * i / (values.size() - 1)
		var y := area.end.y - area.size.y * (values[i] - lo) / (hi - lo)
		pts.append(Vector2(x, y).floor())
	draw_polyline(pts, line_color, 2.0)
	var label := "%s → %s" % [fmt % values[0], fmt % values[-1]]
	draw_string(font, Vector2(8, size.y - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b4bdd0"))
