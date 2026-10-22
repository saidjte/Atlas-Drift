class_name TrackGenLegacy
extends Node3D
## BAKE-TIME ONLY — never used at runtime. This is the old v0.6.x procedural
## pipeline (centerline math + Road Generator + SurfaceTool meshes + MultiMesh
## scenery), kept solely so tools/bake_world.gd can re-bake the world when the
## circuit changes. The game itself loads the frozen result via
## scripts/track_gen.gd ("الغي التوليد البرمجي وقت التشغيل — كل شيء مسبق
## التوليد في ملفات").
##
## Procedural Atlas mountain circuit: smooth closed loop (subdivide + Laplacian
## smoothing, the proven v3.0.0 approach), analytic banking, visual guardrails
## WITH collision (nothing invisible), skirt embankments, scenery via MultiMesh.
## v0.4.0: the asphalt ribbon itself is now built by the "Godot Road Generator"
## addon (TheDuckCow, MIT — addons/road-generator): a closed chain of
## RoadManager > RoadContainer > RoadPoint nodes laid on the same analytic
## centerline, giving trimsheet lane markings, tiled geometry, underside slabs
## and automated trimesh collision. The flat start paddock is a GridMap built
## from "Starter Kit Racing" mesh library (Kenney, MIT).

const N := 880                 # arc-length samples around the loop
const HALF_W := 6.0            # road half width (12 m)
const CURB_W := 0.9
const SKIRT_W := 14.0
const RAIL_H := 0.95
const BASE_Y := -6.0
const RP_STEP := 8             # one RoadPoint every N/RP_STEP samples
const PADDOCK_CENTER := Vector3(85, 0, -248)
const PADDOCK_RADIUS := 55.0   # scenery exclusion zone around the paddock

var pts := PackedVector3Array()      # centerline
var tans := PackedVector3Array()
var rgts := PackedVector3Array()     # rolled (banked) right vectors
var rgts_flat := PackedVector3Array()
var ups := PackedVector3Array()
var roll := PackedFloat32Array()
var kabs := PackedFloat32Array()     # |horizontal curvature| per sample (1/m)
var total_len := 0.0

var road_container: RoadContainer    # Road Generator container (v0.4.0)
var paddock: GridMap                 # Starter Kit Racing GridMap (v0.4.0)
var road_idxs := PackedInt32Array()  # RoadPoint sample indices (v0.6.0, diag)

var _sun: DirectionalLight3D
var _mat_vc: StandardMaterial3D
var _mat_vc_ds: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _shadows_requested := true


## v0.6.1: the build is split into three PHASES so main.gd can spread the
## work across frames in the background (the old single-frame build froze
## the whole game for seconds on phones the moment a menu button was
## pressed — "الضغط على أي زر يتسبب بتشنج اللعبة"). build() still runs all
## phases synchronously for the headless smoke test.
func build(shadows: bool) -> void:
        build_phase_a(shadows)
        build_phase_b()
        build_phase_c()


func build_phase_a(shadows: bool) -> void:
        _shadows_requested = shadows
        _rng.seed = 20260818
        _mat_vc = StandardMaterial3D.new()
        _mat_vc.vertex_color_use_as_albedo = true
        _mat_vc.roughness = 0.95
        _mat_vc.cull_mode = BaseMaterial3D.CULL_DISABLED
        _mat_vc_ds = _mat_vc.duplicate()
        _make_centerline()
        _make_frames()
        _build_road_generator()


func build_phase_b() -> void:
        _build_rails()
        _build_skirt_and_terrain()


func build_phase_c() -> void:
        _build_paddock()
        _build_scenery()
        _build_gates()
        _setup_environment(_shadows_requested)


## Shadow variants (sampled / not sampled in the lit pass) compile on the
## first frame they are RENDERED. Flipping the sun off for two frames and
## back on during the hidden background build precompiles both, so the
## menu's shadow toggle never stutters at runtime.
func set_shadow_state(on: bool) -> void:
        if _sun != null:
                _sun.shadow_enabled = on


# ---------------------------------------------------------------- centerline

func _make_centerline() -> void:
        # Hand-designed touge loop (x, height, z). ~2.3 km, two hairpins, esses.
        var ctrl: Array[Vector3] = [
                Vector3(0, 3, -300), Vector3(180, 7, -295), Vector3(330, 16, -240),
                Vector3(400, 30, -110), Vector3(370, 45, 40), Vector3(260, 56, 130),
                Vector3(150, 60, 90), Vector3(210, 55, 190), Vector3(140, 48, 290),
                Vector3(0, 52, 300), Vector3(-130, 58, 240), Vector3(-270, 62, 290),
                Vector3(-380, 50, 200), Vector3(-410, 36, 60), Vector3(-340, 26, -70),
                Vector3(-200, 20, -120), Vector3(-230, 14, -230), Vector3(-100, 8, -290),
        ]
        var m := ctrl.size()
        var poly := PackedVector3Array()
        for i in m:
                var a := ctrl[i]
                var b := ctrl[(i + 1) % m]
                for k in 12:
                        poly.append(a.lerp(b, float(k) / 12.0))
        # Closed-loop Laplacian smoothing (3 passes) -> C1-continuous, no overshoot.
        for pass_i in 3:
                var np := PackedVector3Array()
                np.resize(poly.size())
                for i in poly.size():
                        var prev := poly[(i - 1 + poly.size()) % poly.size()]
                        var next := poly[(i + 1) % poly.size()]
                        np[i] = poly[i] + (prev + next - poly[i] * 2.0) * 0.22
                poly = np
        # Arc-length resample to N uniform samples.
        var cum := PackedFloat32Array()
        cum.resize(poly.size() + 1)
        cum[0] = 0.0
        for i in poly.size():
                cum[i + 1] = cum[i] + poly[i].distance_to(poly[(i + 1) % poly.size()])
        total_len = cum[poly.size()]
        pts.clear()
        var step := total_len / float(N)
        var seg := 0
        for i in N:
                var d := float(i) * step
                while seg < poly.size() - 1 and cum[seg + 1] < d:
                        seg += 1
                var t := 0.0
                var seg_len := poly[seg].distance_to(poly[(seg + 1) % poly.size()])
                if seg_len > 0.0001:
                        t = clampf((d - cum[seg]) / seg_len, 0.0, 1.0)
                pts.append(poly[seg].lerp(poly[(seg + 1) % poly.size()], t))


