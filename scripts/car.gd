class_name DriftCar
extends VehicleBody3D
## Fully realistic vehicle simulation built on Godot's VehicleBody3D raycast
## vehicle (v0.3.0). Architecture adopted from "SRCoder's Simple Car" by
## Steve Rodkiss (CC0 — see addons/srcoder_simplecar): rpm-limited engine
## torque on rear wheels, steering/driving wheel groups, grip via wheel
## friction slip. Expanded here with real suspension tuning, ABS-style
## braking distribution, handbrake drift (rear grip cut), aerodynamic drag
## + speed-scaled downforce, per-wheel surface grip and impact audio events
## through the EventAudio addon.
##
## v0.4.0 asset fusion:
##  - Body visuals + tuning settings come from "3D Car With Settingspanel"
##    (CC0): the car_model.glb low-poly car with per-part materials, body
##    tinted green to keep the driver's livery. Its SettingsPanel preset
##    system (user://3d_car_customizable/*.json) is ported 1:1 in
##    scripts/settings_panel.gd and auto-loads the first preset on launch.
##  - Input feel follows "Starter Kit Racing" (Kenney, MIT) vehicle.gd:
##    lerped throttle/steer targets instead of raw keys (arcade-like
##    response) on top of the realistic physics core.
##  - Real engine / skid loops + drift smoke particles are the Starter Kit
##    assets (audio/*.ogg, sprites/smoke.png).
##
## Body frame: forward = +Z, up = +Y — positive engine_force drives +Z
## (verified empirically on 4.7.2). v0.5.0 orientation fix: car_model.glb
## natively faces +Z (its Headlights surface sits at z ≈ +2.0 and TailLights
## at z ≈ -2.1, and the original asset's own car.tscn steers the nodes named
## rear_* — i.e. the glb's front_/rear_ node names are swapped relative to
## the geometry). The visual root is therefore NOT yawed, the physics wheels
## keep their glTF positions, and the wheels array is filled physical-front
## first so the [FL, FR, RL, RR] order the game logic expects stays physical.
## Positive VehicleWheel3D steering points the wheels toward +X (car LEFT
## when viewed from behind), so steer input maps as left - right (v0.3.0).

# ---- SRCoder Simple Car style tuning (kept names, retuned values) ----
@export var max_steer := 0.55             # rad, low-speed steering lock
@export var max_torque := 2600.0          # N per rear wheel at 0 rpm
@export var max_brake_force := 95.0       # N·s impulse cap per front wheel
@export var max_wheel_rpm := 1150.0       # rear wheel rpm at force cutoff
                                          # (0.32 m wheels: ~140 km/h top)
@export var steer_damping := 3.0          # rad/s steering slew rate
@export var front_wheel_grip := 2.8       # friction slip, front (understeer bias)
@export var rear_wheel_grip := 2.2        # friction slip, rear wheels (RWD)

const WHEEL_RADIUS := 0.32                # car_model.glb wheel mesh radius (asset tuning: 0.32)
const REST_LENGTH := 0.35                 # suspension rest length
const TRAVEL := 0.24                      # suspension compression allowance
const STIFFNESS := 55.0
const MAX_SUSP_FORCE := 12000.0
const ROLL_INFLUENCE := 0.10              # low -> resists body roll (flat touge feel)
const CD_A := 0.32                        # aero drag coefficient*area (x rho/2)
const DOWNFORCE_K := 1.15                 # N per (m/s)^2
const DOWNFORCE_MAX := 5200.0
const ARCH_H := 0.49                      # car_model wheel-center height below body origin
# v0.5.1 anti-stick: the collision box slides along rails/walls instead of
# gripping them. Wheel grip is NOT affected — raycast wheels use
# wheel_friction_slip, never the PhysicsMaterial.
const BODY_FRICTION := 0.12
const BODY_BOUNCE := 0.02
const SMOKE_DRIFT := 0.30                 # drift level that starts the tire smoke

# v0.6.0 dedicated reverse gear ("اريد تمكين السيارة من الرجوع الى الخلف"):
# its own touch button / key drives the wheels BACKWARDS — the throttle keeps
# its v0.5.1 "always forward, wins over everything" semantics, so there is
# no more accidental reverse through brake+gas (the v0.5.0 complaint) and no
# more "car can't back up" either (the v0.5.1 complaint).
@export var max_reverse_torque := 1450.0  # N per rear wheel in reverse gear
@export var max_reverse_rpm := 250.0      # ~27 km/h wheel-rpm ceiling backwards

