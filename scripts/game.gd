extends Node3D
## World orchestration: track + car + HUD + laps + countdown + respawn.
## v0.3.0: lap-card bonus system powered by GodotCardManager (deck shuffle /
## draw / suit+value mapping), and all discrete SFX routed through the
## EventAudio addon (trigger -> bank lookup). Engine/skid loops stay on
## dedicated players with dynamic pitch (EventAudio targets one-shots).

const KILL_MARGIN := 30.0

# Card suit -> Arabic name + next-lap modifier passed to the car.
const SUIT_INFO := {
        0: {"name": "باستوني", "desc": "تماسك معزز", "col": Color(0.75, 0.78, 0.85),
            "grip": 1.35, "power": 1.0, "rear": 1.0},
        1: {"name": "سباتي", "desc": "دفع معزز", "col": Color(0.75, 0.78, 0.85),
            "grip": 1.0, "power": 1.3, "rear": 1.0},
        2: {"name": "ديناري", "desc": "نقاط انزياح مضاعفة", "col": Color(1.0, 0.55, 0.45),
            "grip": 1.0, "power": 1.0, "rear": 1.0, "x2": true},
        3: {"name": "كوبا", "desc": "مؤخرة انسيابية للانزياح", "col": Color(1.0, 0.55, 0.45),
            "grip": 1.0, "power": 1.0, "rear": 0.62},
}

var main
var track: TrackGen
var car: DriftCar
var hud: CanvasLayer
var touches: CanvasLayer
var cards                       # GodotCardManager deck (addons/godot_card_manager)

var state := "idle" # idle / countdown / race
var countdown_t := 0.0
var _count_shown := 9
var lap_time := 0.0
var lap_count := 0
var last_lap := -1.0
var best_lap := -1.0
var last_idx := 0
var prev_frac := 0.0
var quarters: Array[bool] = [true, false, false, false]
var respawn_idx := 0
var wrong_t := 0.0
var drift_pts := 0.0
var drift_show_t := 0.0
var total_score := 0.0
var drift_mult := 1.0
var _wrong_warned := false
var _dbg_t := 0.0
var _ea: Node


func setup(m: Node3D) -> void:
        main = m


func _ready() -> void:
        track = TrackGen.new()
        add_child(track)
        track.build(true)
        best_lap = main.load_best()

        car = DriftCar.new()
        add_child(car)
        _place_car_at_start()

        hud = load("res://scripts/hud.gd").new()
        hud.setup(main)
        add_child(hud)

        touches = load("res://scripts/touch_controls.gd").new()
        add_child(touches)

        # GodotCardManager: field 0 = deck (52 cards), field 1 = drawn hand.
        cards = load("res://addons/godot_card_manager/cards.gd").new()
        cards.addField(1)
        cards.shuffleField(0)

        _ea = get_node_or_null("/root/EventAudio")


func _sfx(trigger: String) -> void:
        if _ea != null:
                _ea.play_3d(trigger, car)


func _place_car_at_start() -> void:
        var sp: Dictionary = track.start_pose()
        car.set_pose(sp.pos, sp.yaw)
        last_idx = 3
        prev_frac = 3.0 / float(TrackGen.N)
        respawn_idx = 0


func begin_race() -> void:
        _reset_race()
        state = "countdown"
        countdown_t = 3.0
        _count_shown = 9


func pause() -> void:
        state = "idle"
        if car != null:
                car.controls_enabled = false


func unpause() -> void:
        pass


func _reset_race() -> void:
        _place_car_at_start()
        lap_time = 0.0
        lap_count = 0
        last_lap = -1.0
        quarters = [true, false, false, false]
        wrong_t = 0.0
        _wrong_warned = false
        drift_pts = 0.0
        total_score = 0.0
        drift_mult = 1.0
        car.apply_card_mods(1.0, 1.0, 1.0)
        car.controls_enabled = false
        hud.set_wrong_way(false)
        hud.clear_drift()
        hud.clear_card()






func toggle_shadows() -> bool:
        return track.toggle_shadows()


func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("restart") and state == "race":
                _respawn()


func _respawn() -> void:
        var p: Dictionary = track.pose_at(respawn_idx)
        car.respawn_to(p.pos, p.yaw)
        hud.do_fade()


func _process(dt: float) -> void:
        if state == "countdown":
                countdown_t -= dt
                var n := int(ceil(countdown_t))
                if n != _count_shown:
                        _count_shown = n
                        if n > 0:
                                hud.set_countdown(str(n))
                                _sfx("ui+countdown")
                if countdown_t <= 0.0:
                        hud.set_countdown("انطلق!")
                        _sfx("ui+go")
                        car.controls_enabled = true
                        state = "race"
                        lap_time = 0.0
                        var t := create_tween()
                        t.tween_interval(0.9)
                        t.tween_callback(func() -> void:
                                if state == "race":
                                        hud.set_countdown("")
                                        _count_shown = 9
                        )
        elif state == "race":
                _race_step(dt)