func _make_frames() -> void:
        tans.clear()
        rgts.clear()
        rgts_flat.clear()
        ups.clear()
        roll.clear()
        kabs.clear()
        for i in N:
                var prev := pts[(i - 2 + N) % N]
                var next := pts[(i + 2) % N]
                var tg := (next - prev).normalized()
                var r := tg.cross(Vector3.UP)
                if r.length() < 0.001:
                        r = Vector3.RIGHT
                r = r.normalized()
                tans.append(tg)
                rgts_flat.append(r)
                rgts.append(r)
                ups.append(Vector3.UP)
                roll.append(0.0)
                kabs.append(0.0)
        # Signed horizontal curvature -> banking (outer edge raised).
        for i in N:
                var a := pts[(i - 2 + N) % N]
                var b := pts[i]
                var c := pts[(i + 2) % N]
                var v1 := b - a
                var v2 := c - b
                var la := v1.length()
                var lb := v2.length()
                if la < 0.01 or lb < 0.01:
                        continue
                var cross_y := v1.cross(v2).y
                var sinang := clampf(cross_y / (la * lb), -1.0, 1.0)
                var ang := asin(sinang)
                var k := ang / (0.5 * (la + lb)) # 1/m; right turn = negative
                kabs[i] = absf(k)
                # Right turn -> right (inner) edge lower: rotate right vector DOWN.
                roll[i] = clampf(-k * 5.0, -0.15, 0.15)
        # Smooth banking so it never steps.
        for pass_i in 2:
                var nroll := PackedFloat32Array()
                nroll.resize(N)
                for i in N:
                        var acc := 0.0
                        var cnt := 0
                        for d in range(-8, 9):
                                acc += roll[(i + d + N) % N]
                                cnt += 1
                        nroll[i] = acc / float(cnt)
                roll = nroll
        for i in N:
                var q := Quaternion(tans[i], roll[i])
                rgts[i] = (q * rgts[i]).normalized()
                ups[i] = (q * ups[i]).normalized()


# ---------------------------------------------------------------- road (Road Generator)

## v0.6.0 FIX ("الطريق مليء بالمطبات" + "المنعرجات الحادة بها تشوهات و فجوات"):
## the diag harness measured the collision ribbon deviating up to 0.29 m
## from the analytic centerline and twisting ~3.5° between the old sparse
## RoadPoints (fixed RP_STEP=8 ≈ 21 m). Two distinct causes: vertical
## crests/dips sagging between points, and the Hermite OVERSHOOTING the
## centerline in S-bends (alternating ±0.22 m sawtooth) — the chord metric
## cannot see the second one. So spans subdivide until the CUBIC RIBBON
## ITSELF stays within CHORD_TOL of the analytic centerline (measured at
## t = 0.25/0.5/0.75), which is exactly the surface the player drives on.
func _sample_road_indices() -> PackedInt32Array:
        const CHORD_TOL := 0.06
        const MAX_SPAN_M := 18.0
        var idxs := PackedInt32Array()
        var start := 0
        idxs.append(0)
        var guard := 0
        # Walk in VIRTUAL sample space (index mod N) so the closing span back
        # to sample 0 gets the same tolerance treatment as every other span.
        while start < N and guard < 5000:
                guard += 1
                var best := start + 1
                var j := start + 1
                while j <= N:
                        if pts[start % N].distance_to(pts[j % N]) > MAX_SPAN_M:
                                break
                        if _ribbon_dev(start, j) > CHORD_TOL:
                                break
                        best = j
                        j += 1
                start = best
                if start >= N:
                        break
                idxs.append(start)
        return idxs


## Bulge of the span [a,b]: max perpendicular distance from the chord LINE
## for (1) the CUBIC (Hermite) ribbon the road generator will actually build
## (proportional handles, sampled at t = 0.25/0.5/0.75) and (2) the analytic
## centerline samples in between (crest sag). Wraps over virtual indices.
## Bounding both terms bounds the Hermite-vs-analytic error — the surface
## the player actually drives on.
func _ribbon_dev(a: int, b: int) -> float:
        var ia := a % N
        var ib := b % N
        var pa := pts[ia]
        var pb := pts[ib]
        var chord := pb - pa
        var clen := chord.length()
        if clen < 1e-6:
                return 0.0
        var dir := chord / clen
        # The addon feeds prior/next_mag to Curve3D as CONTROL-POINT offsets
        # (handle_out = basis.z * mag), so the effective Hermite tangent is
        # 3 x mag. mag = 0.5 x chord (v0.4.0/v0.5.x) meant a 1.5 x chord
        # tangent — massively loose handles that made the ribbon overshoot
        # and sawtooth between points (the ±0.15 m wiggle the diag caught).
        # mag = 0.18 x chord gives the classic Catmull-Rom tangent
        # (~0.54 x chord) — smooth, minimal overshoot. MUST match the
        # rp.prior_mag/next_mag formula below.
        var mag := maxf(clen * 0.18, 1.0)
        var c1: Vector3 = pa + tans[ia] * mag
        var c2: Vector3 = pb - tans[ib] * mag
        var dev := 0.0
        for t: float in [0.25, 0.5, 0.75]:
                var u := 1.0 - t
                var bp := u * u * u * pa + 3.0 * u * u * t * c1 \
                        + 3.0 * u * t * t * c2 + t * t * t * pb
                dev = maxf(dev, (bp - pa).cross(dir).length())
        for k in range(a + 1, b):
                var p := pts[k % N]
                dev = maxf(dev, (p - pa).cross(dir).length())
        return dev