# Starter Kit Racing style input smoothing (lerped arcade response).
const STEER_EASE := 7.0
const THROTTLE_EASE := 5.0
const BRAKE_EASE := 6.0

var steer := 0.0
var drift := 0.0                          # smoothed slide factor 0..1
var grounded := true
var surface_name := "road"
var controls_enabled := false
var lat_g := 0.0                          # displayed lateral g
var rpm_norm := 0.0                       # avg driven-wheel rpm / max

# Lap-card modifiers (GodotCardManager bonus system, reset each lap).
var grip_boost := 1.0                     # SPADES: +friction all wheels
var power_boost := 1.0                    # CLUBS: +engine torque
var rear_release := 1.0                   # HEARTS: <1 = loose rear (drift)

var wheels: Array[VehicleWheel3D] = []    # FL, FR, RL, RR
var cam: Camera3D
var engine_player: AudioStreamPlayer
var skid_player: AudioStreamPlayer
var smoke_rl: GPUParticles3D
var smoke_rr: GPUParticles3D

var _throttle := 0.0
var _brake := 0.0
var _rev := 0.0
var _steer_in := 0.0
var _hand := false
var _wheel_mu := [1.0, 1.0, 1.0, 1.0]
var _impact_cd := 0.0


func _ready() -> void:
        mass = 1150.0
        center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
        center_of_mass = Vector3(0.0, 0.12, 0.0)
        can_sleep = false
        contact_monitor = true
        max_contacts_reported = 6
        body_entered.connect(_on_body_entered)
        # v0.5.1 anti-stick belt & suspenders: even away from the rails (paddock
        # trucks, road underside scrapes) the body slides instead of glueing.
        var pm := PhysicsMaterial.new()
        pm.friction = BODY_FRICTION
        pm.bounce = BODY_BOUNCE
        physics_material_override = pm
        _build_visuals()
        _build_audio()


func read_input() -> void:
        if controls_enabled:
                # FIXED v0.3.0: left - right  (positive steering = turn left,
                # so pressing the right button now turns the car right).
                # v0.4.0: Starter Kit Racing-style lerp toward the raw target gives
                # the arcade-like eased response on touch and keyboard alike.
                var target := Input.get_action_strength("left") - Input.get_action_strength("right")
                _steer_in = lerpf(_steer_in, target, clampf(STEER_EASE * _dt(), 0.0, 1.0))
                _throttle = lerpf(_throttle, Input.get_action_strength("gas"), clampf(THROTTLE_EASE * _dt(), 0.0, 1.0))
                _brake = lerpf(_brake, Input.get_action_strength("brake"), clampf(BRAKE_EASE * _dt(), 0.0, 1.0))
                _rev = lerpf(_rev, Input.get_action_strength("reverse"), clampf(THROTTLE_EASE * _dt(), 0.0, 1.0))
                _hand = Input.is_action_pressed("hand")
        else:
                _steer_in = lerpf(_steer_in, 0.0, clampf(8.0 * _dt(), 0.0, 1.0))
                _throttle = lerpf(_throttle, 0.0, clampf(8.0 * _dt(), 0.0, 1.0))
                _brake = lerpf(_brake, 0.0, clampf(8.0 * _dt(), 0.0, 1.0))
                _rev = lerpf(_rev, 0.0, clampf(8.0 * _dt(), 0.0, 1.0))
                _hand = false


