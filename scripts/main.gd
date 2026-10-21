extends Node3D
## Atlas Drift bootstrap: input map, fonts, menu <-> world switching.

const GAME_VERSION := "0.2.0"
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
        _make_menu()
        if "--smoke" in OS.get_cmdline_user_args():
                _smoke_test()


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


## Headless end-to-end smoke drive: menu -> race -> gas -> steer -> drift -> quit.
func _smoke_test() -> void:
    await get_tree().create_timer(1.0).timeout
    start_race()
    await get_tree().create_timer(3.8).timeout
    Input.action_press("gas")
    await get_tree().create_timer(3.5).timeout
    var s1: float = world.car.speed_kph()
    var i1: int = world.last_idx
    print("SMOKE drive: %d kph idx=%d" % [int(s1), i1])
    Input.action_press("right")
    await get_tree().create_timer(0.8).timeout
    Input.action_release("right")
    var d1: float = world.car.drift
    print("SMOKE steer: drift=%.2f" % d1)
    Input.action_press("hand")
    await get_tree().create_timer(1.0).timeout
    var d2: float = world.car.drift
    Input.action_release("hand")
    print("SMOKE handbrake: drift=%.2f" % d2)
    Input.action_release("gas")
    Input.action_press("brake")
    await get_tree().create_timer(2.0).timeout
    Input.action_release("brake")
    var i2: int = world.last_idx
    var lap_t: float = world.lap_time
    print("SMOKE final: idx=%d lap_time=%.1f best=%.1f" % [i2, lap_t, world.best_lap])
    var ok := true
    if s1 < 60.0:
        print("SMOKE_FAIL: speed too low (%d kph)" % int(s1))
        ok = false
    if i2 - 3 < 12:
        print("SMOKE_FAIL: barely moved (idx %d)" % i2)
        ok = false
    if d1 < 0.05 and d2 < 0.05:
        print("SMOKE_FAIL: no drift response")
        ok = false
    if ok:
        print("SMOKE_OK")
        get_tree().quit(0)
    else:
        get_tree().quit(1)