## Build the asphalt ribbon with the Godot Road Generator addon: a closed
## chain of RoadPoint nodes on the analytic centerline. Each RoadPoint carries
## the banked frame (right/up/tangent basis) so the generated geometry keeps
## the v0.3.0 banking; the trimsheet material provides lane markings, and the
## container generates trimesh collision for every segment automatically.
func _build_road_generator() -> void:
        var manager := RoadManager.new()
        manager.name = "RoadManager"
        add_child(manager)
        var container := RoadContainer.new()
        container.name = "TougeRoad"
        container.collider_group_name = "road"
        container.flatten_terrain = false
        container.underside_thickness = 0.8
        container.create_edge_curves = false
        container.generate_ai_lanes = false
        container.collision_layer = 1
        container.collision_mask = 1
        manager.add_child(container)
        road_container = container
        # Suppress per-property rebuild storms while assembling the chain;
        # one explicit rebuild at the end builds every segment once.
        container._auto_refresh = false

        var idxs := _sample_road_indices()
        road_idxs = idxs
        print("RoadGen sampling: %d curvature/crest-adaptive RoadPoints" % idxs.size())
        var count := idxs.size()
        var rps: Array[RoadPoint] = []
        for k in count:
                var i := idxs[k]
                var rp := RoadPoint.new()
                rp.name = "RP_%03d" % k
                # Right-handed point frame: x = left, y = up, z = forward
                # (tangent). rgts points LEFT already (tg x UP), so the frame
                # x axis is -rgts; a mirrored (det<1) basis twists every
                # segment junction and punches holes in the road surface.
                var left := ups[i].cross(tans[i]).normalized()
                var b := Basis(left, ups[i], tans[i]).orthonormalized()
                rp.transform = Transform3D(b, pts[i])
                container.add_child(rp)
                rps.append(rp)
        for k in count:
                var rp := rps[k]
                var i := idxs[k]
                var ip: int = idxs[(k - 1 + count) % count]
                var inx: int = idxs[(k + 1) % count]
                rp.auto_lanes = true
                rp.traffic_dir = [RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD]
                rp.lanes = [RoadPoint.LaneType.FAST, RoadPoint.LaneType.SLOW]
                rp.lane_width = 4.6
                rp.shoulder_width_l = 1.4
                rp.shoulder_width_r = 1.4
                rp.gutter_profile = Vector2(0.0, 0.0)
                # v0.6.0: slimmer underside slab — the old 1.2 m slab's seams
                # poked out of crests and knocked the car body ("مطبات").
                rp.underside_thickness = 0.8
                rp.flatten_terrain = false
                rp.prior_mag = maxf(pts[i].distance_to(pts[ip]) * 0.18, 1.0)
                rp.next_mag = maxf(pts[i].distance_to(pts[inx]) * 0.18, 1.0)
        # Closed loop: every point links to its neighbours in both directions.
        for k in count:
                var nxt := (k + 1) % count
                var prv := (k - 1 + count) % count
                rps[k].next_pt_init = NodePath("../RP_%03d" % nxt)
                rps[k].prior_pt_init = NodePath("../RP_%03d" % prv)
        container._auto_refresh = true
        container.rebuild_segments(true)
        # Belt & suspenders: make sure every generated collision body carries
        # the "road" group so the car's per-wheel surface grip detects it.
        var grouped := 0
        # v0.5.1 FIX ("السيارة تلتصق بجدران الطريق"): low-friction road
        # colliders so body scrapes (underside slabs, elevated edges, landings)
        # slide instead of glueing. Driving grip is unaffected — the raycast
        # wheels use wheel_friction_slip, never the PhysicsMaterial.
        var road_pm := PhysicsMaterial.new()
        road_pm.friction = 0.05
        road_pm.bounce = 0.05
        for cnode in container.get_collision_nodes():
                if not cnode.is_in_group("road"):
                        cnode.add_to_group("road", true)
                cnode.physics_material_override = road_pm
                grouped += 1
        print("RoadGen: %d RoadPoints -> %d segments, %d collision bodies" % [
                count, container.get_segments().size(), grouped])


# ------------------------------------------------------------- shared helpers

func _edge(i: int, side: float, extra := 0.0) -> Vector3:
        return pts[i] + rgts[i] * (side * (HALF_W + extra))


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
        for v in [a, b, c]:
                st.set_normal(n)
                st.set_color(col)
                st.add_vertex(v)
        for v in [a, c, d]:
                st.set_normal(n)
                st.set_color(col)
                st.add_vertex(v)


# ---------------------------------------------------------------- guardrails

