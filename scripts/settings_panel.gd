class_name CarSettingsPanel
extends CanvasLayer
## لوحة ضبط السيارة — Godot 4 port of the "3D Car With Settingspanel" asset
## (CC0) rebuilt with the game's UIKit for Arabic RTL. Same feature set as
## the original: engine/steering script variables, body weight, one tuning
## block per wheel (traction/steering flags, radius, friction, suspension,
## damping, roll influence, wheel binding) and the preset system saving to
## user://3d_car_customizable/ with save/load/delete — the first preset on
## the list auto-loads at launch (car.gd handles that part).

var main
var car: DriftCar
var root: Control
var preset_list: OptionButton
var preset_name: LineEdit
var status_label: Label

# Per-wheel UI state: sliders[key] and traction/steering toggles, plus the
# binding OptionButton. Index mirrors DriftCar.WHEEL_ORDER (FL, FR, RL, RR).
var wheel_blocks: Array[Dictionary] = []

var _wheel_titles := ["العجلة الأمامية اليسرى", "العجلة الأمامية اليمنى",
        "العجلة الخلفية اليسرى", "العجلة الخلفية اليمنى"]


func setup(m: Node3D, target: DriftCar) -> void:
        main = m
        car = target


func _ready() -> void:
        layer = 40
        visible = false
        _build()


func is_open() -> bool:
        return visible


func open() -> void:
        if car == null:
                return
        _sync_from_car()
        _refresh_preset_list()
        visible = true


func close() -> void:
        visible = false


# ---------------------------------------------------------------- UI build

func _build() -> void:
        root = Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(root)

        var dim := ColorRect.new()
        dim.color = Color(0.04, 0.05, 0.09, 0.9)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(dim)

        var panel := PanelContainer.new()
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.09, 0.11, 0.17, 0.98)
        sb.corner_radius_top_left = 18
        sb.corner_radius_top_right = 18
        sb.corner_radius_bottom_left = 18
        sb.corner_radius_bottom_right = 18
        sb.border_color = Color(0.85, 0.62, 0.18)
        sb.border_width_bottom = 3
        sb.content_margin_left = 18
        sb.content_margin_right = 18
        sb.content_margin_top = 14
        sb.content_margin_bottom = 14
        panel.add_theme_stylebox_override("panel", sb)
        panel.anchor_left = 0.5
        panel.anchor_right = 0.5
        panel.anchor_top = 0.5
        panel.anchor_bottom = 0.5
        panel.offset_left = -430
        panel.offset_right = 430
        panel.offset_top = -300
        panel.offset_bottom = 300
        root.add_child(panel)

        var scroll := ScrollContainer.new()
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        panel.add_child(scroll)

        var vbox := VBoxContainer.new()
        vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        vbox.add_theme_constant_override("separation", 10)
        scroll.add_child(vbox)

        vbox.add_child(_section_label("إعدادات السيارة", 40, Color(0.95, 0.78, 0.30)))
        vbox.add_child(_note("نظام الإعدادات من إضافة 3D Car With Settingspanel — تُطبَّق القيم فورًا وتُحفظ كإعدادات جاهزة.", 20))

        # ---- script variables + weight ----
        vbox.add_child(_section_label("المحرك والقيادة", 26, Color(0.85, 0.85, 0.92)))
        vbox.add_child(_slider_row("قوة المحرك (لكل عجلة خلفية)", 400.0, 6000.0,
                func() -> float: return car.max_torque,
                func(v: float) -> void: car.max_torque = v, 0))
        vbox.add_child(_slider_row("قوة الفرامل", 20.0, 220.0,
                func() -> float: return car.max_brake_force,
                func(v: float) -> void: car.max_brake_force = v, 0))
        vbox.add_child(_slider_row("أقصى زاوية توجيه", 0.15, 0.8,
                func() -> float: return car.max_steer,
                func(v: float) -> void: car.max_steer = v, 2))
        vbox.add_child(_slider_row("سرعة التوجيه", 1.0, 12.0,
                func() -> float: return car.steer_damping,
                func(v: float) -> void: car.steer_damping = v, 1))
        vbox.add_child(_slider_row("وزن السيارة (كغ)", 500.0, 2200.0,
                func() -> float: return car.mass,
                func(v: float) -> void: car.mass = v, 0))

        # ---- per-wheel blocks ----
        for i in 4:
                vbox.add_child(_section_label(_wheel_titles[i], 24, Color(0.55, 0.85, 0.6)))
                wheel_blocks.append(_build_wheel_block(vbox, i))

        # ---- presets ----
        vbox.add_child(_section_label("الإعدادات الجاهزة", 26, Color(0.85, 0.85, 0.92)))
        preset_list = OptionButton.new()
        preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _style_picker(preset_list)
        vbox.add_child(preset_list)
        var preset_row := HBoxContainer.new()
        preset_row.add_theme_constant_override("separation", 8)
        preset_row.add_child(_small_button("حفظ الإعداد", _on_save_preset))
        preset_row.add_child(_small_button("تحميل المحدد", _on_load_preset))
        preset_row.add_child(_small_button("حذف المحدد", _on_delete_preset))
        vbox.add_child(preset_row)
        preset_name = LineEdit.new()
        preset_name.placeholder_text = "اسم الإعداد الجديد…"
        preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        vbox.add_child(preset_name)

        status_label = _note("", 20)
        vbox.add_child(status_label)

        vbox.add_child(_small_button("إغلاق", close))

        for i in 4:
                _sync_wheel_block(i)
        _refresh_preset_list()


