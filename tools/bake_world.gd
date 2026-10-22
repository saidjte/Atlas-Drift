extends SceneTree
## v0.7.0 WORLD BAKER — runs ONCE on the dev machine, never on the phone.
##
##   godot --headless --path . -s res://tools/bake_world.gd
##
## Builds the whole Atlas mountain circuit with the old procedural pipeline
## (TrackGen phases A/B/C), then FREEZES the result into files:
##
##   res://scenes/world_track.scn     — the full baked world as a PackedScene
##                                      (road ribbon + collision, guardrails,
##                                      embankment skirt, terrain, GridMap
##                                      paddock, MultiMesh trees/rocks/mountains,
##                                      gates, HDRI environment, sun)
##   res://assets/track/centerline.res — TrackData (centerline arrays) for
##                                      respawn/lap/progress logic
##
## Every road-generator addon script is STRIPPED from the saved scene: the
## .scn contains only plain Node3D / MeshInstance3D / StaticBody3D nodes with
## embedded meshes and collision shapes. Loading it costs a file read and a
## scene instantiate — ZERO procedural generation at runtime.

const WORLD_OUT := "res://scenes/world_track.scn"
const DATA_OUT := "res://assets/track/centerline.res"
const GAMEPLAY_GROUPS := ["road", "rail", "ground"]

var _stripped := 0
var _road_bodies := 0
var _rails := 0
var _meshes := 0


func _initialize() -> void:
        _run.call_deferred()


func _run() -> void:
        print("BAKE world: building the circuit with the procedural pipeline...")
        var tg: TrackGenLegacy = load("res://scripts/track_gen_legacy.gd").new()
        root.add_child(tg)
        tg.build(true)
        await process_frame
        await process_frame
        await physics_frame   # flush collision bodies so surface raycasts hit

        # ---- v0.8.0 corner dressing (A Few Roads): chevron arrow boards on
        # the outer edge + red/white curbs on the inner edge of every sharp
        # corner. Runs HERE on the dev machine only — the results are frozen
        # into world_track.scn; the phone just loads the file. ----
        _dress_corners(tg)
        await process_frame

        # ---- capture the centerline data BEFORE any surgery ----
        var td := TrackData.new()
        td.n = TrackGenLegacy.N
        td.total_len = tg.total_len
        td.pts = tg.pts
        td.tans = tg.tans
        td.rgts = tg.rgts
        td.rgts_flat = tg.rgts_flat
        td.ups = tg.ups
        td.roll = tg.roll
        td.kabs = tg.kabs
        td.road_idxs = tg.road_idxs

        # ---- assemble a plain pack root and move the built world into it ----
        var pack_root := Node3D.new()
        pack_root.name = "AtlasTrackBaked"
        root.add_child(pack_root)
        for c in tg.get_children():
                tg.remove_child(c)
                pack_root.add_child(c)
        tg.queue_free()
        await process_frame

        # ---- strip ALL road-generator addon scripts: the saved scene must be
        # 100% static nodes so loading runs no addon code at all ----
        _stripped = 0
        _strip_scripts(pack_root)
        print("BAKE world: stripped %d addon scripts" % _stripped)

        # ---- force-persist every gameplay group: add_to_group() without
        # persistent=true is session-only and would NOT survive the save
        # (the first bake lost road/rail/ground groups this way) ----
        _persist_groups(pack_root)

        # ---- owner pass: only nodes owned by the pack root get saved.
        # Nodes inside instantiated GLB scenes keep their own owner chain, so
        # they stay EXTERNAL instance references (small files, fast loads). ----
        _set_owner(pack_root, pack_root)

        var ps := PackedScene.new()
        var err := ps.pack(pack_root)
        if err != OK:
                push_error("BAKE world: pack failed (%d)" % err)
                quit(1)
                return
        DirAccess.make_dir_recursive_absolute("res://scenes")
        err = ResourceSaver.save(ps, WORLD_OUT, ResourceSaver.FLAG_COMPRESS)
        if err != OK:
                push_error("BAKE world: save scene failed (%d)" % err)
                quit(1)
                return
        DirAccess.make_dir_recursive_absolute("res://assets/track")
        td.dressed_apexes = _apexes
        err = ResourceSaver.save(td, DATA_OUT, ResourceSaver.FLAG_COMPRESS)
        if err != OK:
                push_error("BAKE world: save data failed (%d)" % err)
                quit(1)
                return

        # ---- report ----
        _road_bodies = 0
        _rails = 0
        _meshes = 0
        _count(pack_root)
        var scn_kb: int = FileAccess.open(WORLD_OUT, FileAccess.READ).get_length() / 1024
        var dat_kb: int = FileAccess.open(DATA_OUT, FileAccess.READ).get_length() / 1024
        print("BAKE world: road_bodies=%d rail_bodies=%d mesh_instances=%d" % [
                _road_bodies, _rails, _meshes])
        print("BAKE world: centerline samples=%d total_len=%.1f m roadpoints=%d" % [
                td.n, td.total_len, td.road_idxs.size()])
        print("BAKE world: %s (%d KB), %s (%d KB)" % [WORLD_OUT, scn_kb, DATA_OUT, dat_kb])
        print("BAKE_WORLD_OK")
        quit(0)