## v0.6.0 FIX ("المنعرجات الحادة بها فجوات"): the rail line now follows the
## BANKED frame (rgts), not the flat one. The diag harness found the old
## flat-based rails floating up to ~0.9 m above the lowered inner edge of
## banked corners (road-edge-to-rail gaps up to 2.96 m over the skirt) —
## the car could see daylight under the rail and slide off the road.
func _rail_base(i: int, side: float) -> Vector3:
        return pts[i] + rgts[i] * (side * (HALF_W + 0.5))


func _build_rails() -> void:
        var mesh := ArrayMesh.new()
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        for side in [-1.0, 1.0]:
                for i in N:
                        var j := (i + 1) % N
                        var col := Color(0.85, 0.15, 0.13) if (i / 10) % 2 == 0 else Color(0.93, 0.91, 0.87)
                        var b0 := _rail_base(i, side) + Vector3.UP * 0.25
                        var t0 := _rail_base(i, side) + Vector3.UP * (0.25 + RAIL_H)
                        var b1 := _rail_base(j, side) + Vector3.UP * 0.25
                        var t1 := _rail_base(j, side) + Vector3.UP * (0.25 + RAIL_H)
                        _add_quad(st, b0, t0, t1, b1, col, -rgts_flat[i] * side)
        st.commit(mesh)
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = _mat_vc_ds
        add_child(mi)

        # Rail collision: one body per side, backface-safe. The invisible
        # collision face extends DOWN below the banked road edge (the visual
        # rail starts 0.25 m up for the post gap) — otherwise the car body
        # can slide under the rail and end up high-centered on top of it.
        for side in [-1.0, 1.0]:
                var faces := PackedVector3Array()
                for i in N:
                        var j := (i + 1) % N
                        var b0 := _rail_base(i, side) + Vector3.UP * (-0.33)
                        var t0 := _rail_base(i, side) + Vector3.UP * (0.25 + RAIL_H)
                        var b1 := _rail_base(j, side) + Vector3.UP * (-0.33)
                        var t1 := _rail_base(j, side) + Vector3.UP * (0.25 + RAIL_H)
                        for v in [b0, t0, t1, b0, t1, b1]:
                                faces.append(v)
                var shape := ConcavePolygonShape3D.new()
                shape.backface_collision = true
                shape.set_faces(faces)
                var body := StaticBody3D.new()
                body.add_to_group("rail", true)
                # v0.5.1 FIX ("السيارة تلتصق بالجدران الجانبية"): friction-free
                # rails with a touch of bounce — a car scraping the wall slides
                # along it and is gently pushed back instead of sticking.
                var rail_pm := PhysicsMaterial.new()
                rail_pm.friction = 0.0
                rail_pm.bounce = 0.3
                body.physics_material_override = rail_pm
                var cs := CollisionShape3D.new()
                cs.shape = shape
                body.add_child(cs)
                add_child(body)

        # Posts (visual only).
        var post_mesh := CylinderMesh.new()
        post_mesh.top_radius = 0.09
        post_mesh.bottom_radius = 0.11
        post_mesh.height = 1.15
        var post_mat := StandardMaterial3D.new()
        post_mat.albedo_color = Color(0.55, 0.57, 0.6)
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = post_mesh
        var count := 0
        for i in range(0, N, 12):
                count += 1
        mm.instance_count = count * 2
        var idx := 0
        for i in range(0, N, 12):
                for side in [-1.0, 1.0]:
                        var p := _rail_base(i, side) + Vector3.UP * 0.55
                        var t := Transform3D(Basis(), p)
                        mm.set_instance_transform(idx, t)
                        idx += 1
        var mmi := MultiMeshInstance3D.new()
        mmi.multimesh = mm
        mmi.material_override = post_mat
        add_child(mmi)


# ---------------------------------------------------------------- skirt + ground

func _skirt_bottom(i: int, side: float) -> Vector3:
        var r := rgts_flat[i]
        return Vector3(pts[i].x + r.x * side * (HALF_W + SKIRT_W), BASE_Y, pts[i].z + r.z * side * (HALF_W + SKIRT_W))


## Point on the banked road plane at lateral offset `off` beyond the edge,
## dropped `dy` meters — one vertex of the terraced embankment profile.
func _skirt_point(i: int, side: float, off: float, dy: float) -> Vector3:
        return pts[i] + rgts[i] * (side * (HALF_W + off)) - Vector3.UP * dy


