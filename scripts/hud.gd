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
var fade: ColorRect
var _msg_t := 0.0


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

        fade = ColorRect.new()
        fade.color = Color(0, 0, 0, 0)
        fade.set_anchors_preset(Control.PRESET_FULL_RECT)
        fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(fade)


func _process(dt: float) -> void:
        if _msg_t > 0.0:
                _msg_t -= dt
                if _msg_t <= 0.0:
                        msg_l.text = ""


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


func do_fade() -> void:
        var tw := create_tween()
        tw.tween_property(fade, "color:a", 1.0, 0.18)
        tw.tween_property(fade, "color:a", 0.0, 0.30)


func _fmt(t: float) -> String:
        var m := int(t) / 60
        var s := int(t) % 60
        var cs := int((t - floor(t)) * 100.0)
        return "%02d:%02d.%02d" % [m, s, cs]
