extends CanvasLayer
## Procedural multi-touch controls (GAS / BRAKE / DRIFT / steer L-R).

const BASE_W := 1280.0
const BASE_H := 720.0

var _btns := {}


func _ready() -> void:
	layer = 18
	if not DisplayServer.is_touchscreen_available():
		visible = false
		return
	_add_btn("left", Vector2(120, 590), 66, 0.0)
	_add_btn("right", Vector2(300, 590), 66, PI)
	_add_btn("brake", Vector2(960, 610), 60, -PI / 2.0)
	_add_btn("gas", Vector2(1130, 560), 82, -PI / 2.0)
	_add_btn("hand", Vector2(1040, 415), 50, 0.0)
	_labels()


func _add_btn(action: String, pos: Vector2, radius: int, arrow_angle: float) -> void:
	var d := radius * 2
	var idle_col := Color(0.16, 0.19, 0.27, 0.62)
	var ring_col := Color(0.85, 0.68, 0.25, 0.85)
	var press_col := Color(0.95, 0.72, 0.20, 0.80)
	var b := TouchScreenButton.new()
	b.texture_normal = UIKit.circle_tex(d, idle_col, ring_col)
	b.texture_pressed = UIKit.circle_tex(d, press_col, Color(1, 0.95, 0.7, 0.95))
	b.action = action
	b.position = pos - Vector2(radius, radius)
	b.modulate = Color(1, 1, 1, 0.95)
	add_child(b)

	var arrow := TextureRect.new()
	var atex := UIKit.arrow_tex(d, Color(0.95, 0.92, 0.82, 0.85), arrow_angle)
	arrow.texture = atex
	arrow.size = Vector2(d, d)
	arrow.position = Vector2.ZERO
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(arrow)

	_btns[action] = b


func _labels() -> void:
	var pairs := {
		"brake": Vector2(960, 690),
		"gas": Vector2(1130, 660),
		"hand": Vector2(1040, 360),
	}
	var names := {"brake": "فرامل", "gas": "بنزين", "hand": "انزياح"}
	for a in pairs:
		var l := Label.new()
		l.text = names[a]
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8, 0.75))
		l.position = pairs[a] - Vector2(30, 0)
		l.size = Vector2(60, 26)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
