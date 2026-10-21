extends Node3D
## Atlas Drift bootstrap: input map, fonts, EventAudio bank, menu <-> world.

const GAME_VERSION := "0.3.0"
const SAVE_PATH := "user://atlas.cfg"

var font_regular: FontFile
var font_bold: FontFile
var world
var menu


func _ready() -> void:
        _register_inputs()
        font_regular = load("res://assets/fonts/Tajawal-Regular.ttf")
        font_bold = load("res://assets/fonts/Tajawal-Bold.ttf")
        RenderingServer.set_default_clear_color(Color(0.09, 0.11, 0.16))
        _setup_event_audio()
        _make_menu()
        if "--smoke" in OS.get_cmdline_user_args():
                _smoke_test()


## Event Audio addon (addons/event_audio, autoload "EventAudio"): register a
## runtime-built EAEventBank. All discrete game SFX go through trigger tags;
## the tag hierarchy falls back right-to-left (e.g. "race+best" -> "race").
func _setup_event_audio() -> void:
        var ea := get_node_or_null("/root/EventAudio")
        if ea == null:
                return
        var bank := EAEventBank.new()
        _add_event(bank, "ui+countdown", AudioSynth.beep(392.0, 0.16, 0.55), -6.0)
        _add_event(bank, "ui+go", AudioSynth.beep(784.0, 0.5, 0.6), -4.0)
        _add_event(bank, "race+checkpoint", AudioSynth.beep(660.0, 0.2, 0.5), -8.0, 0.95, 1.1)
        _add_event(bank, "race+lap", AudioSynth.chime(), -6.0)
        _add_event(bank, "race+best", AudioSynth.fanfare(), -4.0)
        _add_event(bank, "race+card", AudioSynth.beep(880.0, 0.3, 0.35), -10.0, 0.98, 1.06)
        _add_event(bank, "car+impact", AudioSynth.thud(), -6.0, 0.8, 1.25)
        _add_event(bank, "race+wrong", AudioSynth.wrong_buzz(), -6.0)
        ea.register_event_bank(bank)


func _add_event(bank: EAEventBank, trigger: String, stream: AudioStream,
                vol_db: float, pmin := 1.0, pmax := 1.0) -> void:
        var ev := EAEvent.new()
        ev.trigger_tags = trigger
        ev.audio_streams = [stream]
        ev.probability_weights = [1.0]
        ev.playback_settings.volume_db = vol_db
        ev.playback_settings.min_pitch = pmin
        ev.playback_settings.max_pitch = pmax
        ev.playback_settings.stop_when_source_dies = true
        bank.entries.append(ev)


func _register_inputs() -> void:
        _bind("gas", [KEY_W, KEY_UP])
        _bind("brake", [KEY_S, KEY_DOWN])
        _bind("left", [KEY_A, KEY_LEFT])
        _bind("right", [KEY_D, KEY_RIGHT])
        _bind("hand", [KEY_SPACE])
        _bind("restart", [KEY_R])


func _bind(action: String, keys: Array) -> void:
        if not InputMap.has_action(action):
                InputMap.add_action(action)
        for k in keys:
                var ev := InputEventKey.new()
                ev.physical_keycode = k
                InputMap.action_add_event(action, ev)


func _make_menu() -> void:
        var menu_script := load("res://scripts/menu.gd")
        menu = menu_script.new()
        menu.setup(self)
        add_child(menu)


func start_race() -> void:
        if world == null:
                var game_script := load("res://scripts/game.gd")
                world = game_script.new()
                world.setup(self)
                add_child(world)
        else:
                world.unpause()
        menu.visible = false
        world.begin_race()


func exit_to_menu() -> void:
        if world != null:
                world.pause()
        menu.visible = true
        menu.refresh_stats()


func toggle_shadows() -> bool:
        if world != null:
                return world.toggle_shadows()
        return true


func save_best(lap: float) -> void:
        var cf := ConfigFile.new()
        cf.load(SAVE_PATH)
        cf.set_value("records", "best_lap", lap)
        cf.save(SAVE_PATH)


