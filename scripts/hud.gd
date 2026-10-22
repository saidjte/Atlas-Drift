extends CanvasLayer
## Race HUD: speed, laps, drift popups, countdown, debug line.

var main
var speed_l: Label
var time_l: Label
var lap_l: Label
var msg_l: Label
var count_l: Label
var wrong_l: Label
var drift_l: Label
var debug_l: Label
var card_l: Label
var card_sub_l: Label
var card_box: PanelContainer
var fade: ColorRect
var pause_btn: Button
var _msg_t := 0.0
var _card_t := 0.0


func setup(m: Node3D) -> void:
        main = m


func _ready() -> void:
        layer = 15
        var root := Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(root)

        speed_l = UIKit.make_label("0", 84, Color(0.97, 0.95, 0.9), main.font_bold)
        speed_l.anchor_left = 1.0
        speed_l.anchor_right = 1.0
        speed_l.anchor_top = 1.0
        speed_l.anchor_bottom = 1.0
        speed_l.offset_left = -330
        speed_l.offset_right = -150
        speed_l.offset_top = -140
        speed_l.offset_bottom = -40
        speed_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        root.add_child(speed_l)

        var kmh := UIKit.make_label("كم/س", 30, Color(0.75, 0.78, 0.85), main.font_regular)
        kmh.anchor_left = 1.0
        kmh.anchor_right = 1.0
        kmh.anchor_top = 1.0
        kmh.anchor_bottom = 1.0
        kmh.offset_left = -140
        kmh.offset_right = -30
        kmh.offset_top = -105
        kmh.offset_bottom = -60
        root.add_child(kmh)

        time_l = UIKit.make_label("00:00.00", 52, Color(0.97, 0.95, 0.9), main.font_bold)
        time_l.anchor_left = 0.5
        time_l.anchor_right = 0.5
        time_l.anchor_top = 0.0
        time_l.anchor_bottom = 0.0
        time_l.offset_left = -140
        time_l.offset_right = 140
        time_l.offset_top = 14
        time_l.offset_bottom = 80
        time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        root.add_child(time_l)

        lap_l = UIKit.make_label("اللفة 0  •  أفضل --:--.--", 26, Color(0.8, 0.82, 0.88), main.font_regular)
        lap_l.anchor_left = 0.5
        lap_l.anchor_right = 0.5
        lap_l.anchor_top = 0.0
        lap_l.anchor_bottom = 0.0
        lap_l.offset_left = -240
        lap_l.offset_right = 240
        lap_l.offset_top = 84
        lap_l.offset_bottom = 118
        lap_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        root.add_child(lap_l)

        count_l = UIKit.make_label("", 150, Color(0.98, 0.82, 0.30), main.font_bold)
        count_l.set_anchors_preset(Control.PRESET_FULL_RECT)
        count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        count_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        root.add_child(count_l)

        msg_l = UIKit.make_label("", 44, Color(0.65, 0.95, 0.65), main.font_bold)
        msg_l.anchor_left = 0.5
        msg_l.anchor_right = 0.5
        msg_l.anchor_top = 0.30
        msg_l.anchor_bottom = 0.30
        msg_l.offset_left = -400
        msg_l.offset_right = 400
        msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        root.add_child(msg_l)

        drift_l = UIKit.make_label("", 58, Color(1.0, 0.62, 0.25), main.font_bold)
        drift_l.anchor_left = 0.5
        drift_l.anchor_right = 0.5
        drift_l.anchor_top = 0.42
        drift_l.anchor_bottom = 0.42
        drift_l.offset_left = -300
        drift_l.offset_right = 300
        drift_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        root.add_child(drift_l)

        wrong_l = UIKit.make_label("اتجاه خاطئ!", 54, Color(1.0, 0.35, 0.30), main.font_bold)
        wrong_l.anchor_left = 0.5
        wrong_l.anchor_right = 0.5
        wrong_l.anchor_top = 0.18
        wrong_l.anchor_bottom = 0.18
        wrong_l.offset_left = -250
        wrong_l.offset_right = 250
        wrong_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        wrong_l.visible = false
        root.add_child(wrong_l)

        debug_l = UIKit.make_label("", 17, Color(0.62, 0.88, 0.62), main.font_regular, false)
        debug_l.anchor_left = 0.0
        debug_l.anchor_right = 1.0
        debug_l.anchor_top = 1.0
        debug_l.anchor_bottom = 1.0
        debug_l.offset_left = 14
        debug_l.offset_top = -30
        debug_l.offset_right = -14
        debug_l.offset_bottom = -8
        debug_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        root.add_child(debug_l)

        # Pause button (top-right, v0.5.0): opens صفحة التوقف المؤقت. The
        # icon is two drawn bars — deliberately font-independent (a text
        # "II" broke on some Android fonts in the TurboRacing era).
        pause_btn = Button.new()
        pause_btn.anchor_left = 1.0
        pause_btn.anchor_right = 1.0
        pause_btn.offset_left = -100
        pause_btn.offset_right = -28
        pause_btn.offset_top = 16
        pause_btn.offset_bottom = 82
        var pb_sb := StyleBoxFlat.new()
        pb_sb.bg_color = Color(0.13, 0.16, 0.23, 0.82)
        pb_sb.set_corner_radius_all(14)
        pb_sb.border_width_bottom = 3
        pb_sb.border_color = Color(0.85, 0.62, 0.18)
        pause_btn.add_theme_stylebox_override("normal", pb_sb)
        var pb_sb2: StyleBoxFlat = pb_sb.duplicate()
        pb_sb2.bg_color = Color(0.30, 0.22, 0.10, 0.92)
        pause_btn.add_theme_stylebox_override("pressed", pb_sb2)
        var pb_sb3: StyleBoxFlat = pb_sb.duplicate()
        pb_sb3.bg_color = Color(0.18, 0.22, 0.31, 0.88)
        pause_btn.add_theme_stylebox_override("hover", pb_sb3)
        for bx in [0.0, 1.0]:
                var bar := ColorRect.new()
                bar.color = Color(0.96, 0.93, 0.86, 0.95)
                bar.anchor_left = 0.5
                bar.anchor_right = 0.5
                bar.anchor_top = 0.5
                bar.anchor_bottom = 0.5
                bar.offset_left = -8.0 + bx * 16.0
                bar.offset_right = 1.0 + bx * 16.0
                bar.offset_top = -16.0
                bar.offset_bottom = 16.0
                bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
                pause_btn.add_child(bar)
        pause_btn.pressed.connect(func() -> void: main.open_pause())
        root.add_child(pause_btn)

        fade = ColorRect.new()
        fade.color = Color(0, 0, 0, 0)
        fade.set_anchors_preset(Control.PRESET_FULL_RECT)
        fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(fade)

        # Lap-card popup (GodotCardManager bonus draw after each lap).
        card_box = PanelContainer.new()
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.08, 0.10, 0.15, 0.92)
        sb.corner_radius_top_left = 16
        sb.corner_radius_top_right = 16
        sb.corner_radius_bottom_left = 16
        sb.corner_radius_bottom_right = 16
        sb.border_width_top = 2
        sb.border_width_bottom = 2
        sb.border_width_left = 2
        sb.border_width_right = 2
        sb.content_margin_left = 26.0
        sb.content_margin_right = 26.0
        sb.content_margin_top = 14.0
        sb.content_margin_bottom = 14.0
        card_box.add_theme_stylebox_override("panel", sb)
        card_box.anchor_left = 0.5
        card_box.anchor_right = 0.5
        card_box.anchor_top = 0.62
        card_box.anchor_bottom = 0.62
        card_box.visible = false
        card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var vb := VBoxContainer.new()
        vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card_box.add_child(vb)
        card_l = UIKit.make_label("", 40, Color(0.97, 0.95, 0.9), main.font_bold)
        card_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        vb.add_child(card_l)
        card_sub_l = UIKit.make_label("", 26, Color(0.8, 0.82, 0.88), main.font_regular)
        card_sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        vb.add_child(card_sub_l)
        root.add_child(card_box)


