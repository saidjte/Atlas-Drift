extends CanvasLayer
## شاشة الإيقاف المؤقت (v0.5.0) — the pause screen the game was missing.
##
## Frozen world, floating UI: this CanvasLayer runs with
## PROCESS_MODE_ALWAYS so its buttons and ESC shortcut keep working while
## get_tree().paused freezes the physics, the countdown, the HUD timers and
## the engine/skid audio (all PAUSABLE by default). Opened from the HUD
## pause button (touch + mouse) or ESC during a race / countdown.

var main
var info_l: Label
var resume_btn: Button
var restart_btn: Button
var menu_btn: Button
var _open := false


func setup(m: Node3D) -> void:
        main = m


func _ready() -> void:
        layer = 30
        process_mode = Node.PROCESS_MODE_ALWAYS
        visible = false
        _build()


func _build() -> void:
        var root := Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(root)

        var bg := ColorRect.new()
        bg.color = Color(0.05, 0.07, 0.11, 0.90)
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(bg)

        var band := ColorRect.new()
        band.color = Color(0.85, 0.62, 0.18, 0.9)
        band.anchor_left = 0.0
        band.anchor_right = 1.0
        band.anchor_top = 0.30
        band.anchor_bottom = 0.30
        band.offset_top = -3
        band.offset_bottom = 3
        root.add_child(band)

        var title := UIKit.make_label("إيقاف مؤقت", 96, Color(0.95, 0.78, 0.30), main.font_bold)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.anchor_left = 0.0
        title.anchor_right = 1.0
        title.anchor_top = 0.13
        title.anchor_bottom = 0.13
        root.add_child(title)

        info_l = UIKit.make_label("", 32, Color(0.8, 0.82, 0.88), main.font_bold)
        info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        info_l.anchor_left = 0.0
        info_l.anchor_right = 1.0
        info_l.anchor_top = 0.325
        info_l.anchor_bottom = 0.325
        root.add_child(info_l)

        # v0.6.0: the three buttons are kept as members (the smoke test taps
        # them exactly like a finger does — pressed.emit()) and the tap
        # targets are slightly taller for easier thumb hits.
        resume_btn = UIKit.make_button("استئناف", main.font_bold, 46)
        resume_btn.anchor_left = 0.5
        resume_btn.anchor_right = 0.5
        resume_btn.anchor_top = 0.43
        resume_btn.anchor_bottom = 0.43
        resume_btn.offset_left = -160
        resume_btn.offset_right = 160
        resume_btn.offset_top = -38
        resume_btn.offset_bottom = 48
        resume_btn.pressed.connect(func() -> void: main.resume_game())
        root.add_child(resume_btn)

        restart_btn = UIKit.make_button("إعادة السباق", main.font_bold, 34)
        restart_btn.anchor_left = 0.5
        restart_btn.anchor_right = 0.5
        restart_btn.anchor_top = 0.585
        restart_btn.anchor_bottom = 0.585
        restart_btn.offset_left = -170
        restart_btn.offset_right = 170
        restart_btn.offset_top = -30
        restart_btn.offset_bottom = 40
        restart_btn.pressed.connect(func() -> void: main.restart_race())
        root.add_child(restart_btn)

        menu_btn = UIKit.make_button("القائمة الرئيسية", main.font_bold, 30)
        menu_btn.anchor_left = 0.5
        menu_btn.anchor_right = 0.5
        menu_btn.anchor_top = 0.72
        menu_btn.anchor_bottom = 0.72
        menu_btn.offset_left = -170
        menu_btn.offset_right = 170
        menu_btn.offset_top = -28
        menu_btn.offset_bottom = 38
        menu_btn.pressed.connect(func() -> void: main.exit_to_menu())
        root.add_child(menu_btn)

        if OS.get_name() != "Android":
                var hint := UIKit.make_label("ESC: استئناف", 22, Color(0.55, 0.58, 0.66), main.font_regular)
                hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                hint.anchor_left = 0.0
                hint.anchor_right = 1.0
                hint.anchor_top = 0.95
                hint.anchor_bottom = 0.95
                root.add_child(hint)


## Show the overlay and snapshot the race stats into the info line.
func open() -> void:
        _open = true
        visible = true
        var txt := ""
        if main.world != null:
                var best: float = main.world.best_lap
                var score: int = int(main.world.total_score)
                txt = "النقاط: %d" % score
                if best > 0.0:
                        txt += "   •   أفضل لفة: %s" % _fmt(best)
        info_l.text = txt


func close() -> void:
        _open = false
        visible = false


func is_open() -> bool:
        return _open


## ESC while paused resumes (this node is PROCESS_MODE_ALWAYS, so it keeps
## receiving input while the rest of the tree is frozen).
func _unhandled_input(event: InputEvent) -> void:
        if _open and event.is_action_pressed("ui_cancel"):
                main.resume_game()
                get_viewport().set_input_as_handled()


func _fmt(t: float) -> String:
        var m := int(t) / 60
        var s := int(t) % 60
        var cs := int((t - floor(t)) * 100.0)
        return "%02d:%02d.%02d" % [m, s, cs]