## v0.6.0 ("تشوهات المنعرجات"): the embankment used to be ONE quad from the
## road edge straight down to BASE_Y — on high banked corners that read as a
## sheer dirt cliff right under the rails, with the rail floating ~2 m off
## the slope. The profile is now terraced: a ~26° shoulder for 4 m, a
## mid bench, then the long drop set back from the road.
func _build_skirt_and_terrain() -> void:
        var mesh := ArrayMesh.new()
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var dirt := Color(0.42, 0.33, 0.22)
        for side in [-1.0, 1.0]:
                for i in N:
                        var j := (i + 1) % N
                        var a0 := _skirt_point(i, side, 0.0, 0.05)
                        var a1 := _skirt_point(i, side, 4.0, 1.4)
                        var a2 := _skirt_point(i, side, 8.0, 5.0)
                        var a3 := _skirt_bottom(i, side)
                        var b0 := _skirt_point(j, side, 0.0, 0.05)
                        var b1 := _skirt_point(j, side, 4.0, 1.4)
                        var b2 := _skirt_point(j, side, 8.0, 5.0)
                        var b3 := _skirt_bottom(j, side)
                        var nrm: Vector3 = -rgts_flat[i] * side
                        _add_quad(st, a0, b0, b1, a1, dirt, nrm)
                        _add_quad(st, a1, b1, b2, a2, dirt, nrm)
                        _add_quad(st, a2, b2, b3, a3, dirt, nrm)
        st.commit(mesh)
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = _mat_vc_ds
        add_child(mi)

        # Ground body: skirt trimesh + big base box.
        var ground := StaticBody3D.new()
        ground.add_to_group("ground", true)
        var cs := CollisionShape3D.new()
        var skirt_shape := ConcavePolygonShape3D.new()
        skirt_shape.backface_collision = true
        var faces := PackedVector3Array()
        for side in [-1.0, 1.0]:
                for i in N:
                        var j := (i + 1) % N
                        var a0 := _skirt_point(i, side, 0.0, 0.05)
                        var a1 := _skirt_point(i, side, 4.0, 1.4)
                        var a2 := _skirt_point(i, side, 8.0, 5.0)
                        var a3 := _skirt_bottom(i, side)
                        var b0 := _skirt_point(j, side, 0.0, 0.05)
                        var b1 := _skirt_point(j, side, 4.0, 1.4)
                        var b2 := _skirt_point(j, side, 8.0, 5.0)
                        var b3 := _skirt_bottom(j, side)
                        for q in [[a0, b0, b1, a1], [a1, b1, b2, a2], [a2, b2, b3, a3]]:
                                for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
                                        faces.append(v)
        skirt_shape.set_faces(faces)
        cs.shape = skirt_shape
        ground.add_child(cs)

        var box := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = Vector3(2600, 2, 2600)
        box.shape = bs
        box.position = Vector3(0, BASE_Y - 1.0, 0)
        ground.add_child(box)
        add_child(ground)

        # Base terrain visual.
        var plane := PlaneMesh.new()
        plane.size = Vector2(2600, 2600)
        var pmi := MeshInstance3D.new()
        pmi.mesh = plane
        var sand := StandardMaterial3D.new()
        sand.albedo_color = Color(0.63, 0.52, 0.35)
        sand.roughness = 1.0
        pmi.material_override = sand
        pmi.position = Vector3(0, BASE_Y, 0)
        add_child(pmi)


# ---------------------------------------------------------------- paddock (GridMap)

## Flat start/finish paddock built with a GridMap and the "Starter Kit Racing"
## mesh library (Kenney, MIT): an apron of track-straight slabs, a track-corner
## turn piece, tents + forest decoration cells, and two parked trucks with real
## collision. Honours the GridMap-based track creation of the kit.
func _build_paddock() -> void:
        var lib: MeshLibrary = load("res://assets/skr/models/mesh_library.tres")
        if lib == null:
                push_warning("SKR mesh library missing — paddock skipped")
                return
        paddock = GridMap.new()
        paddock.name = "PaddockGridMap"
        paddock.mesh_library = lib
        paddock.cell_size = Vector3(10, 1, 10)
        # Start straight runs +X near z=-300; put the apron inside the loop.
        paddock.position = Vector3(PADDOCK_CENTER.x, BASE_Y + 0.12, PADDOCK_CENTER.z)
        add_child(paddock)

        const EMPTY := 0    # decoration-empty
        const FOREST := 1   # decoration-forest
        const TENTS := 2    # decoration-tents
        const CORNER := 3   # track-corner
        const STRAIGHT := 6 # track-straight

        # Apron: 6 x 2 slabs (a pit lane). The slabs are square 10 x 10 m, so the
        # default orientation is fine (Godot 4 has no exposed orthogonal-index
        # helper for arbitrary GridMap rotations).
        for gx in 6:
                for gz in [1, 2]:
                        paddock.set_cell_item(Vector3i(gx, 0, gz), STRAIGHT)
        # Corner piece closing the pit lane on the west end.
        paddock.set_cell_item(Vector3i(-1, 0, 2), CORNER, 0)
        # Tents row along the north edge, forest along the south edge.
        for gx in 6:
                if gx % 2 == 0:
                        paddock.set_cell_item(Vector3i(gx, 0, 0), TENTS, 0)
                else:
                        paddock.set_cell_item(Vector3i(gx, 0, 0), EMPTY, 0)
                paddock.set_cell_item(Vector3i(gx, 0, 4), FOREST, 0)
        paddock.set_cell_item(Vector3i(-1, 0, 3), FOREST, 0)
        paddock.set_cell_item(Vector3i(6, 0, 1), FOREST, 0)
        paddock.set_cell_item(Vector3i(6, 0, 2), FOREST, 0)

        # Parked trucks (Starter Kit models) on the apron with box collision.
        _park_truck("res://assets/skr/models/vehicle-truck-green.glb",
                Vector3(1.5, 0, 1.5), 0.6)
        _park_truck("res://assets/skr/models/vehicle-truck-red.glb",
                Vector3(4.0, 0, 1.5), -0.4)
        # The retired v0.2/v0.3 green sedan, parked as a paddock showcase.
        var sedan: Node3D = (load("res://assets/car/sedan-sports.glb") as PackedScene).instantiate()
        sedan.scale = Vector3(1.6, 1.6, 1.6)
        sedan.position = paddock.position + Vector3(26.0, 0.78, 24.0)
        sedan.rotation.y = 0.35
        add_child(sedan)
        _make_static_box(sedan.global_position, Vector3(2.2, 1.6, 4.6), sedan.rotation.y)

        print("Paddock: %d GridMap cells" % paddock.get_used_cells().size())