func _physics_process(dt: float) -> void:
        read_input()
        _impact_cd = maxf(_impact_cd - dt, 0.0)

        var basis_inv := global_transform.basis.inverse()
        var v_local := basis_inv * linear_velocity
        var vF := v_local.z                        # forward speed (+ = ahead)
        var vL := v_local.x                        # lateral speed
        var speed := absf(vF)

        _update_surface()

        # ---- steering: speed-sensitive lock, rate limited ----
        if controls_enabled:
                var s_norm := clampf(speed / 38.0, 0.0, 1.0)
                var lock := lerpf(max_steer, 0.10, s_norm)
                steer = move_toward(steer, _steer_in * lock, steer_damping * dt)
        else:
                steer = move_toward(steer, 0.0, 4.0 * dt)
        steering = steer

        # ---- driven wheels: rpm-limited engine force (SRCoder curve) ----
        var rpm := 0.0
        for w in _driving_wheels():
                rpm += absf(w.get_rpm())
        rpm /= float(_driving_wheels().size())
        rpm_norm = clampf(rpm / max_wheel_rpm, 0.0, 1.0)

        var engine := 0.0
        var brake_f := 0.0
        var brake_r := 0.0

        # v0.5.1 FIX kept: gas ALWAYS drives forward and wins over the brake
        # AND the reverse gear. v0.6.0 adds a dedicated reverse gear on its
        # own action: it engages only from (near) standstill, is rpm-limited
        # to ~27 km/h, and the brake button brakes a rolling-back car.
        if not controls_enabled:
                brake_f = 4.0                       # hold still on the grid / menu
                brake_r = 4.0
        elif _throttle > 0.02:
                # gas wins: rpm-limited engine force (SRCoder curve), even if
                # the brake or reverse is still held — the car always drives
                # ahead.
                engine = maxf(_throttle * power_boost * ((-max_torque / max_wheel_rpm) * rpm + max_torque), 0.0)
        elif _rev > 0.02 and vF < 1.2:
                if _brake > 0.05 and vF < -0.5:
                        # rolling backwards + brake = stop the car, not throttle
                        brake_f = max_brake_force * _brake
                        brake_r = max_brake_force * _brake
                else:
                        # dedicated reverse gear: fade torque out near the
                        # reverse rpm ceiling, hard-cut past ~30 km/h.
                        var rrpm := clampf(rpm / max_reverse_rpm, 0.0, 1.0)
                        engine = -_rev * max_reverse_torque * (1.0 - 0.7 * rrpm)
                        if vF < -8.5:
                                engine = 0.0
        elif _brake > 0.0 and vF > 0.5:
                # forward braking: ABS-style distribution (solver caps at grip)
                brake_f = max_brake_force * _brake
                brake_r = max_brake_force * 0.7 * _brake
        elif _brake > 0.0:
                # stopped + brake = parking brake: hold still, NEVER creep
                # backwards (reverse lives on its own button now).
                brake_f = max_brake_force * _brake
                brake_r = max_brake_force * _brake

        var drive := _driving_wheels()
        for w in drive:
                w.engine_force = engine

        # ---- handbrake: locks rears + cuts rear grip -> real drift ----
        var hand := _hand and controls_enabled and speed > 3.0
        if hand:
                brake_r = maxf(brake_r, 80.0)

        # ---- per-wheel grip: base slip x card boosts x surface mu ----
        var rear_cut := 0.28 if hand else 1.0
        for i in 4:
                var w := wheels[i]
                if w == null:
                        continue
                w.brake = brake_f if i < 2 else brake_r
                var base := front_wheel_grip if i < 2 else rear_wheel_grip * rear_release
                var slip: float = base * grip_boost * _wheel_mu[i]
                if i >= 2:
                        slip *= rear_cut
                w.wheel_friction_slip = slip

        # ---- aerodynamics: drag + downforce (world space) ----
        var v := linear_velocity
        apply_central_force(-v * v.length() * CD_A)
        apply_central_force(Vector3.DOWN * minf(DOWNFORCE_K * v.length_squared(), DOWNFORCE_MAX))

        # ---- state for HUD / scoring ----
        var contacts := 0
        for w in wheels:
                if w != null and w.is_in_contact():
                        contacts += 1
        grounded = contacts >= 3
        var raw_slide := absf(vL) / maxf(speed, 3.0)
        var slide := clampf(raw_slide / 0.5, 0.0, 1.0)
        if hand:
                slide = maxf(slide, 0.55)
        drift = lerpf(drift, slide, clampf(7.0 * dt, 0.0, 1.0))
        lat_g = vF * angular_velocity.y / 9.81

        _update_smoke(speed, dt)
        _update_camera(dt, vF)
        _update_audio(vF)


func _dt() -> float:
        return get_physics_process_delta_time()