func _build_wheel_block(vbox: VBoxContainer, i: int) -> Dictionary:
        var w := car.wheels[i]
        var block := {}
        var trac := CheckButton.new()
        trac.text = "عجلة دفع"
        trac.button_pressed = w.use_as_traction
        trac.add_theme_font_override("font", main.font_regular)
        trac.add_theme_font_size_override("font_size", 20)
        trac.toggled.connect(func(on: bool) -> void:
                w.use_as_traction = on
                _apply_bound(i, "use_as_traction", on))
        vbox.add_child(trac)
        block["trac"] = trac

        var steer := CheckButton.new()
        steer.text = "عجلة توجيه"
        steer.button_pressed = w.use_as_steering
        steer.add_theme_font_override("font", main.font_regular)
        steer.add_theme_font_size_override("font_size", 20)
        steer.toggled.connect(func(on: bool) -> void:
                w.use_as_steering = on
                _apply_bound(i, "use_as_steering", on))
        vbox.add_child(steer)
        block["steer"] = steer

        var defs := [
                ["wheel_friction_slip", "التماسك", 0.4, 8.0, 2],
                ["wheel_radius", "قطر العجلة (م)", 0.2, 0.5, 2],
                ["wheel_rest_length", "طول راحة النوابض (م)", 0.15, 0.6, 2],
                ["suspension_travel", "مدى حركة النوابض (م)", 0.05, 0.5, 2],
                ["suspension_stiffness", "صلابة النوابض", 15.0, 110.0, 1],
                ["suspension_max_force", "أقصى قوة تعليق", 3000.0, 22000.0, 0],
                ["damping_compression", "تخميد الضغط", 0.2, 2.5, 2],
                ["damping_relaxation", "تخميد الارتخاء", 0.2, 2.5, 2],
                ["wheel_roll_influence", "تأثير ميل العجلة", 0.0, 1.0, 2],
        ]
        var sliders := {}
        for d in defs:
                var key: String = d[0]
                var s := _slider_row(d[1], d[2], d[3],
                        func() -> float: return car.wheels[i].get(key),
                        func(v: float) -> void:
                                car.wheels[i].set(key, v)
                                _apply_bound(i, key, v), d[4])
                vbox.add_child(s)
                sliders[key] = s
        block["sliders"] = sliders

        # Binding: a change on this wheel is mirrored onto the bound wheel,
        # matching the original asset's "Bind wheelsettings to each other".
        var bind := OptionButton.new()
        _style_picker(bind)
        bind.add_item("بدون ربط")
        for j in 4:
                if j != i:
                        bind.add_item(_wheel_titles[j])
        bind.item_selected.connect(func(menu_idx: int) -> void:
                _on_bind_changed(i, menu_idx))
        vbox.add_child(_labeled("اربط هذه العجلة بـ:", bind))
        block["bind"] = bind
        return block


# ---------------------------------------------------------------- helpers

func _slider_row(title: String, mn: float, mx: float, getter: Callable,
                setter: Callable, decimals: int) -> HBoxContainer:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        var lbl := _note(title, 20, 250)
        row.add_child(lbl)
        var s := HSlider.new()
        s.min_value = mn
        s.max_value = mx
        s.step = pow(10.0, -decimals)
        s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        s.custom_minimum_size = Vector2(0, 26)
        s.value_changed.connect(func(v: float) -> void: setter.call(v))
        row.add_child(s)
        var val := Label.new()
        val.custom_minimum_size = Vector2(88, 0)
        val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        val.add_theme_font_override("font", main.font_regular)
        val.add_theme_font_size_override("font_size", 18)
        val.add_theme_color_override("font_color", Color(0.95, 0.78, 0.3))
        row.add_child(val)
        s.set_meta("val_label", val)
        s.set_meta("decimals", decimals)
        # Order matters: connect AFTER the setter so the label refreshes post-apply.
        s.value_changed.connect(func(_v: float) -> void:
                var vl: Label = s.get_meta("val_label")
                vl.text = _fmt_val(s.value, s.get_meta("decimals")))
        s.value = getter.call()
        val.text = _fmt_val(s.value, decimals)
        return row


func _fmt_val(v: float, decimals: int) -> String:
        return "%.*f" % [decimals, v]