func _strip_scripts(n: Node) -> void:
        if n.get_script() != null:
                n.set_script(null)
                _stripped += 1
        for c in n.get_children():
                _strip_scripts(c)


func _persist_groups(n: Node) -> void:
        for g in GAMEPLAY_GROUPS:
                if n.is_in_group(g):
                        # add_to_group(persistent=true) is a NO-OP when the node is
                        # already grouped session-only (the road bodies got their
                        # group from the addon's collider_group_name) — remove first.
                        n.remove_from_group(g)
                        n.add_to_group(g, true)
        for c in n.get_children():
                _persist_groups(c)


func _count(n: Node) -> void:
        if n is StaticBody3D:
                if n.is_in_group("road"):
                        _road_bodies += 1
                elif n.is_in_group("rail"):
                        _rails += 1
        elif n is MeshInstance3D:
                _meshes += 1
        for c in n.get_children():
                _count(c)


func _set_owner(n: Node, o: Node) -> void:
        if n != o and n.owner == null:
                n.owner = o
        for c in n.get_children():
                _set_owner(c, o)


# ================================================================ corner dressing
# v0.8.0 — A Few Roads reads corners through physical, pre-built signs and
# curbs (mark_triangle_* boards, ker curbs). Atlas Drift gets the same
# treatment, baked into the world scene: red/white chevron boards on the
# outside edge of each sharp corner, facing oncoming traffic, plus red/white
# curb strips along the inside edge at the apex. All static, all saved —
# zero runtime generation.

const CORNER_K_MIN := 1.0 / 32.0   # |curvature| above this = dressed corner
const CHEVRON_TEX_R := "res://assets/track/chevron_right.png"
const CHEVRON_TEX_L := "res://assets/track/chevron_left.png"

var _boards := 0
var _curbs := 0
var _dressed := 0
var _apexes := PackedInt32Array()


## Scan the centerline for sharp-corner runs and decorate each apex.
func _dress_corners(tg: TrackGenLegacy) -> void:
        var n: int = tg.N
        var pts: PackedVector3Array = tg.pts
        # signed horizontal curvature (right turn = negative), same chord
        # formula as the builder's banking pass
        var ks := PackedFloat32Array()
        ks.resize(n)
        for i in n:
                var a := pts[(i - 2 + n) % n]
                var b := pts[i]
                var c := pts[(i + 2) % n]
                var v1 := b - a
                var v2 := c - b
                var la := v1.length()
                var lb := v2.length()
                if la < 0.01 or lb < 0.01:
                        continue
                ks[i] = asin(clampf(v1.cross(v2).y / (la * lb), -1.0, 1.0)) / (0.5 * (la + lb))

        # corner runs above threshold, merged when closer than 6 samples
        var runs: Array = []
        var in_run := false
        var start := 0
        for i in n + 1:
                var sharp: bool = i < n and absf(ks[i]) > CORNER_K_MIN
                if sharp and not in_run:
                        in_run = true
                        start = i
                elif not sharp and in_run:
                        in_run = false
                        if i - start >= 3:
                                runs.append([start, i])
        var merged: Array = []
        for r in runs:
                if not merged.is_empty() and (r[0] - merged[-1][1]) < 6:
                        merged[-1][1] = r[1]
                else:
                        merged.append(r)

        var tex_r: Texture2D = load(CHEVRON_TEX_R)
        var tex_l: Texture2D = load(CHEVRON_TEX_L)
        var space := root.get_world_3d().direct_space_state
        var apexes := PackedInt32Array()
        for r in merged:
                var apex: int = r[0]
                for i in range(r[0], r[1]):
                        if absf(ks[i]) > absf(ks[apex]):
                                apex = i
                if absf(ks[apex]) < 1.0 / 30.0:
                        continue
                apexes.append(apex)
                var turn := signf(ks[apex])          # +1 left, -1 right
                var outer := turn                    # outer edge side
                var inner := -turn                   # inner (apex) edge side
                _dressed += 1
                for off in [-5, 0, 5]:
                        _add_chevron(tg, space, (apex + off + n) % n, outer,
                                tex_r if turn < 0.0 else tex_l)
                for off in [-4, -2, 0, 2, 4]:
                        _add_curb(tg, space, (apex + off + n) % n, inner,
                                int(floor(float(apex + off) * 0.5)) % 2 == 0)
        _apexes = apexes
        print("BAKE dressing: %d corners %s, %d chevron boards, %d curbs" % [
                _dressed, str(apexes), _boards, _curbs])


