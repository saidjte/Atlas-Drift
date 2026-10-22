class_name TrackGen
extends Node3D
## v0.7.0 — ZERO RUNTIME GENERATION ("الغي التوليد البرمجي وقت التشغيل و جعل
## كل شيء مسبق التوليد او الافضل استعمال الملفات و الصور").
##
## The whole Atlas mountain circuit is baked ONCE by tools/bake_world.gd into
## real files and shipped inside the APK:
##   res://scenes/world_track.scn      — road ribbon + trimesh collision,
##                                       guardrails, embankment, terrain,
##                                       GridMap paddock, MultiMesh trees /
##                                       rocks / mountains, gates, HDRI sky,
##                                       sun. All static nodes with embedded
##                                       meshes — no addon scripts attached.
##   res://assets/track/centerline.res — TrackData: the analytic centerline
##                                       arrays for respawn / lap / progress.
##
## build() below is a FILE LOAD, not a generator: instantiate the packed
## scene, hook up the few named nodes the gameplay queries, copy the data
## arrays. Nothing here builds geometry, noise, meshes or materials anymore.

const N := 880                 # centerline samples (must match the baked data)
const HALF_W := 6.0            # road half width (informational; baked into the scn)
const BASE_Y := -6.0           # valley floor (game.gd kill-margin math)
const WORLD_SCENE := "res://scenes/world_track.scn"
const DATA_PATH := "res://assets/track/centerline.res"

var data: TrackData

# Centerline copies (same names as the v0.6.x generator — every consumer,
# including the smoke tests and the diag harness, keeps working unchanged).
var pts := PackedVector3Array()
var tans := PackedVector3Array()
var rgts := PackedVector3Array()
var rgts_flat := PackedVector3Array()
var ups := PackedVector3Array()
var roll := PackedFloat32Array()
var kabs := PackedFloat32Array()
var total_len := 0.0
var road_idxs := PackedInt32Array()

# Key baked nodes the game talks to.
var road_container: Node3D     # baked road ribbon (scripts stripped — plain Node3D)
var paddock: GridMap           # Starter Kit Racing GridMap paddock
var _sun: DirectionalLight3D
var build_ms := 0              # file-load time, for the smoke assertion


func build(shadows: bool) -> void:
        var t0 := Time.get_ticks_msec()
        data = load(DATA_PATH)
        if data == null:
                push_error("TrackGen: baked centerline missing at " + DATA_PATH)
                return
        if data.n != N:
                push_error("TrackGen: baked data has %d samples, expected %d — re-bake!" % [
                        data.n, N])
        pts = data.pts
        tans = data.tans
        rgts = data.rgts
        rgts_flat = data.rgts_flat
        ups = data.ups
        roll = data.roll
        kabs = data.kabs
        total_len = data.total_len
        road_idxs = data.road_idxs

        var packed: PackedScene = load(WORLD_SCENE)
        if packed == null:
                push_error("TrackGen: baked world missing at " + WORLD_SCENE)
                return
        var inst: Node3D = packed.instantiate()
        inst.name = "BakedWorld"
        add_child(inst)

        road_container = inst.get_node_or_null("RoadManager/TougeRoad")
        paddock = inst.get_node_or_null("PaddockGridMap")
        _sun = _find_light(inst)
        if _sun != null:
                _sun.shadow_enabled = shadows

        build_ms = Time.get_ticks_msec() - t0
        print("TrackGen: baked world loaded in %d ms (samples=%d, road_points=%d)" % [
                build_ms, data.n, road_idxs.size()])


func _find_light(n: Node) -> DirectionalLight3D:
        if n is DirectionalLight3D:
                return n
        for c in n.get_children():
                var found := _find_light(c)
                if found != null:
                        return found
        return null


## Shadow variants compile on the first frame they are RENDERED. The menu's
## shadow toggle prewarms both variants during the hidden background load —
## same behavior as v0.6.1, just flipping the BAKED sun.
func set_shadow_state(on: bool) -> void:
        if _sun != null:
                _sun.shadow_enabled = on


func toggle_shadows() -> bool:
        if _sun != null:
                _sun.shadow_enabled = not _sun.shadow_enabled
                return _sun.shadow_enabled
        return false


# ---------------------------------------------------------------- queries
# These read the baked TrackData arrays — pure table lookups, no math passes.

func pose_at(i: int) -> Dictionary:
        var idx := (i + N) % N
        var tg := tans[idx]
        # Car faces +Z (VehicleBody3D drive direction), so yaw orients +Z
        # along the tangent: basis.z = R_y(yaw) * (0,0,1) = (sin, 0, cos).
        var yaw := atan2(tg.x, tg.z)
        return {"pos": pts[idx], "yaw": yaw}


func start_pose() -> Dictionary:
        return pose_at(3)


func nearest_idx(p: Vector3, last: int) -> int:
        var best := last
        var bd := 1e18
        for d in range(-45, 46):
                var i := (last + d + N) % N
                var dd := p.distance_squared_to(pts[i])
                if dd < bd:
                        bd = dd
                        best = i
        # Recovery scan if we somehow got far away.
        if bd > 3600.0:
                for i in range(0, N, 4):
                        var dd2 := p.distance_squared_to(pts[i])
                        if dd2 < bd:
                                bd = dd2
                                best = i
        return best
