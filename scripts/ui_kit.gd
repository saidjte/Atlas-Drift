class_name UIKit
extends Object
## Shared UI node helpers. v0.7.0: the old runtime per-pixel texture
## generators (circle_tex / arrow_tex) moved to tools/bake_ui.gd — the game
## loads the baked PNGs from res://assets/ui/ instead of generating them.

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