func _driving_wheels() -> Array[VehicleWheel3D]:
        if wheels.size() < 4:
                return []
        return [wheels[2], wheels[3]]


func _update_surface() -> void:
        var space := get_world_3d().direct_space_state
        var dirt := 0
        for i in 4:
                var w := wheels[i]
                if w == null:
                        _wheel_mu[i] = 1.0
                        continue
                var from := w.global_position
                var to := from - Vector3.UP * (REST_LENGTH + WHEEL_RADIUS + 0.6)
                var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
                var hit := space.intersect_ray(q)
                var mu := 1.0
                if hit.has("collider") and hit.collider is Node:
                        var n := hit.collider as Node
                        if n.is_in_group("road") or n.is_in_group("rail"):
                                mu = 1.0
                        else:
                                mu = 0.45
                                dirt += 1
                _wheel_mu[i] = mu
        surface_name = "dirt" if dirt >= 2 else "road"


func _on_body_entered(_body: Node) -> void:
        if _impact_cd > 0.0 or linear_velocity.length() < 4.0:
                return
        _impact_cd = 0.45
        var ea := get_node_or_null("/root/EventAudio")
        if ea != null:
                ea.play_3d("car+impact", self)


func _update_camera(dt: float, vF: float) -> void:
        if cam == null:
                cam = Camera3D.new()
                cam.fov = 66.0
                add_child(cam)
                cam.current = true
        var fwd := global_transform.basis.z
        fwd.y = 0.0
        fwd = fwd.normalized()
        var spd_norm := clampf(absf(vF) / 46.0, 0.0, 1.0)
        var back := 7.0 + 1.4 * spd_norm
        var desired := global_position - fwd * back + Vector3.UP * (3.0 + 0.5 * spd_norm)
        var w := clampf(7.0 * dt, 0.0, 1.0)
        cam.global_position = cam.global_position.lerp(desired, w)
        cam.look_at(global_position + Vector3.UP * 1.1 + fwd * 2.0)
        cam.fov = lerpf(64.0, 79.0, spd_norm)


func _update_audio(vF: float) -> void:
        if engine_player != null:
                # Real engine loop (Starter Kit Racing, engine.ogg): pitch tracks
                # rpm with a throttle kicker, volume follows load.
                engine_player.pitch_scale = 0.55 + 1.35 * rpm_norm + 0.18 * _throttle
                engine_player.volume_db = -24.0 + 11.0 * maxf(_throttle, rpm_norm * 0.7)
        if skid_player != null:
                if grounded and drift > 0.18 and absf(vF) > 6.0:
                        skid_player.volume_db = lerpf(-60.0, -10.0, clampf(drift, 0.0, 1.0))
                        skid_player.pitch_scale = 0.9 + 0.5 * clampf(absf(vF) / 40.0, 0.0, 1.0)
                        if not skid_player.playing:
                                skid_player.play()
                else:
                        skid_player.volume_db = -60.0


## Starter Kit Racing tire smoke: billboard GPUParticles at the rear wheels,
## emitting while the car is sliding (same trigger as the skid loop).
func _update_smoke(spd: float, dt: float) -> void:
        if smoke_rl == null:
                return
        var emit := grounded and drift > SMOKE_DRIFT and spd > 8.0
        smoke_rl.emitting = emit
        smoke_rr.emitting = emit


func set_pose(pos: Vector3, yaw: float) -> void:
        respawn_to(pos, yaw)


func respawn_to(pos: Vector3, yaw: float) -> void:
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
        steer = 0.0
        steering = 0.0
        drift = 0.0
        global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 0.35)
        if cam != null:
                var fwd := global_transform.basis.z
                fwd.y = 0.0
                fwd = fwd.normalized()
                cam.global_position = global_position - fwd * 7.0 + Vector3.UP * 3.2
                cam.look_at(global_position + Vector3.UP * 1.1)


func speed_kph() -> float:
        return linear_velocity.length() * 3.6


## Park the car (called when the race is left for the main menu): kill all
## motion, cut the engine/skid loops and the smoke — the race must SOUND and
## LOOK over, not keep idling behind the menu.
func park() -> void:
        controls_enabled = false
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
        _throttle = 0.0
        _brake = 0.0
        _rev = 0.0
        if smoke_rl != null:
                smoke_rl.emitting = false
        if smoke_rr != null:
                smoke_rr.emitting = false
        if engine_player != null:
                engine_player.stop()
        if skid_player != null:
                skid_player.stop()