func _park_truck(path: String, cell_local: Vector3, yaw: float) -> void:
        var truck: Node3D = (load(path) as PackedScene).instantiate()
        # GridMap origin is at PADDOCK_CENTER; slabs at cell y=0 top out at
        # BASE_Y + 0.12 + 0.75. Trucks are glTF scale (~1:1, 5 m long).
        truck.position = paddock.position + cell_local * 10.0 + Vector3(0, 0.88, 0)
        truck.rotation.y = yaw
        add_child(truck)
        _make_static_box(truck.global_position, Vector3(2.6, 2.6, 5.4), yaw)


func _make_static_box(pos: Vector3, size: Vector3, yaw: float) -> void:
        var body := StaticBody3D.new()
        # v0.5.1: same anti-stick treatment as the rails — the car nudges
        # around parked trucks/obstacles instead of welding to them.
        var pm := PhysicsMaterial.new()
        pm.friction = 0.05
        pm.bounce = 0.15
        body.physics_material_override = pm
        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)
        body.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
        add_child(body)


# ---------------------------------------------------------------- scenery
# v0.6.0 ("الجبال و الأشجار تبدو سيئة جدا"): the old scenery was raw
# cylinders/cones with flat single-color materials. Everything below is
# flat-shaded low-poly with a PER-FACE color mosaic and noise displacement
# (the classic stylized racing look) while staying MultiMesh-cheap.
# The sky itself becomes a real CC0 morning HDRI panorama (Poly Haven
# "kiara_3_morning"), the asset borrowed from the reference project the user
# pointed at (github.com/Firet/3d-racing-game).

## Bake a triangle-soup mesh into the SurfaceTool as flat-shaded triangles
## with one color per FACE (col_fn(avg_y, shade) -> Color). The per-face
## mosaic is what makes the low-poly trees/mountains read as stylized art
## instead of smooth primitives.
func _bake_faces(st: SurfaceTool, faces: PackedVector3Array, xf: Transform3D,
                col_fn: Callable, rng: RandomNumberGenerator) -> void:
        var i := 0
        while i + 2 < faces.size():
                var a: Vector3 = xf * faces[i]
                var b: Vector3 = xf * faces[i + 1]
                var c: Vector3 = xf * faces[i + 2]
                var n := (b - a).cross(c - a)
                if n.length() > 0.0001:
                        n = n.normalized()
                var cy := (a.y + b.y + c.y) / 3.0
                var shade := rng.randf_range(0.86, 1.08)
                var col: Color = col_fn.call(cy, shade)
                for v in [a, b, c]:
                        st.set_normal(n)
                        st.set_color(col)
                        st.add_vertex(v)
                i += 3


## Craggy mountain ridge: a subdivided cone with simplex noise pushing the
## flanks in/out, snow caps above a noise-jittered snow line, per-face rock
## shades. Base ring stays exactly on the ground so instances sit cleanly.
func _mountain_mesh(seed_v: int) -> ArrayMesh:
        var noise := FastNoiseLite.new()
        noise.seed = seed_v
        noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
        noise.frequency = 1.15
        noise.fractal_octaves = 4
        var cone := CylinderMesh.new()
        cone.top_radius = 0.02
        cone.bottom_radius = 1.0
        cone.height = 1.0
        cone.radial_segments = 12
        cone.rings = 7
        var displaced := PackedVector3Array()
        for p0 in cone.get_faces():
                var p := p0
                if p.y > 0.015:
                        var disp := 1.0 + 0.42 * noise.get_noise_3d(p.x * 2.4, p.y * 1.1, p.z * 2.4)
                        p.x *= disp
                        p.z *= disp
                        p.y *= 1.0 + 0.18 * noise.get_noise_3d(p.x * 1.7 + 11.0, p.y * 3.0, p.z * 1.7)
                displaced.append(p)
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var rock_fn := func(y: float, shade: float) -> Color:
                var snow := clampf((y - 0.42) / 0.16, 0.0, 1.0)
                var grey := 0.5 + 0.5 * noise.get_noise_1d(y * 53.0 + float(seed_v))
                var rock := Color(0.47, 0.40, 0.33).lerp(Color(0.42, 0.41, 0.40), grey)
                return rock.lerp(Color(0.94, 0.96, 0.99), snow) * shade
        _bake_faces(st, displaced, Transform3D.IDENTITY, rock_fn, _rng)
        var mesh := ArrayMesh.new()
        st.commit(mesh)
        return mesh