func _process(dt: float) -> void:
        if _msg_t > 0.0:
                _msg_t -= dt
                if _msg_t <= 0.0:
                        msg_l.text = ""
        if _card_t > 0.0:
                _card_t -= dt
                if _card_t <= 0.0:
                        card_box.visible = false


func update_speed(kph: float) -> void:
        speed_l.text = str(int(kph))


func update_time(t: float, lap: int, best: float) -> void:
        time_l.text = _fmt(t)
        if best > 0.0:
                lap_l.text = "اللفة %d  •  أفضل %s" % [lap, _fmt(best)]
        else:
                lap_l.text = "اللفة %d  •  أفضل --:--.--" % lap


func set_countdown(txt: String) -> void:
        count_l.text = txt


func flash(txt: String, dur := 2.2) -> void:
        msg_l.text = txt
        _msg_t = dur


func show_drift(pts: int) -> void:
        drift_l.text = "انزياح +%d" % pts


func clear_drift() -> void:
        drift_l.text = ""


func set_wrong_way(on: bool) -> void:
        wrong_l.visible = on


func set_debug(txt: String) -> void:
        debug_l.text = txt


func clear_card() -> void:
        _card_t = 0.0
        card_box.visible = false


func do_fade() -> void:
        var tw := create_tween()
        tw.tween_property(fade, "color:a", 1.0, 0.18)
        tw.tween_property(fade, "color:a", 0.0, 0.30)


## Lap-card popup: title line (value + suit + points), subtitle (modifier),
## colored border matching the suit.
func show_card(title: String, subtitle: String, col: Color) -> void:
        card_l.text = title
        card_sub_l.text = subtitle
        card_l.add_theme_color_override("font_color", col)
        var sb: StyleBoxFlat = card_box.get_theme_stylebox("panel").duplicate()
        sb.border_color = col
        card_box.add_theme_stylebox_override("panel", sb)
        card_box.visible = true
        _card_t = 3.2
        card_box.reset_size()
        await get_tree().process_frame
        card_box.position.x = -card_box.size.x * 0.5


func _fmt(t: float) -> String:
        var m := int(t) / 60
        var s := int(t) % 60
        var cs := int((t - floor(t)) * 100.0)
        return "%02d:%02d.%02d" % [m, s, cs]
