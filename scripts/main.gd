extends Node3D
## Atlas Drift bootstrap: input map, fonts, EventAudio bank, menu <-> world.

const GAME_VERSION := "0.5.0"
const SAVE_PATH := "user://atlas.cfg"

var font_regular: FontFile
var font_bold: FontFile
var world
var menu
var pause_menu
var car_panel: CarSettingsPanel


func _ready() -> void:
        _register_inputs()
        font_regular = load("res://assets/fonts/Tajawal-Regular.ttf")
        font_bold = load("res://assets/fonts/Tajawal-Bold.ttf")
        RenderingServer.set_default_clear_color(Color(0.09, 0.11, 0.16))
        _setup_event_audio()
        _make_menu()
        pause_menu = load("res://scripts/pause_menu.gd").new()
        pause_menu.setup(self)
        add_child(pause_menu)
        if "--smoke" in OS.get_cmdline_user_args():
                _smoke_test()


## Event Audio addon (addons/event_audio, autoload "EventAudio"): register a
## runtime-built EAEventBank. All discrete game SFX go through trigger tags;
## the tag hierarchy falls back right-to-left (e.g. "race+best" -> "race").
## v0.4.0: the impact one-shot is the real Starter Kit Racing impact.ogg
## (falls back to the synthesized thud if the asset is missing).
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
        var impact: AudioStream = load("res://assets/skr/audio/impact.ogg")
        if impact == null:
                impact = AudioSynth.thud()
        _add_event(bank, "car+impact", impact, -6.0, 0.85, 1.2)
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
        if get_tree().paused:
                resume_game()
        if world == null:
                _ensure_world()
        if car_panel != null and car_panel.is_open():
                car_panel.close()
                menu.visible = true
                return
        menu.visible = false
        world.begin_race()


## صفحة التوقف المؤقت (v0.5.0): freeze the whole tree and float the pause
## overlay above it. Allowed mid-race and mid-countdown; released inputs so
## no TouchScreenButton press survives the freeze as a stuck pedal.
func open_pause() -> void:
        if world == null:
                return
        if world.state != "race" and world.state != "countdown":
                return
        if pause_menu != null and pause_menu.is_open():
                return
        _release_drive_actions()
        get_tree().paused = true
        pause_menu.open()


func resume_game() -> void:
        get_tree().paused = false
        if pause_menu != null:
                pause_menu.close()
        _release_drive_actions()


func restart_race() -> void:
        resume_game()
        menu.visible = false
        world.begin_race()


func _release_drive_actions() -> void:
        for a in ["gas", "brake", "left", "right", "hand"]:
                Input.action_release(a)


## Lazily build the world (track + car + HUD) so the car settings panel has a
## live VehicleBody3D to tune even before the first race.
func _ensure_world() -> void:
        if world != null:
                return
        var game_script := load("res://scripts/game.gd")
        world = game_script.new()
        world.setup(self)
        add_child(world)


## Menu entry point: open the 3D Car settings panel over the menu.
func open_car_settings() -> void:
        _ensure_world()
        if car_panel == null:
                car_panel = load("res://scripts/settings_panel.gd").new()
                car_panel.setup(self, world.car)
                add_child(car_panel)
        car_panel.open()


func exit_to_menu() -> void:
        get_tree().paused = false
        if pause_menu != null:
                pause_menu.close()
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
        # ESC during a race/countdown opens the pause screen (while paused the
        # tree freezes this PAUSABLE handler — pause_menu.gd, which runs with
        # PROCESS_MODE_ALWAYS, owns ESC-to-resume instead).
        if event.is_action_pressed("ui_cancel"):
                if world != null and not get_tree().paused:
                        open_pause()


