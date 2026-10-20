extends RefCounted
## Flat, high-contrast theme built in code. Focus is a thick yellow outline so keyboard
## position is always visible (WCAG 2.4.7 / 2.4.11).

const BG := Color("10141f")
const PANEL := Color("182032")
const PANEL_BORDER := Color("3a4766")
const BUTTON := Color("243049")
const BUTTON_HOVER := Color("30406a")
const BUTTON_PRESSED := Color("1b2438")
const TEXT := Color("eef1f7")
const TEXT_DIM := Color("b4bdd0")
const FOCUS := Color("ffd34d")
const ACCENT := Color("6ec6ff")
const GOOD := Color("7ee08a")
const BAD := Color("ff8a7a")


static func box(bg: Color, border: Color = PANEL_BORDER, width: int = 2, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(pad)
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("panel", "Panel", box(PANEL))
	for cls in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", cls, box(BUTTON, PANEL_BORDER, 2, 10))
		t.set_stylebox("hover", cls, box(BUTTON_HOVER, ACCENT, 2, 10))
		t.set_stylebox("pressed", cls, box(BUTTON_PRESSED, ACCENT, 2, 10))
		t.set_stylebox("disabled", cls, box(BUTTON_PRESSED, Color("2a3348"), 2, 10))
		var focus := box(Color(0, 0, 0, 0), FOCUS, 4, 10)
		focus.draw_center = false
		focus.expand_margin_left = 2
		focus.expand_margin_right = 2
		focus.expand_margin_top = 2
		focus.expand_margin_bottom = 2
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, FOCUS)
		t.set_color("font_disabled_color", cls, TEXT_DIM)
	t.set_stylebox("normal", "LineEdit", box(Color("0c111b"), PANEL_BORDER, 2, 8))
	var le_focus := box(Color(0, 0, 0, 0), FOCUS, 3, 8)
	le_focus.draw_center = false
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("background", "ProgressBar", box(Color("0c111b"), PANEL_BORDER, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, ACCENT, 0, 0))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(Color("0c111b"), FOCUS, 2, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t
