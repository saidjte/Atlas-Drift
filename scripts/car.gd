class_name DriftCar
extends CharacterBody3D
## Hybrid arcade physics: stable grip base, speed-sensitive lateral slip
## (light drifting when cornering demand exceeds grip), handbrake kick,
## speed-scaled downforce and ABS-limited braking.

const VMAX := 56.0            # m/s flat-ground top speed (~200 km/h)
const A_ENGINE := 11.5
const BRAKE_DECEL := 13.5
const REVERSE_V := 8.0
const MU_ROAD := 1.08
const MU_DIRT := 0.55
const DF_K := 0.0058          # downforce gain (m/s^2 per (m/s)^2)
const DF_MAX := 20.0
const WHEELBASE := 2.6
const CD := 0.0018            # aero drag
const CRR := 0.012            # rolling resistance

var heading := 0.0
var steer := 0.0
var drift := 0.0              # smoothed slide factor 0..1
var grounded := true
var surface_name := "road"
var controls_enabled := false
var lat_g := 0.0              # displayed lateral g

var _throttle := 0.0
var _brake := 0.0
var _steer_in := 0.0
var _hand := false
var _n_up := Vector3.UP
var _wheel_spin := 0.0
var _acc_disp := 0.0

var wheels: Array[MeshInstance3D] = []   # FL, FR, RL, RR
var cam: Camera3D
var engine_player: AudioStreamPlayer
var skid_player: AudioStreamPlayer


func _ready() -> void:
        up_direction = Vector3.UP
        floor_max_angle = deg_to_rad(52)
        floor_snap_length = 1.6
        _build_visuals()
        _build_audio()


func read_input() -> void:
        if controls_enabled:
                _throttle = Input.get_action_strength("gas")
                _brake = Input.get_action_strength("brake")
                _steer_in = Input.get_action_strength("right") - Input.get_action_strength("left")
                _hand = Input.is_action_pressed("hand")
        else:
                _throttle = 0.0
                _brake = 0.0
                _steer_in = 0.0
                _hand = false


func _physics_process(dt: float) -> void:
        read_input()
        var fwd_h := Vector3(-sin(heading), 0.0, -cos(heading))

        # Ground normal blending (slope alignment).
        var n_target := Vector3.UP
        if is_on_floor():
                n_target = get_floor_normal()
        _n_up = _n_up.slerp(n_target, clampf(10.0 * dt, 0.0, 1.0)).normalized()

        var rgt := fwd_h.cross(_n_up).normalized()
        var fwd_s := _n_up.cross(rgt).normalized()

        var vF := velocity.dot(fwd_s)
        var vL := velocity.dot(rgt)
        grounded = is_on_floor()
        var speed := absf(vF)

        # Surface grip via downward raycast.
        var mu := _surface_mu()
        var g_eff := 9.81 + minf(DF_K * vF * vF, DF_MAX)
        var a_lat_max := mu * g_eff
        var grip_rate := 0.25

        if grounded:
                # --- longitudinal: engine, ABS-limited brake, reverse, drag ---
                var acc := 0.0
                if _throttle > 0.0:
                        var curve := maxf(1.0 - clampf(vF / VMAX, -1.0, 1.0), 0.0)
                        acc += _throttle * A_ENGINE * curve
                if _brake > 0.0:
                        if vF > 0.5:
                                acc -= _brake * minf(BRAKE_DECEL, mu * 9.81 * 1.05) # ABS cap
                        else:
                                acc -= _brake * 6.5 # reverse thrust
                acc -= CD * vF * absf(vF) + CRR * vF
                vF += acc * dt
                if _brake > 0.0 and vF < -REVERSE_V:
                        vF = -REVERSE_V

                # --- steering: speed-sensitive lock ---
                var s_norm := clampf(speed / 45.0, 0.0, 1.0)
                var max_st := lerpf(0.62, 0.13, s_norm)
                steer = move_toward(steer, _steer_in * max_st, 3.5 * dt)
                var yaw_rate := vF / WHEELBASE * tan(steer)

                # --- hybrid slip: demand vs grip -> controlled drift ---
                var demand := absf(yaw_rate * vF)
                var slide := clampf((demand - a_lat_max * 0.95) / 7.0, 0.0, 1.0)
                if _hand and speed > 4.0:
                        slide = maxf(slide, 0.62)
                drift = lerpf(drift, slide, clampf(6.0 * dt, 0.0, 1.0))
                grip_rate = lerpf(10.0, 2.0, drift) * (mu / MU_ROAD)

                lat_g = yaw_rate * vF / 9.81
                var yaw_extra := 0.0
                if _hand and speed > 4.0:
                        yaw_extra = _steer_in * 1.25 * clampf(speed / 30.0, 0.0, 1.0)
                heading += (yaw_rate * (1.0 - 0.30 * drift) + yaw_extra) * dt
                _acc_disp = lerpf(_acc_disp, acc, clampf(5.0 * dt, 0.0, 1.0))
        else:
                drift = lerpf(drift, 0.0, clampf(3.0 * dt, 0.0, 1.0))
                velocity.y -= 9.81 * dt
                heading += _steer_in * 0.5 * dt
                lat_g = 0.0

        # --- lateral tire force: decay side slip toward zero ---
        var lat_vel := rgt * vL
        lat_vel = lat_vel.lerp(Vector3.ZERO, clampf(grip_rate * dt, 0.0, 1.0))
        var v_y := velocity.y
        velocity = (fwd_s if grounded else fwd_h) * vF + lat_vel
        if not grounded:
                velocity.y = v_y

        move_and_slide()
        _update_transform(fwd_s, rgt)
        _update_wheels(dt, vF)
        _update_camera(dt, vF, fwd_h)
        _update_audio(vF)