## Two stylized tree species for the Atlas foothills: 0 = broadleaf
## (stout trunk + two overlapping canopy blobs), 1 = cedar (tall narrow
## stacked skirts — the classic mountain conifer).
func _tree_mesh(kind: int, seed_v: int) -> ArrayMesh:
        var rng := RandomNumberGenerator.new()
        rng.seed = seed_v
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var leaf_a := Color(0.14, 0.33, 0.15)
        var leaf_b := Color(0.20, 0.42, 0.18)
        if kind == 0:
                var trunk := CylinderMesh.new()
                trunk.top_radius = 0.12
                trunk.bottom_radius = 0.24
                trunk.height = 1.7
                trunk.radial_segments = 6
                trunk.rings = 2
                _bake_faces(st, trunk.get_faces(), Transform3D(Basis(), Vector3(0, 0.85, 0)),
                        func(_y: float, shade: float) -> Color: return Color(0.34, 0.24, 0.15) * shade, rng)
                var blob := SphereMesh.new()
                blob.radius = 1.1
                blob.height = 2.2
                blob.radial_segments = 7
                blob.rings = 4
                _bake_faces(st, blob.get_faces(), Transform3D(Basis(), Vector3(0, 2.45, 0)),
                        func(_y: float, shade: float) -> Color: return leaf_a * shade, rng)
                var blob2 := SphereMesh.new()
                blob2.radius = 0.72
                blob2.height = 1.44
                blob2.radial_segments = 6
                blob2.rings = 3
                _bake_faces(st, blob2.get_faces(), Transform3D(Basis(), Vector3(0.3, 3.3, 0.12)),
                        func(_y: float, shade: float) -> Color: return leaf_b * shade, rng)
        else:
                var trunk := CylinderMesh.new()
                trunk.top_radius = 0.1
                trunk.bottom_radius = 0.18
                trunk.height = 1.3
                trunk.radial_segments = 6
                trunk.rings = 1
                _bake_faces(st, trunk.get_faces(), Transform3D(Basis(), Vector3(0, 0.65, 0)),
                        func(_y: float, shade: float) -> Color: return Color(0.30, 0.21, 0.13) * shade, rng)
                var radii := [1.25, 0.95, 0.62]
                var heights := [1.55, 2.45, 3.30]
                for s in 3:
                        var skirt := SphereMesh.new()
                        skirt.radius = radii[s]
                        skirt.height = radii[s] * 1.05
                        skirt.radial_segments = 7
                        skirt.rings = 3
                        var sb := Basis().scaled(Vector3(1.0, 0.72, 1.0))
                        _bake_faces(st, skirt.get_faces(), Transform3D(sb, Vector3(0, heights[s], 0)),
                                func(_y: float, shade: float) -> Color: return leaf_a.lerp(leaf_b, float(s) / 2.0) * shade, rng)
        var mesh := ArrayMesh.new()
        st.commit(mesh)
        return mesh


## One MultiMeshInstance3D per baked mesh. Per-instance color tint multiplies
## the baked per-face colors (use_colors + vertex_color_use_as_albedo).
func _scatter_mesh(mesh: ArrayMesh, spots: Array[Transform3D], vmin: float, vmax: float) -> void:
        if spots.is_empty():
                return
        var mat := StandardMaterial3D.new()
        mat.vertex_color_use_as_albedo = true
        mat.roughness = 0.95
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.use_colors = true
        mm.mesh = mesh
        mm.instance_count = spots.size()
        for s in spots.size():
                mm.set_instance_transform(s, spots[s])
                mm.set_instance_color(s, Color(1, 1, 1) * _rng.randf_range(vmin, vmax))
        var mmi := MultiMeshInstance3D.new()
        mmi.multimesh = mm
        mmi.material_override = mat
        add_child(mmi)


func _build_scenery() -> void:
        var spots_leaf: Array[Transform3D] = []
        var spots_cedar: Array[Transform3D] = []
        # Along the road, beyond the skirt.
        for k in 300:
                var i := _rng.randi_range(0, N - 1)
                var side := 1.0 if _rng.randf() > 0.5 else -1.0
                var off := _rng.randf_range(21.0, 55.0)
                var r := rgts_flat[i]
                var p := Vector3(pts[i].x + r.x * side * off, BASE_Y, pts[i].z + r.z * side * off)
                if _in_paddock(p, 6.0):
                        continue
                if _rng.randf() < 0.55:
                        spots_leaf.append(_tree_tf(p, _rng))
                else:
                        spots_cedar.append(_tree_tf(p, _rng))
        # Scattered across the map, min distance from track.
        var tries := 0
        while spots_leaf.size() + spots_cedar.size() < 440 and tries < 3200:
                tries += 1
                var p := Vector3(_rng.randf_range(-650, 650), BASE_Y, _rng.randf_range(-650, 650))
                if _dist_to_track(p) > 26.0 and not _in_paddock(p, 6.0):
                        if _rng.randf() < 0.5:
                                spots_leaf.append(_tree_tf(p, _rng))
                        else:
                                spots_cedar.append(_tree_tf(p, _rng))
        _scatter_mesh(_tree_mesh(0, 77031), spots_leaf, 0.9, 1.12)
        _scatter_mesh(_tree_mesh(1, 77037), spots_cedar, 0.9, 1.12)
        _scatter_rocks()
        _build_peaks()


func _scatter_rocks() -> void:
        # Low-segment sphere, noise-displaced -> craggy boulder (IcosahedronMesh
        # is unavailable in 4.7.2, a faceted sphere reads the same when flat
        # shaded).
        var rock := SphereMesh.new()
        rock.radius = 1.0
        rock.height = 2.0
        rock.radial_segments = 7
        rock.rings = 4
        var noise := FastNoiseLite.new()
        noise.seed = 4242
        noise.frequency = 1.6
        var displaced := PackedVector3Array()
        for p0 in rock.get_faces():
                displaced.append(p0 * (1.0 + 0.34 * noise.get_noise_3d(p0.x * 3.1, p0.y * 3.1, p0.z * 3.1)))
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        _bake_faces(st, displaced, Transform3D.IDENTITY,
                func(_y: float, shade: float) -> Color: return Color(0.44, 0.42, 0.40) * shade, _rng)
        var mesh := ArrayMesh.new()
        st.commit(mesh)
        var spots: Array[Transform3D] = []
        var guard := 0
        while spots.size() < 120 and guard < 2400:
                guard += 1
                var p := Vector3(_rng.randf_range(-620, 620), BASE_Y, _rng.randf_range(-620, 620))
                if _dist_to_track(p) <= 18.0 or _in_paddock(p, 4.0):
                        continue
                var sc := _rng.randf_range(0.5, 2.8)
                var b := Basis().rotated(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
                        Vector3(sc, sc * 0.72, sc * _rng.randf_range(0.75, 1.2)))
                spots.append(Transform3D(b, p + Vector3(0, 0.3 * sc, 0)))
        _scatter_mesh(mesh, spots, 0.82, 1.12)


