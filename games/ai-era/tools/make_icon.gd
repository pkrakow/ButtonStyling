extends SceneTree
## Regenerates assets/app_icon_1024.png (opaque, for the iOS App Store icon) from icon.svg.
## Usage: godot --headless --path . -s res://tools/make_icon.gd
func _init():
	var img := Image.new()
	var err := img.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"), 8.0)
	img.convert(Image.FORMAT_RGB8)
	img.save_png("res://assets/app_icon_1024.png")
	print("icon ", err, " ", img.get_size())
	quit()