## Restart the loop players after a park() (begin_race calls this).
func resume_audio() -> void:
        if engine_player != null and not engine_player.playing:
                engine_player.play()
        if skid_player != null and not skid_player.playing:
                skid_player.play()


## Lap-card bonuses (called from game.gd on each completed lap).
func apply_card_mods(grip: float, power: float, rear: float) -> void:
        grip_boost = grip
        power_boost = power
        rear_release = rear


# ------------------------------------------------------------ presets (3D Car)

## Preset system ported from "3D Car With Settingspanel" (CC0): tuning JSON
## files in user://3d_car_customizable/, first preset auto-loads on launch,
## and the schema keys match the original asset so its presets stay usable.
const PRESET_DIR := "user://3d_car_customizable/"
const WHEEL_ORDER := ["front_left", "front_right", "rear_left", "rear_right"]


func list_presets() -> Array[String]:
        var names: Array[String] = []
        var dir := DirAccess.open(PRESET_DIR)
        if dir == null:
                return names
        dir.list_dir_begin()
        var f := dir.get_next()
        while f != "":
                if not dir.current_is_dir() and f.ends_with(".json"):
                        names.append(f.trim_suffix(".json"))
                f = dir.get_next()
        dir.list_dir_end()
        names.sort()
        return names


func save_preset(pname: String) -> bool:
        if pname.strip_edges().is_empty():
                return false
        DirAccess.make_dir_recursive_absolute(PRESET_DIR)
        var data := {
                "MAX_ENGINE_FORCE": max_torque,
                "MAX_BRAKE": max_brake_force,
                "MAX_STEERING": max_steer,
                "STEERING_SPEED": steer_damping,
                "mass": mass,
                "wheel_names": ".".join(WHEEL_ORDER) + ".",
        }
        for i in 4:
                var w := wheels[i]
                if w == null:
                        continue
                data[WHEEL_ORDER[i]] = {
                        "use_as_traction": w.use_as_traction,
                        "use_as_steering": w.use_as_steering,
                        "wheel_roll_influence": w.wheel_roll_influence,
                        "wheel_radius": w.wheel_radius,
                        "wheel_rest_length": w.wheel_rest_length,
                        "wheel_friction_slip": w.wheel_friction_slip,
                        "suspension_travel": w.suspension_travel,
                        "suspension_stiffness": w.suspension_stiffness,
                        "suspension_max_force": w.suspension_max_force,
                        "damping_compression": w.damping_compression,
                        "damping_relaxation": w.damping_relaxation,
                }
        var f := FileAccess.open(PRESET_DIR + pname.strip_edges() + ".json", FileAccess.WRITE)
        if f == null:
                return false
        f.store_line(JSON.stringify(data, "\t"))
        f.close()
        return true


func delete_preset(pname: String) -> void:
        var path := PRESET_DIR + pname.strip_edges() + ".json"
        if FileAccess.file_exists(path):
                DirAccess.remove_absolute(path)


func load_preset(pname: String) -> bool:
        var f := FileAccess.open(PRESET_DIR + pname.strip_edges() + ".json", FileAccess.READ)
        if f == null:
                return false
        var parsed = JSON.parse_string(f.get_as_text())
        f.close()
        if typeof(parsed) != TYPE_DICTIONARY:
                return false
        return apply_preset(parsed)