func _race_step(dt: float) -> void:
        lap_time += dt
        var idx := track.nearest_idx(car.global_position, last_idx)
        last_idx = idx
        var frac := float(idx) / float(TrackGen.N)

        # Quarter checkpoints.
        var q := int(frac * 4.0) % 4
        if not quarters[q]:
                quarters[q] = true
                respawn_idx = q * (TrackGen.N / 4)
                if q != 0:
                        hud.flash("نقطة تفتيش %d/3" % q, 1.4)
                        _sfx("race+checkpoint")

        # Lap crossing (with all quarters done).
        if prev_frac > 0.9 and frac < 0.1:
                if quarters[1] and quarters[2] and quarters[3] and lap_time > 8.0:
                        last_lap = lap_time
                        lap_count += 1
                        if best_lap < 0.0 or lap_time < best_lap:
                                best_lap = lap_time
                                main.save_best(best_lap)
                                hud.flash("أفضل لفة جديدة! %s" % _fmt(lap_time), 3.0)
                                _sfx("race+best")
                        else:
                                hud.flash("لفة %d — %s" % [lap_count, _fmt(lap_time)], 2.6)
                                _sfx("race+lap")
                        _draw_lap_card()
                lap_time = 0.0
                quarters = [true, false, false, false]
        prev_frac = frac

        # Wrong way detection.
        var tg: Vector3 = track.tans[idx]
        var along := car.linear_velocity.dot(tg)
        if along < -3.0:
                wrong_t += dt
        else:
                wrong_t = maxf(wrong_t - dt * 2.0, 0.0)
        var wrong_now := wrong_t > 1.5
        if wrong_now and not _wrong_warned:
                _wrong_warned = true
                _sfx("race+wrong")
        elif not wrong_now:
                _wrong_warned = false
        hud.set_wrong_way(wrong_now)

        # Drift scoring.
        var spd := car.speed_kph()
        if car.drift > 0.25 and spd > 32.0 and car.grounded:
                drift_pts += car.drift * spd * dt * 1.4 * drift_mult
                drift_show_t = 0.8
                hud.show_drift(int(drift_pts))
        elif drift_show_t > 0.0:
                drift_show_t -= dt
                if drift_show_t <= 0.0:
                        if drift_pts >= 25.0:
                                total_score += drift_pts
                                hud.flash("انزياح مكتمل +%d" % int(drift_pts), 1.6)
                        hud.clear_drift()
                        drift_pts = 0.0

        # Fell off the mountain.
        if car.global_position.y < track.BASE_Y - KILL_MARGIN:
                _respawn()

        # HUD.
        hud.update_speed(spd)
        hud.update_time(lap_time, lap_count, best_lap)
        _dbg_t -= dt
        if _dbg_t <= 0.0:
                _dbg_t = 0.25
                hud.set_debug("FPS %d | %dkph | μ %s | D %.2f | g %.1f | idx %d/%d | v%s | نقاط %d" % [
                        Engine.get_frames_per_second(), int(spd), car.surface_name,
                        car.drift, absf(car.lat_g), last_idx, TrackGen.N, GAME_VER(), int(total_score)
                ])


func _fmt(t: float) -> String:
        var m := int(t) / 60
        var s := int(t) % 60
        var cs := int((t - floor(t)) * 100.0)
        return "%02d:%02d.%02d" % [m, s, cs]


# ------------------------------------------------------------ lap cards

## Draw one card from the GodotCardManager deck after every completed lap.
## Card value -> bonus points added to the total score; card suit -> a real
## physics modifier for the next lap (grip / power / rear release / x2 drift).
func _draw_lap_card() -> void:
        if cards.getFieldSize(0) <= 0:
                # Deck exhausted: rebuild and reshuffle a fresh 52-card deck.
                cards = load("res://addons/godot_card_manager/cards.gd").new()
                cards.addField(1)
        var card: Dictionary = cards.drawCard(cards.getField(1))
        if card == null:
                return
        cards.setRevealed(card, true)
        var suit: int = cards.getSuit(card, false)
        var value: int = cards.getValue(card, false)
        var info: Dictionary = SUIT_INFO[suit]
        var pts := 0
        match value:
                1: pts = 500
                11: pts = 800
                12: pts = 900
                13: pts = 1000
                _: pts = value * 100
        total_score += pts
        drift_mult = 2.0 if info.has("x2") else 1.0
        car.apply_card_mods(info["grip"], info["power"], info["rear"])
        _sfx("race+card")
        hud.show_card("بطاقة اللفة: %s %s  +%d" % [_value_ar(value), info["name"]],
                "المكافأة تطبق على اللفة القادمة — %s" % info["desc"], info["col"])


func _value_ar(v: int) -> String:
        match v:
                1: return "آس"
                11: return "ولد"
                12: return "بنت"
                13: return "ملك"
                _: return str(v)


func GAME_VER() -> String:
        return main.GAME_VERSION