## Headless end-to-end smoke drive: menu -> race -> gas -> steer (direction
## verified!) -> drift -> brake -> quit. v0.3.0 thresholds calibrated for the
## realistic VehicleBody3D physics (0-100 in ~7 s, ~140 km/h top). v0.4.0 adds
## Road Generator / GridMap paddock / SKR audio / smoke particles / preset
## round-trip assertions.
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

    # --- v0.4.0 asset checks ---
    var ok := true
    var segs := -1
    if world.track.road_container != null:
        segs = world.track.road_container.get_segments().size()
    print("SMOKE roadgen: segments=%d" % segs)
    if segs < 100:
        print("SMOKE_FAIL: Road Generator segments missing (%d)" % segs)
        ok = false
    var cells := -1
    if world.track.paddock != null:
        cells = world.track.paddock.get_used_cells().size()
    print("SMOKE paddock: cells=%d" % cells)
    if cells < 10:
        print("SMOKE_FAIL: GridMap paddock missing (%d)" % cells)
        ok = false
    if world.car.wheels.size() != 4:
        print("SMOKE_FAIL: car wheels=%d" % world.car.wheels.size())
        ok = false
    if world.car.smoke_rl == null or world.car.smoke_rr == null:
        print("SMOKE_FAIL: smoke particles missing")
        ok = false
    var eng := world.car.engine_player != null and world.car.engine_player.stream is AudioStreamOggVorbis
    var skd := world.car.skid_player != null and world.car.skid_player.stream is AudioStreamOggVorbis
    print("SMOKE audio: engine_ogg=%s skid_ogg=%s" % [str(eng), str(skd)])
    if not eng or not skd:
        print("SMOKE_FAIL: SKR audio streams not wired")
        ok = false
    # Preset round-trip (3D Car system): save -> list -> load -> delete.
    world.car.max_torque = 2750.0
    var saved: bool = world.car.save_preset("zz_smoke")
    var in_list := false
    for p in world.car.list_presets():
        if p == "zz_smoke":
            in_list = true
    world.car.max_torque = 1000.0
    var loaded: bool = world.car.load_preset("zz_smoke")
    var torque_after: float = world.car.max_torque
    world.car.delete_preset("zz_smoke")
    var gone := true
    for p in world.car.list_presets():
        if p == "zz_smoke":
            gone = false
    print("SMOKE preset: save=%s list=%s load=%s torque=%.0f deleted=%s" % [
        str(saved), str(in_list), str(loaded), torque_after, str(gone)])
    if not saved or not in_list or not loaded or absf(torque_after - 2750.0) > 1.0 or not gone:
        print("SMOKE_FAIL: preset round-trip broken")
        ok = false

    # --- v0.5.0 orientation checks (the "السيارة مقلوبة" bug): the model
    # must face +Z (headlights surface centroid positive, taillights
    # negative), steering on the physical front (+Z) wheels, traction on
    # the physical rear. ---
    var vis: Node3D = world.car.get_node_or_null("ModelVis")
    if vis == null:
        print("SMOKE_FAIL: ModelVis missing")
        ok = false
    else:
        var hl_z := 99.0
        var tl_z := -99.0
        for ch in vis.get_children():
            if ch is MeshInstance3D:
                var mi := ch as MeshInstance3D
                for s in mi.mesh.get_surface_count():
                    var mat: Material = mi.mesh.surface_get_material(s)
                    if mat == null:
                        mat = mi.get_active_material(s)
                    if mat == null:
                        continue
                    var arr := mi.mesh.surface_get_arrays(s)
                    var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
                    if verts.size() == 0:
                        continue
                    var zsum := 0.0
                    for v in verts:
                        zsum += v.z
                    var cz := zsum / float(verts.size())
                    if mat.resource_name == "Headlights":
                        hl_z = cz
                    elif mat.resource_name == "TailLights":
                        tl_z = cz
        var fz: float = world.car.wheels[0].position.z
        var rz: float = world.car.wheels[2].position.z
        var steer_map: bool = world.car.wheels[0].use_as_steering and not world.car.wheels[2].use_as_steering
        print("SMOKE orient: headlights_z=%.2f taillights_z=%.2f front_z=%.2f rear_z=%.2f steer_map=%s" % [hl_z, tl_z, fz, rz, str(steer_map)])
        if hl_z < 0.3 or tl_z > -0.3:
            print("SMOKE_FAIL: model nose is not at +Z (hl=%.2f tl=%.2f)" % [hl_z, tl_z])
            ok = false
        if fz <= 0.0 or rz >= 0.0:
            print("SMOKE_FAIL: physics wheels mirrored (front_z=%.2f rear_z=%.2f)" % [fz, rz])
            ok = false
        if not steer_map:
            print("SMOKE_FAIL: steering not on physical front wheels")
            ok = false

    # --- v0.5.0 pause screen (صفحة التوقف المؤقت): open -> frozen tree +
    # overlay visible -> resume -> back to live race. ---
    open_pause()
    await get_tree().process_frame
    await get_tree().process_frame
    var p_ok: bool = get_tree().paused and pause_menu.visible and pause_menu.is_open()
    print("SMOKE pause: paused=%s menu=%s speed=%d" % [
        str(get_tree().paused), str(pause_menu.is_open()), int(world.car.linear_velocity.length())])
    resume_game()
    await get_tree().process_frame
    var r_ok: bool = not get_tree().paused and not pause_menu.is_open()
    print("SMOKE resume: paused=%s open=%s" % [str(get_tree().paused), str(pause_menu.is_open())])
    if not p_ok or not r_ok:
        print("SMOKE_FAIL: pause flow broken (open=%s resume=%s)" % [str(p_ok), str(r_ok)])
        ok = false

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