func load_best() -> float:
        var cf := ConfigFile.new()
        if cf.load(SAVE_PATH) == OK:
                return float(cf.get_value("records", "best_lap", -1.0))
        return -1.0


func quit_game() -> void:
        get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("ui_cancel"):
                if world != null and world.state == "race":
                        exit_to_menu()


## Headless end-to-end smoke drive: menu -> race -> gas -> steer (direction
## verified!) -> drift -> brake -> quit. v0.3.0 thresholds calibrated for the
## realistic VehicleBody3D physics (0-100 in ~7 s, ~140 km/h top).
func _smoke_test() -> void:
    await get_tree().create_timer(1.0).timeout
    start_race()
    await get_tree().create_timer(4.2).timeout
    var contacts := 0
    for w in world.car.wheels:
        if w != null and w.is_in_contact():
            contacts += 1
    var road_y: float = world.track.start_pose().pos.y
    var origin_h: float = world.car.global_position.y - road_y
    print("SMOKE wheels_in_contact=%d/4 origin_h=%.2f" % [contacts, origin_h])
    Input.action_press("gas")
    await get_tree().create_timer(4.5).timeout
    var s1: float = world.car.speed_kph()
    var i1: int = world.last_idx
    print("SMOKE drive: %d kph idx=%d rpm=%.2f surf=%s" % [int(s1), i1, world.car.rpm_norm, world.car.surface_name])
    # --- steering direction (the reported v0.2.0 bug), coasting so the
    # entry is deterministic (neutral throttle -> understeer slide) ---
    Input.action_release("gas")
    var p0: Vector3 = world.car.global_position
    var fwd0: Vector3 = world.car.global_transform.basis.z
    fwd0.y = 0.0
    fwd0 = fwd0.normalized()
    Input.action_press("right")
    await get_tree().create_timer(0.55).timeout
    var p1: Vector3 = world.car.global_position
    var right_vec: Vector3 = fwd0.cross(Vector3.UP)
    var lat_off: float = (p1 - p0).dot(right_vec)
    print("SMOKE steer_right: lateral_offset=%.2f m (positive = correct right turn)" % lat_off)
    var d1: float = world.car.drift
    print("SMOKE steer: drift=%.2f" % d1)
    Input.action_release("right")
    # --- handbrake drift: yank it while still fast; drift is read while the
    # handbrake is held (floor applies), before it decays on release ---
    Input.action_press("hand")
    await get_tree().create_timer(0.5).timeout
    var d2: float = world.car.drift
    Input.action_release("hand")
    print("SMOKE handbrake: drift=%.2f" % d2)
    Input.action_press("brake")
    await get_tree().create_timer(1.0).timeout
    Input.action_release("brake")
    var s2: float = world.car.speed_kph()
    var i2: int = world.last_idx
    var lap_t: float = world.lap_time
    print("SMOKE final: %d kph idx=%d lap_time=%.1f best=%.1f" % [int(s2), i2, lap_t, world.best_lap])
    var ok := true
    if contacts < 4:
        print("SMOKE_FAIL: wheels not on ground (%d/4)" % contacts)
        ok = false
    if absf(origin_h) > 0.8:
        print("SMOKE_FAIL: bad ride height (%.2f)" % origin_h)
        ok = false
    if s1 < 35.0:
        print("SMOKE_FAIL: speed too low (%d kph)" % int(s1))
        ok = false
    if lat_off < 1.0:
        print("SMOKE_FAIL: steering direction wrong or too weak (lat=%.2f)" % lat_off)
        ok = false
    if d1 < 0.15:
        print("SMOKE_FAIL: cornering does not build slip (drift=%.2f)" % d1)
        ok = false
    if d2 < 0.3:
        print("SMOKE_FAIL: handbrake drift too weak (drift=%.2f)" % d2)
        ok = false
    if s2 > 8.0:
        print("SMOKE_FAIL: brakes too weak (%d kph left)" % int(s2))
        ok = false
    if i2 - 3 < 8:
        print("SMOKE_FAIL: barely moved (idx %d)" % i2)
        ok = false
    if ok:
        print("SMOKE_OK")
        get_tree().quit(0)
    else:
        get_tree().quit(1)
