class_name UiKit
extends RefCounted
## Piezas de interfaz (copiadas del estilo de Sky Explorer). Los botones se pueden
## recorrer con teclado y mando (flechas / cruceta + Enter / A).

const PANEL_COLOR := Color(0.08, 0.1, 0.2, 0.9)
const BUTTON_COLOR := Color(0.2, 0.42, 0.85)
const BUTTON_ALT_COLOR := Color(0.24, 0.27, 0.38)


static func label(parent: Node, font_size: int, color := Color.WHITE, outline := 8) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", outline)
	if parent:
		parent.add_child(l)
	return l


## Panel centrado con un VBoxContainer dentro (accesible con panel.get_child(0)).
static func panel(parent: Node, padding := 32, spacing := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	var style := round_box(PANEL_COLOR, 18)
	style.set_content_margin_all(padding)
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", spacing)
	p.add_child(vb)
	return p


static func button(parent: Node, text: String, action: Callable, primary := true,
		min_size := Vector2(320, 68)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size = min_size
	var base := BUTTON_COLOR if primary else BUTTON_ALT_COLOR
	b.add_theme_stylebox_override("normal", round_box(base, 14))
	b.add_theme_stylebox_override("hover", round_box(base.lightened(0.15), 14))
	b.add_theme_stylebox_override("pressed", round_box(base.darkened(0.2), 14))
	var focus := round_box(Color(0, 0, 0, 0), 14)
	focus.draw_center = false
	focus.set_border_width_all(4)
	focus.border_color = Color("#fff3c4")
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", round_box(Color(0.18, 0.19, 0.24, 0.8), 14))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func round_box(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s


## Centra un Control en su viewport.
static func center(c: Control) -> void:
	c.reset_size()
	c.position = (c.get_viewport_rect().size - c.size) * 0.5