## "weight" is kept for compatibility with the original asset's presets:
## it mirrors mass (weight = mass * 9.81) — mass wins when both differ.
func apply_preset(data: Dictionary) -> bool:
        if data.has("MAX_ENGINE_FORCE"):
                max_torque = float(data["MAX_ENGINE_FORCE"])
        if data.has("MAX_BRAKE"):
                max_brake_force = float(data["MAX_BRAKE"])
        if data.has("MAX_STEERING"):
                max_steer = float(data["MAX_STEERING"])
        if data.has("STEERING_SPEED"):
                steer_damping = float(data["STEERING_SPEED"])
        if data.has("mass"):
                mass = float(data["mass"])
        elif data.has("weight"):
                mass = float(data["weight"]) / 9.81
        var ok := true
        for i in 4:
                var w := wheels[i]
                if w == null or not data.has(WHEEL_ORDER[i]):
                        continue
                var wd: Dictionary = data[WHEEL_ORDER[i]]
                if typeof(wd) != TYPE_DICTIONARY:
                        ok = false
                        continue
                if wd.has("use_as_traction"):
                        w.use_as_traction = bool(wd["use_as_traction"])
                if wd.has("use_as_steering"):
                        w.use_as_steering = bool(wd["use_as_steering"])
                for key in ["wheel_roll_influence", "wheel_radius", "wheel_rest_length",
                                "wheel_friction_slip", "suspension_travel",
                                "suspension_stiffness", "suspension_max_force",
                                "damping_compression", "damping_relaxation"]:
                        if wd.has(key):
                                w.set(key, float(wd[key]))
        return ok


## The original asset auto-loads the first preset on the list at launch.
func _load_first_preset() -> void:
        var names := list_presets()
        if names.size() > 0:
                if load_preset(names[0]):
                        print("Preset loaded: ", names[0])
                else:
                        push_warning("Preset failed to parse: " + names[0])


# ---------------------------------------------------------------- visuals

## car_model.glb from "3D Car With Settingspanel" (CC0). Godot 4.7's glTF
## importer converts the model's *_wheel nodes into real VehicleWheel3D
## nodes (with the wheel meshes already parented inside), so the visuals are
## adopted as-is: each wheel is re-parented under this VehicleBody3D at its
## own glTF position (the model natively faces +Z — the SAME direction the
## body drives — so no yaw/mirror is applied) and re-tuned to the SRCoder
## style suspension numbers. The Body material is tinted green — the livery
## requested since v0.3.0 — and the body mesh is lifted so the model's wheel
## arches line up with the physics wheel centers.
##
## v0.5.0 FIX ("السيارة مقلوبة الامام في الخلف"): v0.4.0 assumed the glb
## faces -Z and mirrored everything (wheel positions negated + visual root
## yawed PI), which rendered the whole car nose-backwards while driving.
## Verified against the glb itself: Headlights surface centroid z ≈ +2.0,
## TailLights ≈ -2.1 → the model faces +Z exactly like the drive direction.
func _build_visuals() -> void:
        var car_scene: PackedScene = load("res://assets/car3d/car_model.glb")
        var vis := car_scene.instantiate() as Node3D
        vis.name = "ModelVis"
        add_child(vis)
        _tint_body_green(vis)

        # Collect the importer-generated wheels by their glTF names, then
        # adopt them in the FL, FR, RL, RR order the game logic expects.
        var by_name := {}
        for ch in vis.get_children():
                if ch is VehicleWheel3D:
                        by_name[String(ch.name)] = ch
        # Physical order [FL, FR, RL, RR]. The glb node names are swapped
        # relative to the geometry: nodes named front_* sit at z<0 (physical
        # REAR) and rear_* at z>0 (physical FRONT), and left/right are
        # mirrored as well (for a +Z-facing body, physical left = +X). So the
        # list reads odd on purpose — the first two entries are the PHYSICAL
        # front wheels, which is what the brake split / RWD logic expects.
        var order := ["rear_right", "rear_left", "front_right", "front_left"]
        wheels = []
        for nm in order:
                var w := by_name.get(nm) as VehicleWheel3D
                if w == null:
                        push_warning("car_model.glb wheel missing: %s" % nm)
                        continue
                var glb_pos := w.position          # glTF space (forward = +Z)
                vis.remove_child(w)
                w.position = Vector3(glb_pos.x, WHEEL_RADIUS + REST_LENGTH, glb_pos.z)
                var is_front := glb_pos.z > 0.0
                w.use_as_steering = is_front
                w.use_as_traction = not is_front
                _tune_wheel(w)
                add_child(w)
                wheels.append(w)

        # Body visual: NO yaw (the model already faces +Z, the same direction
        # the body drives — the v0.5.0 fix), just lift the arch line (model
        # wheel centers sit ARCH_H below the model origin) onto the physics
        # wheel centers.
        vis.position = Vector3(0, WHEEL_RADIUS + ARCH_H, 0)

        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(1.8, 1.15, 4.3)
        cs.shape = shape
        cs.position = Vector3(0, 0.72, 0)
        add_child(cs)

        _build_smoke()
        _load_first_preset()


