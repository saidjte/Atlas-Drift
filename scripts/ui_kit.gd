class_name UIKit
extends Object
## Shared runtime-drawn UI helpers (no external assets).

static func circle_tex(diameter: int, fill: Color, ring: Color) -> ImageTexture:
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
        return ImageTexture.create_from_image(img)


static func arrow_tex(size: int, col: Color, angle_rad: float) -> ImageTexture:
        var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
        var c := Vector2(float(size) * 0.5, float(size) * 0.5)
        # Triangle in local space (pointing up), rotated by angle_rad around center.
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
        return ImageTexture.create_from_image(img)


static func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
        var d1 := _sign2(p, a, b)
        var d2 := _sign2(p, b, c)
        var d3 := _sign2(p, c, a)
        var has_neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
        var has_pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
        return not (has_neg and has_pos)


static func _sign2(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
        return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


static func make_label(text: String, size: int, color: Color, bold: FontFile, shadow := true) -> Label:
        var l := Label.new()
        l.text = text
        l.add_theme_font_override("font", bold)
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", color)
        if shadow:
                l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
                l.add_theme_constant_override("shadow_offset_x", 2)
                l.add_theme_constant_override("shadow_offset_y", 2)
        return l


static func make_button(text: String, font: FontFile, size_px: int) -> Button:
        var b := Button.new()
        b.text = text
        b.add_theme_font_override("font", font)
        b.add_theme_font_size_override("font_size", size_px)
        b.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
        b.add_theme_color_override("font_hover_color", Color(1, 0.85, 0.4))
        b.add_theme_color_override("font_pressed_color", Color(1, 0.75, 0.25))
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.13, 0.16, 0.23, 0.92)
        sb.corner_radius_top_left = 14
        sb.corner_radius_top_right = 14
        sb.corner_radius_bottom_left = 14
        sb.corner_radius_bottom_right = 14
        sb.content_margin_left = 26.0
        sb.content_margin_right = 26.0
        sb.content_margin_top = 12.0
        sb.content_margin_bottom = 12.0
        sb.border_width_bottom = 3
        sb.border_color = Color(0.85, 0.62, 0.18)
        b.add_theme_stylebox_override("normal", sb)
        var sb2: StyleBoxFlat = sb.duplicate()
        sb2.bg_color = Color(0.18, 0.22, 0.31, 0.95)
        b.add_theme_stylebox_override("hover", sb2)
        var sb3: StyleBoxFlat = sb.duplicate()
        sb3.bg_color = Color(0.30, 0.22, 0.10, 0.95)
        b.add_theme_stylebox_override("pressed", sb3)
        return b
