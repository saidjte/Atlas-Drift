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