## Apply the v0.3.0 suspension tuning onto an imported VehicleWheel3D.
## v0.6.0 ("الطريق مليء بالمطبات"): heavier damping — the old 0.88/1.05
## let the sprung mass oscillate after every crest and mid-corner banking
## shift, which read as constant small bumps. Compression +42%, rebound
## +43% keep the same ride height but kill the pogo effect.
func _tune_wheel(w: VehicleWheel3D) -> void:
        w.wheel_radius = WHEEL_RADIUS
        w.wheel_rest_length = REST_LENGTH
        w.suspension_travel = TRAVEL
        w.suspension_stiffness = STIFFNESS
        w.suspension_max_force = MAX_SUSP_FORCE
        w.damping_compression = 1.25
        w.damping_relaxation = 1.50
        w.wheel_roll_influence = ROLL_INFLUENCE


## Repaint every material named "Body" on the model in Atlas green.
func _tint_body_green(n: Node) -> void:
        if n is MeshInstance3D:
                var mi := n as MeshInstance3D
                for i in mi.get_surface_override_material_count():
                        var m := mi.get_active_material(i)
                        if m is BaseMaterial3D and m.resource_name == "Body":
                                var tinted: BaseMaterial3D = m.duplicate()
                                tinted.albedo_color = Color(0.16, 0.55, 0.24)
                                mi.set_surface_override_material(i, tinted)
        for c in n.get_children():
                _tint_body_green(c)


## Tire smoke: the process/surface materials are PRE-BAKED resource files
## (tools/bake_fx.gd → res://assets/fx/smoke_*.tres) — v0.7.0 removed the
## runtime Curve/CurveTexture/ParticleProcessMaterial construction.
## Rear-wheel positions come straight from the adopted physics wheels
## (physical rear = the glb nodes named front_*, z = -1.544).
func _build_smoke() -> void:
        var pm: ParticleProcessMaterial = load("res://assets/fx/smoke_process.tres")
        var mat: StandardMaterial3D = load("res://assets/fx/smoke_surface.tres")
        smoke_rl = _make_smoke_node(pm, mat, Vector3(0.82, 0.18, -1.544))
        smoke_rr = _make_smoke_node(pm, mat, Vector3(-0.82, 0.18, -1.544))


func _make_smoke_node(pm: ParticleProcessMaterial, mat: Material, pos: Vector3) -> GPUParticles3D:
        var p := GPUParticles3D.new()
        p.position = pos
        p.process_material = pm
        p.material_override = mat
        p.amount = 36
        p.lifetime = 0.6
        p.fixed_fps = 30
        p.emitting = false
        var quad := QuadMesh.new()
        quad.size = Vector2(0.9, 0.9)
        p.draw_pass_1 = quad
        add_child(p)
        return p


func _make_materials_double_sided(n: Node) -> void:
        if n is MeshInstance3D:
                var mi := n as MeshInstance3D
                for i in mi.get_surface_override_material_count():
                        var m := mi.get_active_material(i)
                        if m is BaseMaterial3D:
                                (m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
        for c in n.get_children():
                _make_materials_double_sided(c)


func _build_audio() -> void:
        # Starter Kit Racing real recordings; OGG imports default to no loop,
        # so the loop flag is forced here at runtime.
        engine_player = AudioStreamPlayer.new()
        var eng: AudioStream = load("res://assets/skr/audio/engine.ogg")
        if eng is AudioStreamOggVorbis:
                (eng as AudioStreamOggVorbis).loop = true
        engine_player.stream = eng
        engine_player.volume_db = -24.0
        add_child(engine_player)
        engine_player.play()

        skid_player = AudioStreamPlayer.new()
        var skd: AudioStream = load("res://assets/skr/audio/skid.ogg")
        if skd is AudioStreamOggVorbis:
                (skd as AudioStreamOggVorbis).loop = true
        skid_player.stream = skd
        skid_player.volume_db = -60.0
        add_child(skid_player)
        skid_player.play()
