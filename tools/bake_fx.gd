extends SceneTree
## v0.7.0 FX BAKER — replaces runtime ParticleProcessMaterial / Curve /
## CurveTexture / StandardMaterial3D construction with resource files.
##
##   godot --headless --path . -s res://tools/bake_fx.gd
##
## car.gd used to build the tire-smoke process material (with two curves)
## from scratch on the phone. This tool builds the EXACT same materials once
## and saves them into res://assets/fx/ — car.gd now load()s them.

const OUT := "res://assets/fx/"


func _initialize() -> void:
        _run.call_deferred()


func _run() -> void:
        DirAccess.make_dir_recursive_absolute(OUT)

        var mat := StandardMaterial3D.new()
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.vertex_color_use_as_albedo = true
        mat.albedo_texture = load("res://assets/skr/sprites/smoke.png")
        mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
        mat.billboard_keep_scale = true
        mat.disable_receive_shadows = true
        mat.grow_amount = 0.5
        var e1 := ResourceSaver.save(mat, OUT + "smoke_surface.tres")
        print("BAKE fx: smoke_surface.tres (%d)" % e1)

        var alpha := Curve.new()
        alpha.add_point(Vector2(0.0, 0.0))
        alpha.add_point(Vector2(0.5, 1.0))
        alpha.add_point(Vector2(1.0, 0.0))
        var alpha_tex := CurveTexture.new()
        alpha_tex.curve = alpha

        var scale_c := Curve.new()
        scale_c.add_point(Vector2(0.0, 0.5))
        scale_c.add_point(Vector2(0.5, 1.0))
        scale_c.add_point(Vector2(1.0, 0.2))
        var scale_tex := CurveTexture.new()
        scale_tex.curve = scale_c

        var pm := ParticleProcessMaterial.new()
        pm.angle_min = -90.0
        pm.angle_max = 90.0
        pm.gravity = Vector3.ZERO
        pm.damping_min = 1.0
        pm.damping_max = 1.0
        pm.scale_min = 0.3
        pm.scale_max = 0.65
        pm.scale_curve = scale_tex
        pm.color = Color(0.37, 0.37, 0.42, 1.0)
        pm.alpha_curve = alpha_tex
        var e2 := ResourceSaver.save(pm, OUT + "smoke_process.tres")
        print("BAKE fx: smoke_process.tres (%d)" % e2)

        if e1 == OK and e2 == OK:
                print("BAKE_FX_OK")
                quit(0)
        else:
                quit(1)
