extends SceneTree
## v0.7.0 UI BAKER — replaces runtime per-pixel ImageTexture generation with
## PNG files.
##
##   godot --headless --path . -s res://tools/bake_ui.gd
##
## The old UIKit.circle_tex()/arrow_tex() walked 256x256 pixels in GDScript
## six-plus times on the phone every launch. This tool renders the exact same
## shapes once and saves real PNGs into res://assets/ui/ — touch_controls.gd
## now just load()s CompressedTexture2D assets like any normal game.

const OUT := "res://assets/ui/"
const TEX_D := 256


func _initialize() -> void:
        _run.call_deferred()


func _run() -> void:
        DirAccess.make_dir_recursive_absolute(OUT)
        # Same colors touch_controls.gd used at runtime.
        var idle := circle_img(TEX_D, Color(0.16, 0.19, 0.27, 0.62), Color(0.85, 0.68, 0.25, 0.85))
        var pressed := circle_img(TEX_D, Color(0.95, 0.72, 0.20, 0.80), Color(1, 0.95, 0.7, 0.95))
        var col := Color(0.95, 0.92, 0.82, 0.85)
        var ok := true
        ok = _save(idle, "btn_idle.png") and ok
        ok = _save(pressed, "btn_pressed.png") and ok
        ok = _save(arrow_img(TEX_D, col, -PI / 2.0), "arrow_left.png") and ok
        ok = _save(arrow_img(TEX_D, col, PI / 2.0), "arrow_right.png") and ok
        ok = _save(arrow_img(TEX_D, col, 0.0), "arrow_up.png") and ok
        ok = _save(arrow_img(TEX_D, col, PI), "arrow_down.png") and ok
        ok = _save(arrow_img(TEX_D, col, PI / 4.0), "arrow_up_right.png") and ok
        if ok:
                print("BAKE_UI_OK")
                quit(0)
        else:
                quit(1)


func _save(img: Image, name: String) -> bool:
        var err := img.save_png(OUT + name)
        if err != OK:
                push_error("BAKE ui: %s failed (%d)" % [name, err])
                return false
        print("BAKE ui: %s%s (%dx%d)" % [OUT, name, img.get_width(), img.get_height()])
        return true


# ---- the exact pixel code that used to run on the phone (moved from
# scripts/ui_kit.gd, unchanged output) ----

func circle_img(diameter: int, fill: Color, ring: Color) -> Image:
        var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
        var c := float(diameter) * 0.5
        var r := c - 2.0
        for y in diameter:
                for x in diameter:
                        var d := Vector2(float(x) - c, float(y) - c).length()
                        var px := Color(0, 0, 0, 0)
                        if d <= r - 3.0:
                                px = fill
                        elif d <= r:
                                px = ring
                        img.set_pixel(x, y, px)
        return img


func arrow_img(size: int, col: Color, angle_rad: float) -> Image:
        var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
        var c := Vector2(float(size) * 0.5, float(size) * 0.5)
        var local: Array[Vector2] = [
                Vector2(0.0, -0.62), Vector2(0.55, 0.45), Vector2(-0.55, 0.45)
        ]
        var s := float(size) * 0.5
        var tri: Array[Vector2] = []
        for p: Vector2 in local:
                var q: Vector2 = p.rotated(angle_rad) * s + c
                tri.append(q)
        for y in size:
                for x in size:
                        var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
                        if _in_triangle(pt, tri[0], tri[1], tri[2]):
                                img.set_pixel(x, y, col)
        return img


func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
        var d1 := _sign2(p, a, b)
        var d2 := _sign2(p, b, c)
        var d3 := _sign2(p, c, a)
        var has_neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
        var has_pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
        return not (has_neg and has_pos)


func _sign2(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
        return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
