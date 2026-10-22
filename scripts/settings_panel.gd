class_name CarSettingsPanel
extends CanvasLayer
## لوحة ضبط السيارة — الإصدار المبسّط (v0.5.1).
##
## طلب المستخدم: «صفحة الاعدادات معقدة و إعدادات العجلات غير ضرورية» — أُزيلت
## كتل العجلات الأربع (دفع/توجيه/قطر/تماسك/نوابض/تخميد/ميل/ربط) كلياً، وبقيت
## الإعدادات الأساسية الخمسة فقط (المحرك، الفرامل، التوجيه، سرعة التوجيه،
## الوزن) مع نظام الإعدادات الجاهزة من أصل "3D Car With Settingspanel" (CC0):
## حفظ/تحميل/حذف في user://3d_car_customizable/ وتحميل الأول تلقائياً عند
## الإقلاع (في car.gd). مخطط JSON لم يتغير — الإعدادات القديمة تعمل، وقيم
## العجلات تُحفظ كما هي دون عرضها.

var main
var car: DriftCar
var root: Control
var preset_list: OptionButton
var preset_name: LineEdit
var status_label: Label

# The five simplified tuning rows, kept so open() can re-sync the slider
# positions from the live car (e.g. after loading a preset elsewhere).
var _rows: Array[Dictionary] = []


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
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -310
	panel.offset_bottom = 310
	root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	vbox.add_child(_section_label("إعدادات السيارة", 38, Color(0.95, 0.78, 0.30)))
	vbox.add_child(_note("خمسة إعدادات فقط تُطبَّق فوراً: المحرك، الفرامل، التوجيه والوزن. احفظها كإعداد جاهز لتعود إليها لاحقاً.", 20))

	# ---- the five core sliders ----
	vbox.add_child(_section_label("الضبط الأساسي", 26, Color(0.85, 0.85, 0.92)))
	_rows.append(_slider_row("قوة المحرك", 400.0, 6000.0,
			func() -> float: return car.max_torque,
			func(v: float) -> void: car.max_torque = v, 0))
	_rows.append(_slider_row("قوة الفرامل", 20.0, 220.0,
			func() -> float: return car.max_brake_force,
			func(v: float) -> void: car.max_brake_force = v, 0))
	_rows.append(_slider_row("أقصى زاوية توجيه", 0.15, 0.8,
			func() -> float: return car.max_steer,
			func(v: float) -> void: car.max_steer = v, 2))
	_rows.append(_slider_row("سرعة التوجيه", 1.0, 12.0,
			func() -> float: return car.steer_damping,
			func(v: float) -> void: car.steer_damping = v, 1))
	_rows.append(_slider_row("وزن السيارة (كغ)", 500.0, 2200.0,
			func() -> float: return car.mass,
			func(v: float) -> void: car.mass = v, 0))
	for r in _rows:
		vbox.add_child(r["row"])

	# ---- presets ----
	vbox.add_child(_section_label("الإعدادات الجاهزة", 26, Color(0.85, 0.85, 0.92)))
	preset_list = OptionButton.new()
	preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_picker(preset_list)
	vbox.add_child(preset_list)
	preset_name = LineEdit.new()
	preset_name.placeholder_text = "اسم الإعداد الجديد…"
	preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(preset_name)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	preset_row.add_child(_small_button("حفظ", _on_save_preset))
	preset_row.add_child(_small_button("تحميل المحدد", _on_load_preset))
	preset_row.add_child(_small_button("حذف المحدد", _on_delete_preset))
	vbox.add_child(preset_row)

	status_label = _note("", 20)
	vbox.add_child(status_label)

	vbox.add_child(_small_button("إغلاق", close))

	_refresh_preset_list()


# ---------------------------------------------------------------- helpers

## One labeled slider row (RTL: label | slider | value). Returns a Dictionary
## {row, getter, decimals} so open() can re-sync values from the car.
func _slider_row(title: String, mn: float, mx: float, getter: Callable,
				setter: Callable, decimals: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := _note(title, 20, 220)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = pow(10.0, -decimals)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 30)
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
	return {"row": row, "getter": getter, "decimals": decimals}


func _fmt_val(v: float, decimals: int) -> String:
	return "%.*f" % [decimals, v]


func _sync_from_car() -> void:
	for r in _rows:
		var row: HBoxContainer = r["row"]
		var s: HSlider = row.get_child(1)
		var v: float = float(r["getter"].call())
		s.set_value_no_signal(v)
		var vl: Label = s.get_meta("val_label")
		vl.text = _fmt_val(v, r["decimals"])


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


func _style_picker(b: OptionButton) -> void:
	b.add_theme_font_override("font", main.font_regular)
	b.add_theme_font_size_override("font_size", 20)


func _small_button(text: String, cb: Callable) -> Button:
	var b := UIKit.make_button(text, main.font_regular, 20)
	b.pressed.connect(cb)
	return b