func _surface_mu() -> float:
        var space := get_world_3d().direct_space_state
        var from := global_position + Vector3.UP * 1.0
        var to := global_position - Vector3.UP * 3.0
        var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
        var hit := space.intersect_ray(q)
        if hit.has("collider") and hit.collider is Node:
                var n := hit.collider as Node
                if n.is_in_group("road"):
                        surface_name = "road"
                        return MU_ROAD
                if n.is_in_group("rail"):
                        surface_name = "rail"
                        return MU_ROAD
        surface_name = "dirt"
        return MU_DIRT


func _update_transform(fwd_s: Vector3, rgt: Vector3) -> void:
        var b := Basis(rgt, _n_up, -fwd_s)
        # Visual body lean: roll from lateral g, pitch from acceleration.
        b = b.rotated(fwd_s, clampf(-lat_g * 0.022, -0.10, 0.10))
        b = b.rotated(rgt, clampf(-_acc_disp * 0.006, -0.05, 0.05))
        global_transform.basis = b.orthonormalized()


func _update_wheels(dt: float, vF: float) -> void:
        _wheel_spin += vF * dt / 0.48   # scaled sedan wheel radius (0.3 * 1.6)
        for i in wheels.size():
                var w := wheels[i]
                if w == null:
                        continue
                if i < 2:
                        w.basis = Basis(Vector3.UP, steer) * Basis(Vector3(1, 0, 0), _wheel_spin)
                else:
                        w.basis = Basis(Vector3(1, 0, 0), _wheel_spin)


func _update_camera(dt: float, vF: float, fwd_h: Vector3) -> void:
        if cam == null:
                cam = Camera3D.new()
                cam.fov = 66.0
                add_child(cam)
                cam.current = true
        var spd_norm := clampf(absf(vF) / VMAX, 0.0, 1.0)
        var back := 7.0 + 1.4 * spd_norm
        var desired := global_position - fwd_h * back + Vector3.UP * (3.0 + 0.5 * spd_norm)
        var w := clampf(7.0 * dt, 0.0, 1.0)
        cam.global_position = cam.global_position.lerp(desired, w)
        cam.look_at(global_position + Vector3.UP * 1.1 + fwd_h * 2.0)
        cam.fov = lerpf(64.0, 79.0, spd_norm)


func _update_audio(vF: float) -> void:
        if engine_player != null:
                var spd_norm := clampf(absf(vF) / VMAX, 0.0, 1.0)
                engine_player.pitch_scale = 0.62 + 1.15 * spd_norm + 0.18 * _throttle
                engine_player.volume_db = -20.0 + 9.0 * maxf(_throttle, spd_norm * 0.7)
        if skid_player != null:
                if grounded and drift > 0.18 and absf(vF) > 6.0:
                        skid_player.volume_db = lerpf(-60.0, -12.0, clampf(drift, 0.0, 1.0))
                        if not skid_player.playing:
                                skid_player.play()
                else:
                        skid_player.volume_db = -60.0


func respawn_to(pos: Vector3, yaw: float) -> void:
        global_position = pos + Vector3.UP * 1.4
        heading = yaw
        velocity = Vector3.ZERO
        steer = 0.0
        drift = 0.0
        _n_up = Vector3.UP
        if cam != null:
                var fwd_h := Vector3(-sin(heading), 0.0, -cos(heading))
                cam.global_position = global_position - fwd_h * 7.0 + Vector3.UP * 3.2
                cam.look_at(global_position + Vector3.UP * 1.1)


func speed_kph() -> float:
        return velocity.length() * 3.6


# ---------------------------------------------------------------- visuals

## Sedan-sports model (srcoder SimpleCar asset, CC0). The glTF faces +Z and
## our forward is -Z, so the model is wrapped in a 180° yaw pivot. Uniform
## scale 1.6 brings it to ~4.1 m long to match the physics footprint.
const CAR_SCALE := 1.6

func _build_visuals() -> void:
        var wrap := Node3D.new()
        wrap.rotation.y = PI
        add_child(wrap)

        var car_scene: PackedScene = load("res://assets/car/sedan-sports.glb")
        var vis := car_scene.instantiate() as Node3D
        vis.scale = Vector3(CAR_SCALE, CAR_SCALE, CAR_SCALE)
        wrap.add_child(vis)

        wheels = []
        for n in ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]:
                var w := vis.find_child(n, true, false) as MeshInstance3D
                wheels.append(w)
        _make_materials_double_sided(vis)

        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(1.95, 1.0, 4.05)
        cs.shape = shape
        cs.position = Vector3(0, 0.72, 0)
        add_child(cs)


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