## Distant Atlas range: three craggy ridge variants ringed around the map,
## fading into the morning fog (replaces the old smooth cone peaks).
func _build_peaks() -> void:
        var s0: Array[Transform3D] = []
        var s1: Array[Transform3D] = []
        var s2: Array[Transform3D] = []
        var placed := 0
        while placed < 18:
                var ang := TAU * float(placed) / 18.0 + _rng.randf_range(-0.10, 0.10)
                var rad := _rng.randf_range(760.0, 1180.0)
                var h := _rng.randf_range(170.0, 400.0)
                var rad_m := _rng.randf_range(150.0, 330.0)
                var cx := cos(ang) * rad
                var cz := sin(ang) * rad
                var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(rad_m, h, rad_m))
                var t := Transform3D(b, Vector3(cx, BASE_Y - 2.0, cz))
                match placed % 3:
                        0: s0.append(t)
                        1: s1.append(t)
                        _: s2.append(t)
                placed += 1
        _scatter_mesh(_mountain_mesh(9011), s0, 0.88, 1.06)
        _scatter_mesh(_mountain_mesh(9017), s1, 0.88, 1.06)
        _scatter_mesh(_mountain_mesh(9029), s2, 0.88, 1.06)


func _tree_tf(p: Vector3, rng: RandomNumberGenerator) -> Transform3D:
        var sc := rng.randf_range(0.8, 1.7)
        var b := Basis().rotated(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc))
        return Transform3D(b, p)


func _dist_to_track(p: Vector3) -> float:
        var best := 1e9
        for i in range(0, N, 6):
                var d := p.distance_squared_to(pts[i])
                if d < best:
                        best = d
        return sqrt(best)


## True when the XZ position sits inside the GridMap paddock area (plus an
## extra margin), used to keep procedural scenery out of the paddock.
func _in_paddock(p: Vector3, margin := 0.0) -> bool:
        var dx := p.x - PADDOCK_CENTER.x
        var dz := p.z - PADDOCK_CENTER.z
        return Vector2(dx, dz).length() < PADDOCK_RADIUS + margin


# ---------------------------------------------------------------- gates

func _build_gates() -> void:
        _gate_at(0, Color(0.95, 0.78, 0.30))
        _gate_at(N / 4, Color(0.2, 0.75, 0.85))
        _gate_at(N / 2, Color(0.2, 0.75, 0.85))
        _gate_at(3 * N / 4, Color(0.2, 0.75, 0.85))


func _gate_at(i: int, col: Color) -> void:
        var post := CylinderMesh.new()
        post.top_radius = 0.22
        post.bottom_radius = 0.28
        post.height = 6.0
        var pm := StandardMaterial3D.new()
        pm.albedo_color = Color(0.75, 0.72, 0.68)
        for side in [-1.0, 1.0]:
                var mi := MeshInstance3D.new()
                mi.mesh = post
                mi.material_override = pm
                mi.position = pts[i] + rgts[i] * (side * (HALF_W + 0.7)) + Vector3.UP * 3.0
                add_child(mi)
        var banner := BoxMesh.new()
        banner.size = Vector3(2.0 * (HALF_W + 0.7), 1.1, 0.28)
        var bmi := MeshInstance3D.new()
        bmi.mesh = banner
        var bm := StandardMaterial3D.new()
        bm.albedo_color = col
        bmi.material_override = bm
        var q := Quaternion(Vector3.UP, atan2(-tans[i].x, -tans[i].z))
        bmi.transform = Transform3D(Basis(q), pts[i] + Vector3.UP * 5.6)
        add_child(bmi)


# ---------------------------------------------------------------- environment

func _setup_environment(shadows: bool) -> void:
        var env := Environment.new()
        env.background_mode = Environment.BG_SKY
        var sky := Sky.new()
        var hdr: Texture2D = load("res://assets/env/kiara_morning.jpg")
        if hdr != null:
                # v0.6.0: real morning panorama (Poly Haven "kiara_3_morning",
                # CC0 — borrowed from the reference project the user pointed
                # at, Firet/3d-racing-game). Replaces the flat procedural
                # gradient sky with actual clouds + warm light.
                var pano := PanoramaSkyMaterial.new()
                pano.panorama = hdr
                sky.sky_material = pano
        else:
                var sm := ProceduralSkyMaterial.new()
                sm.sky_top_color = Color(0.20, 0.40, 0.70)
                sm.sky_horizon_color = Color(0.88, 0.75, 0.55)
                sm.ground_bottom_color = Color(0.35, 0.28, 0.20)
                sm.ground_horizon_color = Color(0.88, 0.75, 0.55)
                sky.sky_material = sm
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_sky_contribution = 1.0
        env.ambient_light_energy = 1.0
        env.fog_enabled = true
        env.fog_density = 0.0011
        env.fog_light_color = Color(0.9, 0.8, 0.62)
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        var we := WorldEnvironment.new()
        we.environment = env
        add_child(we)

        _sun = DirectionalLight3D.new()
        _sun.rotation_degrees = Vector3(-48, -35, 0)
        _sun.light_energy = 1.25
        _sun.light_color = Color(1.0, 0.94, 0.82)
        _sun.shadow_enabled = shadows
        add_child(_sun)


func toggle_shadows() -> bool:
        if _sun != null:
                _sun.shadow_enabled = not _sun.shadow_enabled
                return _sun.shadow_enabled
        return false


# ---------------------------------------------------------------- queries

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