## Ground height under a world point (bake-time raycast; falls back to the
## centerline height when nothing is hit).
func _ground_y(space: PhysicsDirectSpaceState3D, p: Vector3, fallback: float) -> Dictionary:
        var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0,
                p + Vector3.DOWN * 14.0)
        var hit := space.intersect_ray(q)
        if hit.has("position"):
                return {"y": hit.position.y, "normal": hit.normal}
        return {"y": fallback, "normal": Vector3.UP}


## Red/white chevron board on a post at the OUTER edge, facing back along
## the track so approaching drivers see the arrows pointing into the turn.
func _add_chevron(tg: TrackGenLegacy, space: PhysicsDirectSpaceState3D,
                i: int, outer: float, tex: Texture2D) -> void:
        var edge: Vector3 = tg.pts[i] + tg.rgts_flat[i] * (outer * (tg.HALF_W + 2.2))
        var g: Dictionary = _ground_y(space, edge, tg.pts[i].y)
        var base_y: float = g["y"]

        var post := CylinderMesh.new()
        post.top_radius = 0.05
        post.bottom_radius = 0.06
        post.height = 1.35
        var post_mi := MeshInstance3D.new()
        post_mi.mesh = post
        var pm := StandardMaterial3D.new()
        pm.albedo_color = Color(0.42, 0.42, 0.44)
        post_mi.material_override = pm
        post_mi.position = Vector3(edge.x, base_y + 0.675, edge.z)
        tg.add_child(post_mi)

        var quad := QuadMesh.new()
        quad.size = Vector2(1.7, 0.95)
        var board := MeshInstance3D.new()
        board.mesh = quad
        var bm := StandardMaterial3D.new()
        bm.albedo_texture = tex
        bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        bm.cull_mode = BaseMaterial3D.CULL_DISABLED
        bm.roughness = 0.55
        board.material_override = bm
        var q := Quaternion(Vector3.UP, atan2(-tg.tans[i].x, -tg.tans[i].z))
        board.transform = Transform3D(Basis(q),
                Vector3(edge.x, base_y + 1.55, edge.z))
        tg.add_child(board)
        _boards += 1


## One red/white curb block on the INNER road edge at the apex — a static
## body grouped "road" so the wheels read it as asphalt and rumble over it.
func _add_curb(tg: TrackGenLegacy, space: PhysicsDirectSpaceState3D,
                i: int, inner: float, red: bool) -> void:
        var edge: Vector3 = tg.pts[i] + tg.rgts_flat[i] * (inner * (tg.HALF_W - 0.32))
        var g: Dictionary = _ground_y(space, edge, tg.pts[i].y)
        var y: float = g["y"]
        var nrm: Vector3 = (g["normal"] as Vector3).normalized()
        var tz: Vector3 = tg.tans[i].normalized()
        var zz := (tz - nrm * tz.dot(nrm)).normalized()   # tangent on the surface
        var xx := nrm.cross(zz).normalized()

        var body := StaticBody3D.new()
        body.add_to_group("road")            # persisted by _persist_groups
        # Same anti-stick policy as the road ribbon and the rails: the static
        # body is friction-free, grip lives entirely in wheel_friction_slip,
        # so a car scraping the curb slides instead of welding to it.
        var body_pm := PhysicsMaterial.new()
        body_pm.friction = 0.0
        body_pm.bounce = 0.0
        body.physics_material_override = body_pm
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(0.55, 0.08, 1.4)
        shape.shape = box
        body.add_child(shape)
        var mi := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = Vector3(0.55, 0.08, 1.4)
        mi.mesh = mesh
        var m := StandardMaterial3D.new()
        m.albedo_color = Color(0.80, 0.07, 0.12) if red else Color(0.92, 0.92, 0.92)
        m.roughness = 0.7
        mi.material_override = m
        body.add_child(mi)
        body.transform = Transform3D(Basis(xx, nrm, zz),
                Vector3(edge.x, y + 0.036, edge.z))
        tg.add_child(body)
        _curbs += 1