func _on_bind_changed(i: int, menu_idx: int) -> void:
        # Menu index 0 = none; 1..3 map onto the three other wheels in order.
        var block := wheel_blocks[i]
        block["bind_target"] = -1 if menu_idx <= 0 else _other_wheel(i, menu_idx - 1)
        if block["bind_target"] >= 0:
                _sync_wheel_to(i, block["bind_target"])
        status_label.text = "تم الربط" if block["bind_target"] >= 0 else "أُلغي الربط"


func _other_wheel(i: int, k: int) -> int:
        var others: Array[int] = []
        for j in 4:
                if j != i:
                        others.append(j)
        return others[k]


func _apply_bound(i: int, key: String, value) -> void:
        var block := wheel_blocks[i]
        if block.is_empty() or not block.has("bind_target"):
                return
        var t: int = block["bind_target"]
        if t < 0 or t >= 4:
                return
        var w: VehicleWheel3D = car.wheels[t]
        if key == "use_as_traction":
                w.use_as_traction = value
                wheel_blocks[t]["trac"].button_pressed = value
        elif key == "use_as_steering":
                w.use_as_steering = value
                wheel_blocks[t]["steer"].button_pressed = value
        else:
                w.set(key, value)
                _set_slider(wheel_blocks[t]["sliders"][key], float(value))


func _sync_wheel_to(src: int, dst: int) -> void:
        var a: VehicleWheel3D = car.wheels[src]
        var b: VehicleWheel3D = car.wheels[dst]
        b.use_as_traction = a.use_as_traction
        b.use_as_steering = a.use_as_steering
        for key in ["wheel_friction_slip", "wheel_radius", "wheel_rest_length",
                        "suspension_travel", "suspension_stiffness",
                        "suspension_max_force", "damping_compression",
                        "damping_relaxation", "wheel_roll_influence"]:
                b.set(key, a.get(key))
        _sync_wheel_block(dst)


func _set_slider(row: HBoxContainer, v: float) -> void:
        var s: HSlider = row.get_child(1)
        s.set_value_no_signal(v)
        var vl: Label = s.get_meta("val_label")
        vl.text = _fmt_val(v, s.get_meta("decimals"))


func _sync_wheel_block(i: int) -> void:
        if car == null or car.wheels.size() < 4:
                return
        var w := car.wheels[i]
        var block := wheel_blocks[i]
        block["trac"].set_pressed_no_signal(w.use_as_traction)
        block["steer"].set_pressed_no_signal(w.use_as_steering)
        for key in block["sliders"]:
                _set_slider(block["sliders"][key], w.get(key))


func _sync_from_car() -> void:
        for i in 4:
                _sync_wheel_block(i)


func _refresh_preset_list() -> void:
        preset_list.clear()
        preset_list.add_item("— اختر إعدادًا —")
        for pname in car.list_presets():
                preset_list.add_item(pname)


func _on_save_preset() -> void:
        var pname := preset_name.text.strip_edges()
        if pname.is_empty():
                if preset_list.selected > 0:
                        pname = preset_list.get_item_text(preset_list.selected)
        if pname.is_empty() or pname.begins_with("—"):
                status_label.text = "اكتب اسمًا للإعداد أولًا"
                return
        if car.save_preset(pname):
                status_label.text = "تم الحفظ: %s" % pname
                preset_name.text = ""
        else:
                status_label.text = "فشل الحفظ"
        _refresh_preset_list()


func _on_load_preset() -> void:
        if preset_list.selected <= 0:
                status_label.text = "اختر إعدادًا من القائمة"
                return
        var pname := preset_list.get_item_text(preset_list.selected)
        if car.load_preset(pname):
                status_label.text = "تم التحميل: %s" % pname
                _sync_from_car()
        else:
                status_label.text = "تعذر تحميل الإعداد"


func _on_delete_preset() -> void:
        if preset_list.selected <= 0:
                status_label.text = "اختر إعدادًا من القائمة"
                return
        var pname := preset_list.get_item_text(preset_list.selected)
        car.delete_preset(pname)
        status_label.text = "تم الحذف: %s" % pname
        _refresh_preset_list()


# ---------------------------------------------------------------- widgets

func _section_label(text: String, size: int, col: Color) -> Label:
        var l := UIKit.make_label(text, size, col, main.font_bold)
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        return l


func _note(text: String, size: int, min_w := 0.0) -> Label:
        var l := UIKit.make_label(text, size, Color(0.75, 0.78, 0.86), main.font_regular)
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        if min_w > 0.0:
                l.custom_minimum_size = Vector2(min_w, 0)
        return l


func _labeled(title: String, node: Control) -> HBoxContainer:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        var l := _note(title, 20, 170)
        row.add_child(l)
        node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(node)
        return row


func _style_picker(b: OptionButton) -> void:
        b.add_theme_font_override("font", main.font_regular)
        b.add_theme_font_size_override("font_size", 20)


func _small_button(text: String, cb: Callable) -> Button:
        var b := UIKit.make_button(text, main.font_regular, 20)
        b.pressed.connect(cb)
        return b
