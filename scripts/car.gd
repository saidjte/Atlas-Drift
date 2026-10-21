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
## Body frame: forward = +Z, up = +Y, left = +X — Godot's VehicleBody3D
## convention (positive engine_force drives +Z, verified empirically on
## 4.7.2) which also matches the glTF model's native facing, so no visual
## flip is needed. Positive VehicleWheel3D steering points the wheels toward
## +X (car/screen LEFT when viewed from behind), so steer input is mapped as
##  left - right  (fixes the v0.2.0 inverted steering on touch and keyboard).

# ---- SRCoder Simple Car style tuning (kept names, retuned values) ----
@export var max_steer := 0.55             # rad, low-speed steering lock
@export var max_torque := 2600.0          # N per rear wheel at 0 rpm
@export var max_brake_force := 95.0       # N·s impulse cap per front wheel
@export var max_wheel_rpm := 950.0        # rear wheel rpm at force cutoff
@export var steer_damping := 3.0          # rad/s steering slew rate
@export var front_wheel_grip := 2.8       # friction slip, front (understeer bias)
@export var rear_wheel_grip := 2.2        # friction slip, rear wheels (RWD)

const WHEEL_RADIUS := 0.48                # sedan wheel radius (0.3 model * 1.6)
const REST_LENGTH := 0.42                 # suspension rest length
const TRAVEL := 0.26                      # suspension compression allowance
const STIFFNESS := 58.0
const MAX_SUSP_FORCE := 12000.0
const ROLL_INFLUENCE := 0.10              # low -> resists body roll (flat touge feel)
const CD_A := 0.32                        # aero drag coefficient*area (x rho/2)
const DOWNFORCE_K := 1.15                 # N per (m/s)^2
const DOWNFORCE_MAX := 5200.0
const REVERSE_FORCE := 980.0              # N per rear wheel in reverse
const REVERSE_VMAX := 9.0                 # m/s reverse cap
const CAR_SCALE := 1.6                    # GLB model -> meters

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

var _throttle := 0.0
var _brake := 0.0
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
        _build_visuals()
        _build_audio()


func read_input() -> void:
        if controls_enabled:
                # FIXED v0.3.0: left - right  (positive steering = turn left,
                # so pressing the right button now turns the car right).
                _steer_in = Input.get_action_strength("left") - Input.get_action_strength("right")
                _throttle = Input.get_action_strength("gas")
                _brake = Input.get_action_strength("brake")
                _hand = Input.is_action_pressed("hand")
        else:
                _steer_in = 0.0
                _throttle = 0.0
                _brake = 0.0
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

        if not controls_enabled:
                brake_f = 4.0                       # hold still on the grid / menu
                brake_r = 4.0
        elif _brake > 0.0 and vF > 0.8:
                # forward braking: ABS-style distribution (solver caps at grip)
                brake_f = max_brake_force * _brake
                brake_r = max_brake_force * 0.7 * _brake
        elif _brake > 0.0:
                engine = -REVERSE_FORCE * power_boost
                if vF < -REVERSE_VMAX:
                        engine = 0.0
        else:
                var curve := maxf(1.0 - rpm_norm, 0.0)
                engine = maxf(_throttle * power_boost * ((-max_torque / max_wheel_rpm) * rpm + max_torque), 0.0)

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

        _update_camera(dt, vF)
        _update_audio(vF)


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
                engine_player.pitch_scale = 0.62 + 1.15 * rpm_norm + 0.14 * _throttle
                engine_player.volume_db = -20.0 + 9.0 * maxf(_throttle, rpm_norm * 0.7)
        if skid_player != null:
                if grounded and drift > 0.18 and absf(vF) > 6.0:
                        skid_player.volume_db = lerpf(-60.0, -12.0, clampf(drift, 0.0, 1.0))
                        if not skid_player.playing:
                                skid_player.play()
                else:
                        skid_player.volume_db = -60.0


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


## Lap-card bonuses (called from game.gd on each completed lap).
func apply_card_mods(grip: float, power: float, rear: float) -> void:
        grip_boost = grip
        power_boost = power
        rear_release = rear


# ---------------------------------------------------------------- visuals

## Sedan-sports model (srcoder SimpleCar asset, CC0, body recolored green).
## The glTF faces +Z — exactly the VehicleBody3D drive direction — so the
## visual root only carries the 1.6 m scale. Each GLB wheel mesh is
## re-parented under a pivot node inside its VehicleWheel3D so the engine
## drives suspension travel, steering and roll; the pivot keeps the scale
## that the engine would otherwise overwrite on direct children.
func _build_visuals() -> void:
        var car_scene: PackedScene = load("res://assets/car/sedan-sports.glb")
        var vis := car_scene.instantiate() as Node3D
        vis.scale = Vector3(CAR_SCALE, CAR_SCALE, CAR_SCALE)
        add_child(vis)
        _make_materials_double_sided(vis)

        var defs := [
                ["wheel-front-left", Vector3(0.48, 0.0, 1.056), true],
                ["wheel-front-right", Vector3(-0.48, 0.0, 1.056), true],
                ["wheel-back-left", Vector3(0.48, 0.0, -1.056), false],
                ["wheel-back-right", Vector3(-0.48, 0.0, -1.056), false],
        ]
        wheels = []
        for d in defs:
                var mesh := vis.find_child(d[0], true, false) as MeshInstance3D
                var w := _make_wheel(d[1], d[2])
                wheels.append(w)
                if mesh != null:
                        vis.remove_child(mesh)
                        var pivot := Node3D.new()
                        w.add_child(pivot)
                        mesh.transform = Transform3D(Basis().scaled(Vector3.ONE * CAR_SCALE), Vector3.ZERO)
                        pivot.add_child(mesh)

        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(1.9, 1.0, 4.0)
        cs.shape = shape
        cs.position = Vector3(0, 0.8, 0)
        add_child(cs)


func _make_wheel(pos_xz: Vector3, steer: bool) -> VehicleWheel3D:
        var w := VehicleWheel3D.new()
        # Node origin = suspension top; wheel center rests REST_LENGTH below,
        # matching the model wheel-center height (0.48 m) at rest.
        w.position = Vector3(pos_xz.x, WHEEL_RADIUS + REST_LENGTH, pos_xz.z)
        w.use_as_steering = steer
        w.use_as_traction = not steer
        w.wheel_radius = WHEEL_RADIUS
        w.wheel_rest_length = REST_LENGTH
        w.suspension_travel = TRAVEL
        w.suspension_stiffness = STIFFNESS
        w.suspension_max_force = MAX_SUSP_FORCE
        w.damping_compression = 0.88
        w.damping_relaxation = 1.05
        w.wheel_roll_influence = ROLL_INFLUENCE
        add_child(w)
        return w


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
        engine_player = AudioStreamPlayer.new()
        engine_player.stream = AudioSynth.engine_loop()
        engine_player.volume_db = -20.0
        add_child(engine_player)
        engine_player.play()

        skid_player = AudioStreamPlayer.new()
        skid_player.stream = AudioSynth.skid_loop()
        skid_player.volume_db = -60.0
        add_child(skid_player)
        skid_player.play()
