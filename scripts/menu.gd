extends CanvasLayer
## Main menu (Arabic-first), overlays the world when it exists.

var main
var best_label: Label
var shadows_btn: Button


func setup(m: Node3D) -> void:
        main = m


func _ready() -> void:
        layer = 20
        _build()


func _build() -> void:
        var root := Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(root)

        var bg := ColorRect.new()
        bg.color = Color(0.07, 0.09, 0.14, 0.94)
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(bg)

        var band := ColorRect.new()
        band.color = Color(0.85, 0.62, 0.18, 0.9)
        band.anchor_left = 0.0
        band.anchor_right = 1.0
        band.anchor_top = 0.62
        band.anchor_bottom = 0.62
        band.offset_top = -3
        band.offset_bottom = 3
        root.add_child(band)

        var title := UIKit.make_label("أطلس دريفت", 108, Color(0.95, 0.78, 0.30), main.font_bold)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.anchor_left = 0.0
        title.anchor_right = 1.0
        title.anchor_top = 0.13
        title.anchor_bottom = 0.13
        root.add_child(title)

        var sub := UIKit.make_label("ATLAS DRIFT  •  سباق الجبال بالانزياح", 30, Color(0.8, 0.82, 0.88), main.font_regular)
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.anchor_left = 0.0
        sub.anchor_right = 1.0
        sub.anchor_top = 0.30
        sub.anchor_bottom = 0.30
        root.add_child(sub)

        best_label = UIKit.make_label("", 34, Color(0.65, 0.9, 0.65), main.font_bold)
        best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        best_label.anchor_left = 0.0
        best_label.anchor_right = 1.0
        best_label.anchor_top = 0.40
        best_label.anchor_bottom = 0.40
        root.add_child(best_label)

        var start := UIKit.make_button("ابدأ السباق", main.font_bold, 46)
        start.anchor_left = 0.5
        start.anchor_right = 0.5
        start.anchor_top = 0.70
        start.anchor_bottom = 0.70
        start.offset_left = -160
        start.offset_right = 160
        start.offset_top = -34
        start.offset_bottom = 44
        start.pressed.connect(func() -> void: main.start_race())
        root.add_child(start)

        shadows_btn = UIKit.make_button("الظلال: مفعّلة", main.font_regular, 26)
        shadows_btn.anchor_left = 0.5
        shadows_btn.anchor_right = 0.5
        shadows_btn.anchor_top = 0.82
        shadows_btn.anchor_bottom = 0.82
        shadows_btn.offset_left = -140
        shadows_btn.offset_right = 140
        shadows_btn.offset_top = -20
        shadows_btn.offset_bottom = 30
        shadows_btn.pressed.connect(_on_shadows)
        root.add_child(shadows_btn)

        if OS.get_name() != "Android":
                var quit := UIKit.make_button("خروج", main.font_regular, 26)
                quit.anchor_left = 0.5
                quit.anchor_right = 0.5
                quit.anchor_top = 0.91
                quit.anchor_bottom = 0.91
                quit.offset_left = -90
                quit.offset_right = 90
                quit.offset_top = -16
                quit.offset_bottom = 26
                quit.pressed.connect(func() -> void: main.quit_game())
                root.add_child(quit)

        var hint := UIKit.make_label("قيادة: أسهم/WASD • بنزين W • فرامل S • انزياح مسافة • إعادة R", 22, Color(0.55, 0.58, 0.66), main.font_regular)
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hint.anchor_left = 0.0
        hint.anchor_right = 1.0
        hint.anchor_top = 0.975
        hint.anchor_bottom = 0.975
        root.add_child(hint)

        refresh_stats()


func refresh_stats() -> void:
        var best: float = main.load_best()
        if best > 0.0:
                best_label.text = "أفضل لفة: %s" % _fmt(best)
        else:
                best_label.text = "لم تُسجَّل لفة بعد — سجّل أول زمن!"


func _on_shadows() -> void:
        var on: bool = main.toggle_shadows()
        shadows_btn.text = "الظلال: مفعّلة" if on else "الظلال: معطلة"


func _fmt(t: float) -> String:
        var m := int(t) / 60
        var s := int(t) % 60
        var cs := int((t - floor(t)) * 100.0)
        return "%02d:%02d.%02d" % [m, s, cs]
