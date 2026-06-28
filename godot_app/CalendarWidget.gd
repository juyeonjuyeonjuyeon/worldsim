class_name CalendarWidget
extends VBoxContainer

## 컴팩트 날짜 네비게이터 + 팝업 달력
## Signals:
##   date_changed(year: int, month: int, day: int) — 사용자가 날짜를 바꿀 때

signal date_changed(year: int, month: int, day: int)

var _year: int = 2026
var _month: int = 6
var _day: int = 21
var _picking: bool = false
var _fs: int = 14

var _date_lbl: Label = null
var _popup: PopupPanel = null
var _popup_year: int = 2026
var _popup_month: int = 6
var _cal_hdr: Label = null
var _day_btns: Array[Button] = []

func setup(font_size: int) -> void:
	_fs = font_size

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()

func _exit_tree() -> void:
	if _popup and is_instance_valid(_popup):
		_popup.queue_free()

func set_date(y: int, mo: int, d: int) -> void:
	if _picking:
		return
	_year = y; _month = mo; _day = d
	_update_lbl()

func _update_lbl() -> void:
	if _date_lbl:
		_date_lbl.text = "%04d-%02d-%02d" % [_year, _month, _day]

func _max_day(y: int, m: int) -> int:
	if m in [4, 6, 9, 11]: return 30
	if m == 2: return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
	return 31

func _shift_day(delta: int) -> void:
	var unix := Time.get_unix_time_from_datetime_dict(
		{"year": _year, "month": _month, "day": _day, "hour": 0, "minute": 0, "second": 0})
	unix += float(delta) * 86400.0
	var nd := Time.get_datetime_dict_from_unix_time(int(unix))
	_year = int(nd["year"]); _month = int(nd["month"]); _day = int(nd["day"])
	_update_lbl()
	date_changed.emit(_year, _month, _day)

func _build_ui() -> void:
	var bh := maxi(32, int(_fs * 2.0))

	# 날짜 네비 행
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	var prev_btn := Button.new()
	prev_btn.text = "◀"
	prev_btn.add_theme_font_size_override("font_size", _fs)
	prev_btn.custom_minimum_size = Vector2(bh, bh)
	prev_btn.pressed.connect(func(): _shift_day(-1))
	row.add_child(prev_btn)

	_date_lbl = Label.new()
	_date_lbl.text = "%04d-%02d-%02d" % [_year, _month, _day]
	_date_lbl.add_theme_font_size_override("font_size", _fs)
	_date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_lbl.custom_minimum_size = Vector2(0, bh)
	row.add_child(_date_lbl)

	var next_btn := Button.new()
	next_btn.text = "▶"
	next_btn.add_theme_font_size_override("font_size", _fs)
	next_btn.custom_minimum_size = Vector2(bh, bh)
	next_btn.pressed.connect(func(): _shift_day(1))
	row.add_child(next_btn)

	var cal_btn := Button.new()
	cal_btn.text = "📅"
	cal_btn.add_theme_font_size_override("font_size", _fs)
	cal_btn.custom_minimum_size = Vector2(bh, bh)
	cal_btn.pressed.connect(_open_calendar)
	row.add_child(cal_btn)

	# 팝업 달력 (트리에 추가는 _ready 완료 후 deferred로)
	_popup = PopupPanel.new()
	_popup.popup_hide.connect(func(): _picking = false)
	_popup.min_size = Vector2(230, 0)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 2)
	_popup.add_child(pvb)

	# 팝업 헤더: 月 탐색
	var hdr := HBoxContainer.new()
	pvb.add_child(hdr)

	var pp := Button.new()
	pp.text = "◀"
	pp.add_theme_font_size_override("font_size", _fs)
	pp.custom_minimum_size = Vector2(28, 28)
	pp.pressed.connect(_popup_prev_month)
	hdr.add_child(pp)

	_cal_hdr = Label.new()
	_cal_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cal_hdr.add_theme_font_size_override("font_size", _fs)
	hdr.add_child(_cal_hdr)

	var pn := Button.new()
	pn.text = "▶"
	pn.add_theme_font_size_override("font_size", _fs)
	pn.custom_minimum_size = Vector2(28, 28)
	pn.pressed.connect(_popup_next_month)
	hdr.add_child(pn)

	# 요일 헤더 (월=0)
	var dow_row := HBoxContainer.new()
	pvb.add_child(dow_row)
	for dl in ["월", "화", "수", "목", "금", "토", "일"]:
		var lbl := Label.new()
		lbl.text = dl
		lbl.add_theme_font_size_override("font_size", _fs - 2)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dow_row.add_child(lbl)

	# 날짜 격자 (6행 × 7열 = 42칸)
	var grid := GridContainer.new()
	grid.columns = 7
	pvb.add_child(grid)
	_day_btns.clear()
	for i in range(42):
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", _fs - 2)
		btn.custom_minimum_size = Vector2(28, 28)
		btn.pressed.connect(_on_day_btn.bind(i))
		grid.add_child(btn)
		_day_btns.append(btn)

	call_deferred("_register_popup")

func _register_popup() -> void:
	if is_inside_tree() and _popup:
		get_tree().get_root().add_child(_popup)

func _popup_prev_month() -> void:
	_popup_month -= 1
	if _popup_month < 1:
		_popup_month = 12
		_popup_year -= 1
	_rebuild_grid()

func _popup_next_month() -> void:
	_popup_month += 1
	if _popup_month > 12:
		_popup_month = 1
		_popup_year += 1
	_rebuild_grid()

func _open_calendar() -> void:
	_picking = true
	_popup_year  = _year
	_popup_month = _month
	_rebuild_grid()
	# 팝업을 버튼 아래 세계 좌표에 표시
	var gpos := global_position + Vector2(0.0, size.y)
	_popup.popup(Rect2(gpos, Vector2.ZERO))

func _rebuild_grid() -> void:
	if _cal_hdr:
		_cal_hdr.text = "%d년 %d월" % [_popup_year, _popup_month]

	# 이달 1일의 요일 (0=일…6=토) → 월요일 기준(0=월)으로 변환
	var first_unix := int(Time.get_unix_time_from_datetime_dict(
		{"year": _popup_year, "month": _popup_month, "day": 1,
		 "hour": 0, "minute": 0, "second": 0}))
	var first_dt   := Time.get_datetime_dict_from_unix_time(first_unix)
	var first_wday: int = (int(first_dt["weekday"]) + 6) % 7  # 일(0)→6, 월(1)→0

	var max_d := _max_day(_popup_year, _popup_month)

	for i in range(42):
		var btn := _day_btns[i]
		var day_num := i - first_wday + 1
		if day_num < 1 or day_num > max_d:
			btn.text     = ""
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0)
		else:
			btn.text     = str(day_num)
			btn.disabled = false
			# 현재 선택된 날 강조
			var is_sel := (day_num == _day and _popup_month == _month and _popup_year == _year)
			btn.modulate = Color(1.0, 0.85, 0.2, 1.0) if is_sel else Color(1, 1, 1, 1)

func _on_day_btn(idx: int) -> void:
	if _day_btns[idx].text.is_empty():
		return
	_day   = int(_day_btns[idx].text)
	_year  = _popup_year
	_month = _popup_month
	_popup.hide()
	_picking = false
	_update_lbl()
	date_changed.emit(_year, _month, _day)
