extends SceneTree
## Headless track-geometry diagnostic for Atlas Drift (v0.6.0 planning).
## Measures, on the REAL collision meshes:
##  1. road-surface height deviation vs the analytic centerline (the "bumps")
##  2. lateral deviation of the RoadGen ribbon vs the centerline (corner cut)
##  3. rail-line coverage: gap between the rail wall line and the road edge
##  4. cross-road transects at the worst corners (seam steps / "gaps")
## Copy into the project as scripts/diag_track_geo.gd, then:
##   godot --headless --path . -s res://scripts/diag_track_geo.gd

const HALF_W := 6.0

func _initialize() -> void:
        _run.call_deferred()


func _run() -> void:
        var tg := TrackGen.new()
        root.add_child(tg)
        tg.build(true)
        await process_frame
        await physics_frame

        var segs := -1
        if tg.road_container != null:
                segs = tg.road_container.get_segments().size()
        print("DIAG segments=%d samples=%d total_len=%.0f" % [segs, TrackGen.N, tg.total_len])

        var space := root.get_world_3d().direct_space_state
        var h_dev := {}
        var lat_dev := {}
        var rail_gap := {}
        for i in range(0, int(TrackGen.N), 1):
                var p: Vector3 = tg.pts[i]
                var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 8.0)
                q.collision_mask = 1
                var hit := space.intersect_ray(q)
                if hit.is_empty():
                        h_dev[i] = 99.0
                        lat_dev[i] = 99.0
                        continue
                var hp: Vector3 = hit.position
                h_dev[i] = hp.y - p.y
                var r: Vector3 = tg.rgts_flat[i]
                var off := Vector3(hp.x - p.x, 0, hp.z - p.z).dot(Vector3(r.x, 0, r.z))
                lat_dev[i] = off
                # rail zone check: at 6.3 m (banked frame) there must be solid
                # surface within 0.5 m of the banked plane point — no holes
                # under the rails (the v0.6.0 rails sit on that same plane)
                var rp: Vector3 = p + tg.rgts[i] * 6.3
                var q2 := PhysicsRayQueryParameters3D.create(rp + Vector3.UP * 4.0, rp + Vector3.DOWN * 12.0)
                q2.collision_mask = 1
                var h2 := space.intersect_ray(q2)
                if h2.is_empty():
                        rail_gap[i] = 99.0
                else:
                        rail_gap[i] = absf(h2.position.y - rp.y)

        var abs_h: Array = []
        for k in h_dev:
                abs_h.append([absf(h_dev[k]), k])
        abs_h.sort_custom(func(a, b): return a[0] > b[0])
        var mean_h := 0.0
        for a in abs_h:
                mean_h += a[0]
        mean_h /= maxf(abs_h.size(), 1.0)
        print("DIAG bumps: mean_abs=%.3f m max=%.3f m" % [mean_h, abs_h[0][0]])
        # distance from each worst sample to the nearest RoadPoint index
        var rp_set := {}
        for ri in tg.road_idxs:
                rp_set[ri] = true
        print("DIAG worst 12 height devs (idx, dev_m, dist_to_RP_samples):")
        for a in 12:
                var idx: int = abs_h[a][1]
                var dmin := 9999
                for d in range(-12, 13):
                        if rp_set.has((idx + d + int(TrackGen.N)) % int(TrackGen.N)):
                                dmin = mini(dmin, absi(d))
                print("  i=%d dev=%+.3f m rp_dist=%d" % [idx, h_dev[idx], dmin])

        var abs_l: Array = []
        for k in lat_dev:
                abs_l.append([absf(lat_dev[k]), k, lat_dev[k]])
        abs_l.sort_custom(func(a, b): return a[0] > b[0])
        var mean_l := 0.0
        for a in abs_l:
                mean_l += a[0]
        mean_l /= maxf(abs_l.size(), 1.0)
        print("DIAG lateral: mean_abs=%.3f m max=%.3f m (worst:)" % [mean_l, abs_l[0][0]])
        for a in 8:
                print("  i=%d lat=%+.3f m" % [abs_l[a][1], abs_l[a][2]])

        var gaps: Array = []
        for k in rail_gap:
                gaps.append([rail_gap[k], k])
        gaps.sort_custom(func(a, b): return a[0] > b[0])
        var n_bad := 0
        for g in gaps:
                if g[0] > 1.0:
                        n_bad += 1
        print("DIAG rail_gap: max=%.2f m, count>1.0m = %d / %d (worst:)" % [gaps[0][0], n_bad, gaps.size()])
        for a in 8:
                print("  i=%d gap=%.2f m" % [gaps[a][1], gaps[a][0]])

        for a in 3:
                var idx: int = abs_h[a][1]
                var p: Vector3 = tg.pts[idx]
                var r: Vector3 = tg.rgts_flat[idx]
                var line := "  transect i=%d:" % idx
                for s in [-5.0, -3.5, -2.0, -0.5, 0.5, 2.0, 3.5, 5.0]:
                        var pp: Vector3 = p + r * s
                        var q3 := PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 4.0, pp + Vector3.DOWN * 8.0)
                        q3.collision_mask = 1
                        var h3 := space.intersect_ray(q3)
                        if h3.is_empty():
                                line += " [%.1f]=--" % s
                        else:
                                line += " [%.1f]=%.2f" % [s, h3.position.y - p.y]
                print(line)

        print("DIAG_OK")
        quit(0)
