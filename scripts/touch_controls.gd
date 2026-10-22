extends CanvasLayer
## Multi-touch controls, anchored to the real viewport corners so
## the layout holds on any aspect ratio (16:9 up to 21:9+ phones).
##
## Layout (universal driving ergonomics, independent of UI RTL):
##   bottom-left  : steering  ◀ ▶   side by side
##   bottom-right : gas ▲ (corner), brake ▼ (left of gas), handbrake ↗ above
##                  gas, reverse ◄▼ above the brake (v0.6.0)
##
## v0.7.0 ("الغي التوليد البرمجي وقت التشغيل"): every texture here is a BAKED
## PNG file (tools/bake_ui.gd → res://assets/ui/*.png) — the old per-pixel
## GDScript loops (6 x 256x256 set_pixel) are gone. The arrows are pre-rotated
## in the files themselves: ◀ left, ▶ right, ▲ up (gas), ▼ down (brake +
## reverse), ↗ up-right (handbrake).

const TEX_D := 256   # baked PNG size (assets/ui/*.png), scaled per button

var _btns := {}
var _name_labels := {}
var _touch_ok := false


func _ready() -> void:
        layer = 18
        _touch_ok = DisplayServer.is_touchscreen_available()
        if not _touch_ok:
                visible = false
                return
        # v0.7.0: file loads only — no runtime texture generation.
        var idle: Texture2D = load("res://assets/ui/btn_idle.png")
        var pressed: Texture2D = load("res://assets/ui/btn_pressed.png")

        _add_btn("left", load("res://assets/ui/arrow_left.png"), idle, pressed, "")
        _add_btn("right", load("res://assets/ui/arrow_right.png"), idle, pressed, "")
        _add_btn("brake", load("res://assets/ui/arrow_down.png"), idle, pressed, "فرامل")
        _add_btn("gas", load("res://assets/ui/arrow_up.png"), idle, pressed, "بنزين")
        _add_btn("hand", load("res://assets/ui/arrow_up_right.png"), idle, pressed, "انزياح")
        _add_btn("reverse", load("res://assets/ui/arrow_down.png"), idle, pressed, "رجوع")

        _layout()
        get_viewport().size_changed.connect(_layout)
        # Hidden until begin_race() flips set_race_mode(true) — before the
        # first race the world may exist for the settings panel only.
        visible = false


## Race HUD state: shown on touchscreens while a race is running, hidden on
## the menu / after leaving the race. On non-touch devices this stays hidden
## forever (keyboard only).
func set_race_mode(on: bool) -> void:
        visible = _touch_ok and on


func _add_btn(action: String, arrow_tex: Texture2D, idle: Texture2D, pressed: Texture2D, label_text: String) -> void:
        var b := TouchScreenButton.new()
        b.texture_normal = idle
        b.texture_pressed = pressed
        b.action = action
        b.modulate = Color(1, 1, 1, 0.95)
        b.position = Vector2(-TEX_D, -TEX_D)  # hidden until first layout
        add_child(b)

        var arrow := TextureRect.new()
        arrow.texture = arrow_tex
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
        var r_rev := int(56.0 * s)
        var h := vs.y

        # bottom-left: steering pair
        var l_c := Vector2(m + r_steer, h - m - r_steer)
        var r_c := Vector2(m + r_steer * 3 + gap, h - m - r_steer)
        # bottom-right: pedals - gas in the corner, brake beside it, handbrake
        # above the gas column, reverse above the brake column (v0.6.0)
        var g_c := Vector2(vs.x - m - r_gas, h - m - r_gas)
        var b_c := Vector2(g_c.x - r_gas - gap - r_brake, h - m - r_brake)
        var hd_c := Vector2(g_c.x - 4.0 * s, g_c.y - r_gas - gap - r_hand)
        var rv_c := Vector2(b_c.x, b_c.y - r_brake - gap - r_rev)

        _place("left", l_c, r_steer)
        _place("right", r_c, r_steer)
        _place("gas", g_c, r_gas)
        _place("brake", b_c, r_brake)
        _place("hand", hd_c, r_hand)
        _place("reverse", rv_c, r_rev)


func _place(action: String, center: Vector2, r: int) -> void:
        var b: TouchScreenButton = _btns.get(action)
        if b == null:
                return
        var k := (float(r) * 2.0) / float(TEX_D)
        b.scale = Vector2(k, k)
        b.position = center - Vector2(r, r)
