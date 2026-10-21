extends CanvasLayer
## Procedural multi-touch controls, anchored to the real viewport corners so
## the layout holds on any aspect ratio (16:9 up to 21:9+ phones).
##
## Layout (universal driving ergonomics, independent of UI RTL):
##   bottom-left  : steering  ◀ ▶   side by side
##   bottom-right : gas ▲ (corner), brake ▼ (left of gas), handbrake ↗ above
##
## Arrow convention: arrow_tex() draws an UP-pointing triangle at angle 0 and
## Godot 2D rotates positive angles CLOCKWISE on screen, so:
##   ◀ = -PI/2   ▶ = +PI/2   ▲ = 0   ▼ = PI   ↗ = +PI/4
## (v0.1.0 shipped with swapped angles - steering showed up/down arrows and
## the pedals showed left arrows, which made the layout feel broken.)

const TEX_D := 256   # all textures generated once at this size, scaled per button

var _btns := {}
var _name_labels := {}


func _ready() -> void:
        layer = 18
        if not DisplayServer.is_touchscreen_available():
                visible = false
                return
        var idle_col := Color(0.16, 0.19, 0.27, 0.62)
        var ring_col := Color(0.85, 0.68, 0.25, 0.85)
        var press_col := Color(0.95, 0.72, 0.20, 0.80)
        var idle := UIKit.circle_tex(TEX_D, idle_col, ring_col)
        var pressed := UIKit.circle_tex(TEX_D, press_col, Color(1, 0.95, 0.7, 0.95))

        _add_btn("left", -PI / 2.0, idle, pressed, "")
        _add_btn("right", PI / 2.0, idle, pressed, "")
        _add_btn("brake", PI, idle, pressed, "فرامل")
        _add_btn("gas", 0.0, idle, pressed, "بنزين")
        _add_btn("hand", PI / 4.0, idle, pressed, "انزياح")

        _layout()
        get_viewport().size_changed.connect(_layout)


func _add_btn(action: String, arrow_angle: float, idle: Texture2D, pressed: Texture2D, label_text: String) -> void:
        var b := TouchScreenButton.new()
        b.texture_normal = idle
        b.texture_pressed = pressed
        b.action = action
        b.modulate = Color(1, 1, 1, 0.95)
        b.position = Vector2(-TEX_D, -TEX_D)  # hidden until first layout
        add_child(b)

        var arrow := TextureRect.new()
        arrow.texture = UIKit.arrow_tex(TEX_D, Color(0.95, 0.92, 0.82, 0.85), arrow_angle)
        arrow.stretch_mode = TextureRect.STRETCH_SCALE
        arrow.size = Vector2(TEX_D, TEX_D)
        arrow.position = Vector2.ZERO
        arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
        b.add_child(arrow)

        if label_text != "":
                var l := Label.new()
                l.text = label_text
                l.add_theme_font_size_override("font_size", 26)
                l.add_theme_color_override("font_color", Color(0.93, 0.9, 0.8, 0.9))
                l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                l.size = Vector2(TEX_D, 34)
                l.position = Vector2(0, TEX_D * 0.68)
                l.mouse_filter = Control.MOUSE_FILTER_IGNORE
                b.add_child(l)
                _name_labels[action] = l

        _btns[action] = b


## Anchor every button to the actual canvas size (stretch mode is
## canvas_items + expand, so this is the visible canvas, not the 1280x720
## design base).
func _layout() -> void:
        var vs := get_viewport().get_visible_rect().size
        if vs.x <= 0.0 or vs.y <= 0.0:
                return
        var s := clampf(vs.y / 720.0, 0.9, 1.5)   # UI scale follows canvas height
        var m := 26.0 * s                          # edge margin
        var gap := 16.0 * s

        var r_steer := int(72.0 * s)
        var r_gas := int(88.0 * s)
        var r_brake := int(70.0 * s)
        var r_hand := int(56.0 * s)
        var h := vs.y

        # bottom-left: steering pair
        var l_c := Vector2(m + r_steer, h - m - r_steer)
        var r_c := Vector2(m + r_steer * 3 + gap, h - m - r_steer)
        # bottom-right: pedals - gas in the corner, brake beside it, handbrake above
        var g_c := Vector2(vs.x - m - r_gas, h - m - r_gas)
        var b_c := Vector2(g_c.x - r_gas - gap - r_brake, h - m - r_brake)
        var hd_c := Vector2(g_c.x - 4.0 * s, g_c.y - r_gas - gap - r_hand)

        _place("left", l_c, r_steer)
        _place("right", r_c, r_steer)
        _place("gas", g_c, r_gas)
        _place("brake", b_c, r_brake)
        _place("hand", hd_c, r_hand)


func _place(action: String, center: Vector2, r: int) -> void:
        var b: TouchScreenButton = _btns.get(action)
        if b == null:
                return
        var k := (float(r) * 2.0) / float(TEX_D)
        b.scale = Vector2(k, k)
        b.position = center - Vector2(r, r)
