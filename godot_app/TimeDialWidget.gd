class_name TimeDialWidget
extends Control

## 24시간 아날로그 다이얼 위젯
## Signals:
##   time_changed(hour: float)  — 0..24, 드래그/입력 시 발생
##   day_rolled(delta: int)     — 자정 교차 시 +1(다음날) / -1(이전날)

signal time_changed(hour: float)
signal day_rolled(delta: int)

var _hour: float = 12.0
var _dragging: bool = false
var _center_edit: LineEdit = null

func _ready() -> void:
	custom_minimum_size = Vector2(160, 160)
	mouse_filter = MOUSE_FILTER_STOP

	_center_edit = LineEdit.new()
	_center_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_edit.flat = true
	_center_edit.add_theme_font_size_override("font_size", 16)
	_center_edit.size = Vector2(74, 30)
	_center_edit.mouse_filter = MOUSE_FILTER_STOP
	_center_edit.text_submitted.connect(_on_submitted)
	_center_edit.focus_exited.connect(func(): _validate(_center_edit.text))
	add_child(_center_edit)
	_sync_label()
	_layout_edit()

func set_hour(h: float) -> void:
	if _dragging:
		return
	_hour = fmod(clampf(h, 0.0, 24.0), 24.0)
	_sync_label()
	queue_redraw()

func _sync_label() -> void:
	if _center_edit and not _center_edit.has_focus():
		_center_edit.text = "%02d:%02d" % [int(_hour), int(fmod(_hour, 1.0) * 60.0)]

func _layout_edit() -> void:
	if _center_edit and size != Vector2.ZERO:
		_center_edit.position = (size - _center_edit.size) / 2.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_edit()
		queue_redraw()

func _on_submitted(text: String) -> void:
	_validate(text)

func _validate(text: String) -> void:
	var colon := text.find(":")
	if colon >= 1:
		var hh := text.substr(0, colon).to_int()
		var mm := text.substr(colon + 1).to_int()
		if hh >= 0 and hh <= 23 and mm >= 0 and mm <= 59:
			_hour = float(hh) + float(mm) / 60.0
			time_changed.emit(_hour)
			queue_redraw()
	_sync_label()
	if _center_edit and _center_edit.has_focus():
		_center_edit.release_focus()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _center_edit and Rect2(_center_edit.position, _center_edit.size).has_point(mb.position):
				return  # LineEdit handles its own click
			if mb.pressed:
				_dragging = true
				_do_drag(mb.position)
			else:
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_do_drag((event as InputEventMouseMotion).position)
		accept_event()

func _do_drag(pos: Vector2) -> void:
	var ctr := size / 2.0
	var v := pos - ctr
	if v.length() < 14.0:
		return
	# angle()=0은 우측, +PI/2면 0h=상단 기준으로 변환
	var ang := fmod(v.angle() + PI / 2.0 + TAU, TAU)
	var nh := ang / TAU * 24.0
	var diff := nh - _hour
	if diff > 20.0:
		day_rolled.emit(-1)   # CCW로 자정 역방향 통과
	elif diff < -20.0:
		day_rolled.emit(1)    # CW로 자정 순방향 통과
	_hour = nh
	_sync_label()
	time_changed.emit(_hour)
	queue_redraw()

func _draw() -> void:
	var ctr := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 5.0
	if r < 24.0:
		return

	# 배경
	draw_circle(ctr, r, Color(0.09, 0.11, 0.18, 0.96))
	draw_arc(ctr, r, 0.0, TAU, 80, Color(0.38, 0.43, 0.60), 2.0, true)

	# 야간 구역 (자정~6시, 18시~자정 = 상반원) 표시
	# draw_arc: 각도 0=우, PI/2=하, PI=좌, -PI/2=상(=TAU*0.75)
	# 상반원 = -PI/2 → PI/2 가는 상단 호 (우→상→좌 = 야간영역)
	draw_arc(ctr, r * 0.86, PI, TAU, 40, Color(0.10, 0.15, 0.35, 0.28), r * 0.08, true)
	# 주간 구역 (6시~18시 = 하반원)
	draw_arc(ctr, r * 0.86, 0.0, PI, 40, Color(0.85, 0.70, 0.20, 0.12), r * 0.08, true)

	# 눈금
	for h in range(24):
		var a := float(h) / 24.0 * TAU - TAU / 4.0  # -PI/2 → 0h=상단
		var d := Vector2(cos(a), sin(a))
		var is_q := (h % 6 == 0)
		var is_t := (h % 3 == 0)
		var tl := r * (0.17 if is_q else (0.10 if is_t else 0.06))
		draw_line(
			ctr + d * (r - tl), ctr + d * r,
			Color(1.0, 1.0, 1.0, 0.85 if is_q else (0.50 if is_t else 0.28)),
			2.0 if is_q else 1.0, true)

	# 시각 레이블 (0, 6, 12, 18)
	var fnt := get_theme_font("font", "Label")
	var fs := clampi(int(r * 0.19), 8, 18)
	for h in [0, 6, 12, 18]:
		var a := float(h) / 24.0 * TAU - TAU / 4.0
		var d := Vector2(cos(a), sin(a))
		var lbl := str(h)
		var tw := fnt.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := ctr + d * (r * 0.73)
		# draw_string 기준점: 왼쪽 baseline → 텍스트 시각적 중심이 lp에 오도록 보정
		draw_string(fnt,
			Vector2(lp.x - tw / 2.0, lp.y + fs * 0.35),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.85, 0.88, 1.0, 0.85))

	# 시침
	var ha := _hour / 24.0 * TAU - TAU / 4.0
	var hd := Vector2(cos(ha), sin(ha))
	draw_line(ctr - hd * r * 0.14, ctr + hd * r * 0.73, Color(1.0, 0.80, 0.22), 3.0, true)
	draw_circle(ctr + hd * r * 0.73, 5.5, Color(1.0, 0.80, 0.22))

	# 중심 캡
	draw_circle(ctr, 6.0, Color(0.22, 0.26, 0.42))
	draw_circle(ctr, 2.8, Color(1.0, 0.80, 0.22))
