class_name WorldSimUI
extends CanvasLayer

signal settings_confirmed(s: Dictionary)
signal view_mode_requested(mode: String)
signal aspect_requested(ratio: String)
signal test_event_requested(event_name: String)
signal test_toggle_requested(name: String, on: bool)   # 특수현상 켜기/끄기
signal test_param_changed(name: String, value: float)  # 특수현상 강도 슬라이더
signal showcase_restore_requested()                    # 연출 복귀(원래 설정으로)
signal eye_view_requested(enabled: bool)
signal play_state_changed(playing: bool)

const _CFG := "user://window_state.cfg"
const WEATHER_KEYS   := ["CLEAR", "CIRRUS", "CUMULUS", "OVERCAST", "RAIN", "SNOW"]
const WEATHER_LABELS := ["맑음", "얇은 구름", "뭉게구름", "흐림", "비", "눈"]
# 구름 운형(날씨와 독립). AUTO=날씨에서 자동.
const CLOUD_KEYS   := ["AUTO", "NONE", "CIRRUS", "CIRROCUMULUS", "ALTOCUMULUS", "CUMULUS", "STRATOCUMULUS", "STRATUS", "NIMBOSTRATUS", "CUMULONIMBUS"]
const CLOUD_LABELS := ["자동", "없음", "새털구름(권운)", "비늘구름(권적운)", "양떼구름(고적운)", "뭉게구름(적운)", "층적운", "층운", "비구름(난층운)", "먹구름(적란운)"]

var font_scale: float  = 2.0
var panel_w_saved: int = 0
var panel_h_saved: int = 0

var _cur_scale: float       = 2.0
var _pending := {}
var _fs: int                = 16
var _slider_h: int          = 20
var _panel: Panel           = null
var _tab: TabContainer      = null
var _handle: Control        = null
var _resizing: bool         = false
var status_label: Label     = null
var _play_btn: Button       = null
var _playing: bool          = true
var _pending_font_scale: float = 2.0

# 날짜/시간 위젯 참조
var _day_sl: HSlider  = null   # 구형 슬라이더 (null 유지)
var _day_lbl: Label   = null
var _cur_month: int   = 6
var _cur_year: int    = 2026
var _cur_day: int     = 21
var _time_dial: TimeDialWidget  = null
var _cal_widget: CalendarWidget = null

# UTC 슬라이더 자동계산용
var _utc_sl: HSlider  = null
var _utc_lbl: Label   = null

# 자동 날씨 모드에서 비활성화할 컨트롤 목록
var _auto_wx_controls: Array = []

# ── 저장 / 복원 ──────────────────────────────────────────────────────
func load_state(window: Window) -> void:
	var cfg := ConfigFile.new()
	var ok   := cfg.load(_CFG) == OK
	var saved_size := Vector2i(0, 0)
	if ok:
		saved_size    = cfg.get_value("window", "size",       Vector2i(0, 0))
		font_scale    = cfg.get_value("ui",     "font_scale", 2.0)
		panel_w_saved = cfg.get_value("ui",     "panel_w",    0)
		panel_h_saved = cfg.get_value("ui",     "panel_h",    0)
	if saved_size.y < 900:
		var scr       := DisplayServer.screen_get_size()
		window.size     = Vector2i(int(scr.x * 0.55), int(scr.y * 0.85))
		window.position = Vector2i(int(scr.x * 0.05), int(scr.y * 0.05))
	else:
		window.size     = saved_size
		window.position = cfg.get_value("window", "position", Vector2i(100, 100))

func save_state(window: Window) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("window", "position",   window.position)
	cfg.set_value("window", "size",       window.size)
	cfg.set_value("ui",     "font_scale", font_scale)
	cfg.set_value("ui",     "panel_w",    panel_w_saved)
	cfg.set_value("ui",     "panel_h",    panel_h_saved)
	cfg.save(_CFG)

# ── 빌드 / 리빌드 ────────────────────────────────────────────────────
func build(init: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	_build_all(init)

func update_status(text: String) -> void:
	if status_label:
		status_label.text = text

# 검수용: 탭 인덱스 선택 (0=날씨 1=시간 2=위치 3=카메라 4=테스트)
func select_tab(idx: int) -> void:
	if _tab and idx >= 0 and idx < _tab.get_tab_count():
		_tab.current_tab = idx

func update_time_ui(dt: Dictionary) -> void:
	var y  := int(dt.get("year",  _cur_year))
	var mo := int(dt.get("month", _cur_month))
	var d  := int(dt.get("day",   _cur_day))
	var h  := float(dt.get("hour", 12.0))
	_cur_year  = y; _cur_month = mo; _cur_day = d
	_pending["sim_year"]    = y
	_pending["sim_month"]   = mo
	_pending["sim_day"]     = d
	_pending["time_of_day"] = h
	if _time_dial:
		_time_dial.set_hour(h)
	if _cal_widget:
		_cal_widget.set_date(y, mo, d)

func set_playing(playing: bool) -> void:
	_playing = playing
	if _play_btn:
		_play_btn.text = "⏸" if _playing else "▶"

# ── 즉시 반영 ────────────────────────────────────────────────────────
func _apply() -> void:
	settings_confirmed.emit(_pending.duplicate())
	_pending["_reset_elapsed"] = false

# ── 입력 (스페이스바, 리사이즈) ──────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_playing = not _playing
			play_state_changed.emit(_playing)
			if _play_btn:
				_play_btn.text = "⏸" if _playing else "▶"
			get_viewport().set_input_as_handled()
			return

	if not _resizing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_resizing = false
		save_state(get_window())
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _panel:
		var mouse     := get_viewport().get_mouse_position()
		var vp        := get_viewport().get_visible_rect().size
		var panel_top := int(_panel.position.y)
		var panel_x   := int(_panel.position.x)
		var new_w := clampi(int(mouse.x) - panel_x, 120, int(vp.x * 0.8))
		var new_h := clampi(int(mouse.y) - panel_top, 100, int(vp.y) - panel_top - int(8 * _cur_scale))
		_resize(new_w, new_h)
		get_viewport().set_input_as_handled()

func _resize(new_w: int, new_h: int) -> void:
	if not _panel:
		return
	_panel.size = Vector2(new_w, new_h)
	var hsz := int(20 * _cur_scale)
	if _handle:
		_handle.position = Vector2(new_w - hsz, new_h - hsz)
	var inner_w := new_w - int(12 * _cur_scale)
	if _tab:
		_tab.size = Vector2(inner_w, new_h - int(12 * _cur_scale))
	panel_w_saved = new_w
	panel_h_saved = new_h

# ── 일 최대값 계산 ────────────────────────────────────────────────────
func _max_day(year: int, month: int) -> int:
	if month in [4, 6, 9, 11]:
		return 30
	if month == 2:
		return 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28
	return 31

func _update_day_max() -> void:
	if not _day_sl:
		return
	var max_d := _max_day(_cur_year, _cur_month)
	_day_sl.max_value = float(max_d)
	var cur_d: int = _pending.get("sim_day", 1)
	if cur_d > max_d:
		_pending["sim_day"] = max_d
		_day_sl.value = float(max_d)
		if _day_lbl:
			_day_lbl.text = "일: %d" % max_d

# ── 탭 페이지 생성 헬퍼 ──────────────────────────────────────────────
func _make_tab(tab: TabContainer, name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name                   = name
	sc.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return vb

# ── 전체 UI 구성 ─────────────────────────────────────────────────────
func _build_all(init: Dictionary) -> void:
	var vp: Vector2   = get_viewport().get_visible_rect().size
	var s: float      = clampf(font_scale, 0.5, 4.0)
	_cur_scale         = s
	_pending_font_scale = font_scale

	var bar_h: int    = int(44 * s)
	var fs_top: int   = maxi(12, int(15 * s))
	var fs_label: int = maxi(12, int(16 * s))
	var fs_ctrl: int  = maxi(11, int(15 * s))
	var pad: int      = maxi(6,  int(12 * s))
	var panel_y: int  = bar_h + int(8 * s)
	var def_w: int    = mini(int(340 * s), int(vp.x * 0.42))
	var def_h: int    = int(vp.y) - panel_y - int(8 * s)
	var panel_w: int  = panel_w_saved if panel_w_saved > 0 else def_w
	var panel_h: int  = panel_h_saved if panel_h_saved > 0 else def_h
	var btn_w: int    = int(100 * s)
	_fs       = fs_label
	_slider_h = maxi(12, int(20 * s))

	_cur_month = init.get("sim_month", 6)
	_cur_year  = init.get("sim_year",  2026)
	_cur_day   = init.get("sim_day",   21)

	# ── 상단 바 ──────────────────────────────────────────────
	var top_bar := Panel.new()
	top_bar.anchor_right  = 1.0
	top_bar.offset_bottom = bar_h
	add_child(top_bar)

	var top_hb := HBoxContainer.new()
	top_hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_bar.add_child(top_hb)

	var lpad := Control.new()
	lpad.custom_minimum_size = Vector2(pad, 0)
	top_hb.add_child(lpad)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", fs_top)
	top_hb.add_child(status_label)

	_play_btn = Button.new()
	_play_btn.text = "⏸" if _playing else "▶"
	_play_btn.add_theme_font_size_override("font_size", fs_top)
	_play_btn.custom_minimum_size = Vector2(int(52 * s), 0)
	_play_btn.pressed.connect(func():
		_playing = not _playing
		play_state_changed.emit(_playing)
		_play_btn.text = "⏸" if _playing else "▶"
	)
	top_hb.add_child(_play_btn)

	var settings_btn := Button.new()
	settings_btn.text = "⚙  설정"
	settings_btn.add_theme_font_size_override("font_size", fs_top)
	settings_btn.custom_minimum_size = Vector2(btn_w, 0)
	top_hb.add_child(settings_btn)

	# ── 파라미터 패널 ────────────────────────────────────────
	var panel := Panel.new()
	panel.position      = Vector2(int(8 * s), panel_y)
	panel.size          = Vector2(panel_w, panel_h)
	panel.clip_contents = true
	add_child(panel)

	var ui_theme := Theme.new()
	ui_theme.set_font_size("font_size", "Label",        fs_label)
	ui_theme.set_font_size("font_size", "Button",       fs_ctrl)
	ui_theme.set_font_size("font_size", "OptionButton", fs_ctrl)
	ui_theme.set_font_size("font_size", "CheckBox",     fs_ctrl)
	ui_theme.set_font_size("font_size", "TabContainer", fs_ctrl)

	# 슬라이더: 채워진 영역 파란색 강조 + 트랙 두께
	var sl_fill := StyleBoxFlat.new()
	sl_fill.bg_color = Color(0.22, 0.50, 0.90, 0.88)
	sl_fill.set_corner_radius_all(3)
	sl_fill.content_margin_top    = 3.0
	sl_fill.content_margin_bottom = 3.0
	var sl_bg := StyleBoxFlat.new()
	sl_bg.bg_color = Color(0.14, 0.15, 0.20, 0.82)
	sl_bg.set_corner_radius_all(3)
	sl_bg.content_margin_top    = 3.0
	sl_bg.content_margin_bottom = 3.0
	ui_theme.set_stylebox("grabber_area",           "HSlider", sl_fill)
	ui_theme.set_stylebox("grabber_area_highlight", "HSlider", sl_fill)
	ui_theme.set_stylebox("slider",                 "HSlider", sl_bg)

	# 버튼: 둥근 모서리 + 테두리
	var mk_btn := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(5)
		sb.border_width_left   = 1; sb.border_width_right  = 1
		sb.border_width_top    = 1; sb.border_width_bottom = 1
		sb.border_color = border
		sb.content_margin_left = 8.0; sb.content_margin_right  = 8.0
		sb.content_margin_top  = 4.0; sb.content_margin_bottom = 4.0
		return sb
	var btn_n: StyleBoxFlat = mk_btn.call(Color(0.20, 0.22, 0.28, 0.95), Color(0.35, 0.38, 0.50))
	var btn_h: StyleBoxFlat = mk_btn.call(Color(0.27, 0.30, 0.42, 0.95), Color(0.44, 0.54, 0.82))
	var btn_p: StyleBoxFlat = mk_btn.call(Color(0.18, 0.36, 0.70, 0.95), Color(0.44, 0.54, 0.82))
	for cls in ["Button", "OptionButton"]:
		ui_theme.set_stylebox("normal",   cls, btn_n)
		ui_theme.set_stylebox("hover",    cls, btn_h)
		ui_theme.set_stylebox("pressed",  cls, btn_p)
		ui_theme.set_stylebox("focus",    cls, btn_h)
	# 토글 버튼 눌린 상태
	ui_theme.set_stylebox("pressed",        "Button", btn_p)
	# 폰트 색
	for cls in ["Button", "OptionButton"]:
		ui_theme.set_color("font_color",         cls, Color(0.87, 0.90, 0.96))
		ui_theme.set_color("font_hover_color",   cls, Color(1.0,  1.0,  1.0))
		ui_theme.set_color("font_pressed_color", cls, Color(1.0,  1.0,  1.0))
	ui_theme.set_color("font_color", "CheckBox", Color(0.87, 0.90, 0.96))
	# 드롭다운 팝업 항목 폰트
	ui_theme.set_font_size("font_size", "PopupMenu", fs_ctrl)
	ui_theme.set_color("font_color",       "PopupMenu", Color(0.87, 0.90, 0.96))
	ui_theme.set_color("font_hover_color", "PopupMenu", Color(1.0, 1.0, 1.0))

	panel.theme = ui_theme

	var inner_w: int = panel_w - int(12 * s)

	var tab := TabContainer.new()
	tab.position               = Vector2(int(6 * s), int(6 * s))
	tab.size                   = Vector2(inner_w, panel_h - int(12 * s))
	tab.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	panel.add_child(tab)
	_tab   = tab
	_panel = panel

	# ── 리사이즈 핸들 ────────────────────────────────────────
	var hsz    := int(20 * s)
	var handle := Panel.new()
	handle.position                   = Vector2(panel_w - hsz, panel_h - hsz)
	handle.size                       = Vector2(hsz, hsz)
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.mouse_filter               = Control.MOUSE_FILTER_STOP
	handle.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_resizing = ev.pressed
			if not ev.pressed:
				save_state(get_window())
	)
	panel.add_child(handle)
	_handle = handle

	# ── pending 초기화 ────────────────────────────────────────
	_pending = {
		"font_scale":          font_scale,
		"weather_type":        init.get("weather_type",        "RAIN"),
		"rain_rate":           init.get("rain_rate",           20.0),
		"overcast_intensity":  init.get("overcast_intensity",  0.6),
		"wind_enabled":        init.get("wind_enabled",        true),
		"wind_speed":          init.get("wind_speed",          1.6),
		"wind_direction":      init.get("wind_direction",      0.0),
		"latitude":            init.get("latitude",            37.5665),
		"longitude":           init.get("longitude",           126.978),
		"utc_offset":          init.get("utc_offset",          9.0),
		"sim_year":            init.get("sim_year",            2026),
		"sim_month":           init.get("sim_month",           6),
		"sim_day":             init.get("sim_day",             21),
		"time_of_day":         init.get("time_of_day",         12.0),
		"real_time_mode":      init.get("real_time_mode",      false),
		"day_length_sec":      init.get("day_length_sec",      120.0),
		"rain_streak_scale":   init.get("rain_streak_scale",   1.0),
		"snow_size_scale":     init.get("snow_size_scale",     1.0),
		"show_constellations": init.get("show_constellations", false),
		"use_fahrenheit":      init.get("use_fahrenheit",      false),
		"auto_weather":        init.get("auto_weather",        false),
		"_reset_elapsed":      false,
	}

	var check_h: int = maxi(24, int(fs_ctrl * 1.6))

	# ═════════════════════════════════════════════════════════
	# 탭 1: 날씨
	# ═════════════════════════════════════════════════════════
	var vb_w := _make_tab(tab, "날씨")

	# 자동 날씨 토글
	var is_auto: bool = init.get("auto_weather", false)
	var auto_wx_check := CheckBox.new()
	auto_wx_check.text           = "자동 날씨 (위도·날짜 기반)"
	auto_wx_check.button_pressed = is_auto
	auto_wx_check.add_theme_font_size_override("font_size", fs_ctrl)
	auto_wx_check.custom_minimum_size = Vector2(0, check_h)
	vb_w.add_child(auto_wx_check)
	vb_w.add_child(HSeparator.new())

	var weather_opt := OptionButton.new()
	weather_opt.add_theme_font_size_override("font_size", fs_ctrl)
	weather_opt.get_popup().add_theme_font_size_override("font_size", fs_ctrl)
	for w in WEATHER_LABELS:
		weather_opt.add_item(w)
	weather_opt.select(maxi(0, WEATHER_KEYS.find(init.get("weather_type", "RAIN"))))
	vb_w.add_child(_labeled("날씨", weather_opt))

	var rain_row       := _slider_row("강수강도", 0.5, 60.0, init.get("rain_rate", 20.0),
		func(v): _pending["rain_rate"] = v)
	var rain_stk_row   := _slider_row("빗줄기 크기", 0.3, 2.5, init.get("rain_streak_scale", 1.0),
		func(v): _pending["rain_streak_scale"] = v)
	var snow_sz_row    := _slider_row("눈송이 크기", 0.3, 2.5, init.get("snow_size_scale", 1.0),
		func(v): _pending["snow_size_scale"] = v)
	var overcast_row   := _slider_row("흐림 정도", 0.0, 1.0, init.get("overcast_intensity", 0.6),
		func(v): _pending["overcast_intensity"] = v)
	vb_w.add_child(rain_row)
	vb_w.add_child(rain_stk_row)
	vb_w.add_child(snow_sz_row)
	vb_w.add_child(overcast_row)

	var refresh_weather := func():
		var wt: String = _pending.get("weather_type", "CLEAR")
		rain_row.visible     = wt == "RAIN" or wt == "SNOW"
		rain_stk_row.visible = wt == "RAIN"
		snow_sz_row.visible  = wt == "SNOW"
		overcast_row.visible = wt == "OVERCAST"
	weather_opt.item_selected.connect(func(idx):
		_pending["weather_type"] = WEATHER_KEYS[idx]
		refresh_weather.call()
		_apply()
	)
	refresh_weather.call()

	# 자동 날씨 모드: 날씨 타입·강수강도·흐림 컨트롤 비활성화
	_auto_wx_controls = [weather_opt]
	for row: Control in [rain_row, overcast_row]:
		for ch in row.get_children():
			if ch is HSlider:
				_auto_wx_controls.append(ch as HSlider)
	_toggle_weather_controls(not is_auto)
	auto_wx_check.toggled.connect(func(p: bool):
		_pending["auto_weather"] = p
		_toggle_weather_controls(not p)
		_apply()
	)

	# ── 구름 (비/눈과 독립: 운형 + 운량 + 프리셋) ──
	vb_w.add_child(HSeparator.new())
	var cloud_opt := OptionButton.new()
	cloud_opt.add_theme_font_size_override("font_size", fs_ctrl)
	cloud_opt.get_popup().add_theme_font_size_override("font_size", fs_ctrl)
	for cl in CLOUD_LABELS:
		cloud_opt.add_item(cl)
	cloud_opt.select(0)   # 자동
	vb_w.add_child(_labeled("구름", cloud_opt))
	var cloudcov_row := _slider_row("운량(%)", 0.0, 100.0, 60.0,
		func(v): _pending["cloud_coverage"] = v / 100.0)
	vb_w.add_child(cloudcov_row)
	cloud_opt.item_selected.connect(func(idx):
		_pending["cloud_type"] = CLOUD_KEYS[idx]
		# 자동이면 운량 슬라이더 무시(<0), 아니면 슬라이더값 사용
		cloudcov_row.visible = idx != 0
		_apply()
	)
	cloudcov_row.visible = false   # 자동일 땐 숨김
	# 프리셋 버튼: 누르면 운형 드롭다운+운량을 그 값으로
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", maxi(2, int(4 * s)))
	for pr: Array in [["새털", "CIRRUS", 55], ["뭉게", "CUMULUS", 45], ["양떼", "ALTOCUMULUS", 70], ["먹구름", "CUMULONIMBUS", 90]]:
		var pbtn := Button.new()
		pbtn.text = pr[0]
		pbtn.add_theme_font_size_override("font_size", fs_ctrl)
		pbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pkey: String = pr[1]
		var pcov: float  = float(pr[2])
		pbtn.pressed.connect(func():
			var ki: int = CLOUD_KEYS.find(pkey)
			cloud_opt.select(ki)
			cloudcov_row.visible = true
			_pending["cloud_type"] = pkey
			_pending["cloud_coverage"] = pcov / 100.0
			_apply()
		)
		preset_row.add_child(pbtn)
	vb_w.add_child(preset_row)

	var const_check := CheckBox.new()
	const_check.text           = "별자리 선 표시"
	const_check.button_pressed = init.get("show_constellations", false)
	const_check.add_theme_font_size_override("font_size", fs_ctrl)
	const_check.custom_minimum_size = Vector2(0, check_h)
	const_check.toggled.connect(func(p): _pending["show_constellations"] = p; _apply())
	vb_w.add_child(const_check)

	var trail_check := CheckBox.new()
	trail_check.text           = "태양/달 궤적"
	trail_check.button_pressed = init.get("show_trails", false)
	trail_check.add_theme_font_size_override("font_size", fs_ctrl)
	trail_check.custom_minimum_size = Vector2(0, check_h)
	trail_check.toggled.connect(func(p): _pending["show_trails"] = p; _apply())
	vb_w.add_child(trail_check)

	vb_w.add_child(HSeparator.new())

	var wind_check := CheckBox.new()
	wind_check.text           = "바람"
	wind_check.button_pressed = init.get("wind_enabled", true)
	wind_check.add_theme_font_size_override("font_size", fs_ctrl)
	wind_check.custom_minimum_size = Vector2(0, check_h)
	wind_check.toggled.connect(func(p): _pending["wind_enabled"] = p; _apply())
	vb_w.add_child(wind_check)
	vb_w.add_child(_slider_row("바람 속도",    0.0,   12.0, init.get("wind_speed",     1.6),
		func(v): _pending["wind_speed"]     = v))
	vb_w.add_child(_slider_row("바람 방향(°)", 0.0,  360.0, init.get("wind_direction", 0.0),
		func(v): _pending["wind_direction"] = v))

	# ═════════════════════════════════════════════════════════
	# 탭 2: 시간
	# ═════════════════════════════════════════════════════════
	var vb_t := _make_tab(tab, "시간")

	# ── 달력 위젯 (날짜 선택) ───────────────────────────
	_cal_widget = CalendarWidget.new()
	_cal_widget.setup(fs_ctrl)
	_cal_widget.set_date(_cur_year, _cur_month, _cur_day)
	_cal_widget.date_changed.connect(func(y: int, mo: int, d: int):
		_cur_year  = y; _cur_month = mo; _cur_day = d
		_pending["sim_year"]       = y
		_pending["sim_month"]      = mo
		_pending["sim_day"]        = d
		_pending["_reset_elapsed"] = true
		_apply()
	)
	vb_t.add_child(_cal_widget)

	# ── 24h 아날로그 다이얼 ──────────────────────────
	var dial_center := CenterContainer.new()
	dial_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb_t.add_child(dial_center)

	_time_dial = TimeDialWidget.new()
	_time_dial.custom_minimum_size   = Vector2(160, 160)
	_time_dial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_dial.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_time_dial.set_hour(init.get("time_of_day", 12.0))
	_time_dial.time_changed.connect(func(h: float):
		_pending["time_of_day"]    = h
		_pending["_reset_elapsed"] = true
		_apply()
	)
	_time_dial.day_rolled.connect(func(delta: int):
		var unix := Time.get_unix_time_from_datetime_dict(
			{"year": _cur_year, "month": _cur_month, "day": _cur_day,
			 "hour": 0, "minute": 0, "second": 0})
		unix += float(delta) * 86400.0
		var nd := Time.get_datetime_dict_from_unix_time(int(unix))
		_cur_year  = int(nd["year"]); _cur_month = int(nd["month"]); _cur_day = int(nd["day"])
		_pending["sim_year"]  = _cur_year
		_pending["sim_month"] = _cur_month
		_pending["sim_day"]   = _cur_day
		if _cal_widget:
			_cal_widget.set_date(_cur_year, _cur_month, _cur_day)
		# time_changed가 뒤이어 _apply()를 호출하므로 여기선 생략
	)
	dial_center.add_child(_time_dial)

	vb_t.add_child(HSeparator.new())

	var rt_check := CheckBox.new()
	rt_check.text           = "재생으로 시간 자동 진행"
	rt_check.button_pressed = init.get("real_time_mode", false)
	rt_check.add_theme_font_size_override("font_size", fs_ctrl)
	rt_check.custom_minimum_size = Vector2(0, check_h)
	rt_check.toggled.connect(func(p): _pending["real_time_mode"] = p; _apply())
	vb_t.add_child(rt_check)

	# 하루 길이 슬라이더 + 1:1 실제속도 체크박스
	var dl_init: float   = init.get("day_length_sec", 120.0)
	var is_real: bool    = dl_init >= 86000.0
	var dl_vbox := VBoxContainer.new()
	dl_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dl_lbl := Label.new()
	dl_lbl.add_theme_font_size_override("font_size", _fs)
	dl_lbl.text = _speed_text(dl_init)
	dl_vbox.add_child(dl_lbl)
	var dl_sl := HSlider.new()
	dl_sl.min_value             = 5.0
	dl_sl.max_value             = 600.0
	dl_sl.step                  = (600.0 - 5.0) / 500.0
	dl_sl.value                 = clampf(dl_init if not is_real else 120.0, 5.0, 600.0)
	dl_sl.custom_minimum_size   = Vector2(0, _slider_h)
	dl_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl_sl.editable              = not is_real
	dl_sl.value_changed.connect(func(v):
		_pending["day_length_sec"] = v
		dl_lbl.text = _speed_text(v)
		_apply()
	)
	dl_vbox.add_child(dl_sl)
	var rs_check := CheckBox.new()
	rs_check.text           = "1:1 실제 속도"
	rs_check.button_pressed = is_real
	rs_check.add_theme_font_size_override("font_size", fs_ctrl)
	rs_check.custom_minimum_size = Vector2(0, check_h)
	rs_check.toggled.connect(func(checked):
		if checked:
			_pending["day_length_sec"] = 86400.0
			dl_sl.editable = false
			dl_lbl.text = _speed_text(86400.0)
		else:
			_pending["day_length_sec"] = dl_sl.value
			dl_sl.editable = true
			dl_lbl.text = _speed_text(dl_sl.value)
		_apply()
	)
	dl_vbox.add_child(rs_check)
	vb_t.add_child(dl_vbox)

	# ═════════════════════════════════════════════════════════
	# 탭 3: 위치
	# ═════════════════════════════════════════════════════════
	var vb_l := _make_tab(tab, "위치")

	vb_l.add_child(_slider_row("위도",  -90.0,  90.0, init.get("latitude",  37.5665),
		func(v): _pending["latitude"]  = v))
	vb_l.add_child(_slider_row("경도", -180.0, 180.0, init.get("longitude", 126.978),
		func(v): _pending["longitude"] = v))

	# UTC오프셋 + 자동 계산 버튼
	var utc_box := VBoxContainer.new()
	utc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var utc_lbl := Label.new()
	utc_lbl.text = "UTC오프셋: %+.1f" % init.get("utc_offset", 9.0)
	utc_lbl.add_theme_font_size_override("font_size", _fs)
	utc_box.add_child(utc_lbl)
	var utc_sl := HSlider.new()
	utc_sl.min_value             = -12.0
	utc_sl.max_value             = 14.0
	utc_sl.step                  = 0.5
	utc_sl.value                 = init.get("utc_offset", 9.0)
	utc_sl.custom_minimum_size   = Vector2(0, _slider_h)
	utc_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utc_sl.value_changed.connect(func(v):
		_pending["utc_offset"] = v
		utc_lbl.text = "UTC오프셋: %+.1f" % v
		_apply()
	)
	utc_box.add_child(utc_sl)
	var auto_utc_btn := Button.new()
	auto_utc_btn.text = "경도에서 자동 계산"
	auto_utc_btn.add_theme_font_size_override("font_size", fs_ctrl)
	auto_utc_btn.pressed.connect(func():
		var lon: float  = _pending.get("longitude", 0.0)
		var utc: float  = clampf(round(lon / 15.0 * 2.0) / 2.0, -12.0, 14.0)
		_pending["utc_offset"] = utc
		utc_sl.value = utc
		utc_lbl.text = "UTC오프셋: %+.1f" % utc
		_apply()
	)
	utc_box.add_child(auto_utc_btn)
	_utc_sl  = utc_sl
	_utc_lbl = utc_lbl
	vb_l.add_child(utc_box)

	# ═════════════════════════════════════════════════════════
	# 탭 4: 카메라
	# ═════════════════════════════════════════════════════════
	var vb_c := _make_tab(tab, "카메라")

	var view_row   := HBoxContainer.new()
	var view_group := ButtonGroup.new()
	var cur_view: String = init.get("view_mode", "NORMAL")
	for vm: Array in [["일반뷰", "NORMAL"], ["하늘뷰", "SKY"], ["땅뷰", "GROUND"]]:
		var vbtn := Button.new()
		vbtn.text          = vm[0]
		vbtn.toggle_mode   = true
		vbtn.button_group  = view_group
		if vm[1] == cur_view:
			vbtn.button_pressed = true
		vbtn.pressed.connect(func(): view_mode_requested.emit(vm[1]))
		view_row.add_child(vbtn)
	vb_c.add_child(_labeled("시점", view_row))

	var eye_row   := HBoxContainer.new()
	var eye_group := ButtonGroup.new()
	var cur_eye: bool = init.get("eye_view", true)
	for em: Array in [["사람눈", true], ["카메라", false]]:
		var ebtn := Button.new()
		ebtn.text         = em[0]
		ebtn.toggle_mode  = true
		ebtn.button_group = eye_group
		if em[1] == cur_eye:
			ebtn.button_pressed = true
		ebtn.pressed.connect(func(): eye_view_requested.emit(em[1]))
		eye_row.add_child(ebtn)
	vb_c.add_child(_labeled("뷰 모드", eye_row))

	var aspect_row := HBoxContainer.new()
	for ar: String in ["16:9", "9:16", "1:1"]:
		var abtn := Button.new()
		abtn.text = ar
		abtn.pressed.connect(func(): aspect_requested.emit(ar))
		aspect_row.add_child(abtn)
	vb_c.add_child(_labeled("화면비율", aspect_row))

	var fahr_check := CheckBox.new()
	fahr_check.text           = "온도 단위: 화씨(°F)"
	fahr_check.button_pressed = init.get("use_fahrenheit", false)
	fahr_check.add_theme_font_size_override("font_size", fs_ctrl)
	fahr_check.custom_minimum_size = Vector2(0, check_h)
	fahr_check.toggled.connect(func(p): _pending["use_fahrenheit"] = p; _apply())
	vb_c.add_child(fahr_check)

	vb_c.add_child(HSeparator.new())

	# 글자 크기: 별도 "적용" 버튼 (UI 재구성 필요해서 즉시 반영 제외)
	var font_box := VBoxContainer.new()
	font_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var font_lbl := Label.new()
	font_lbl.text = "글자 크기: %.2f" % font_scale
	font_lbl.add_theme_font_size_override("font_size", _fs)
	font_box.add_child(font_lbl)
	var font_sl := HSlider.new()
	font_sl.min_value             = 0.5
	font_sl.max_value             = 4.0
	font_sl.step                  = (4.0 - 0.5) / 500.0
	font_sl.value                 = font_scale
	font_sl.custom_minimum_size   = Vector2(0, _slider_h)
	font_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_sl.value_changed.connect(func(v):
		_pending_font_scale = v
		font_lbl.text = "글자 크기: %.2f" % v
	)
	font_box.add_child(font_sl)
	var font_apply_btn := Button.new()
	font_apply_btn.text = "글자 크기 적용 (UI 재구성)"
	font_apply_btn.add_theme_font_size_override("font_size", fs_ctrl)
	font_apply_btn.pressed.connect(func():
		_pending["font_scale"] = _pending_font_scale
		_apply()
	)
	font_box.add_child(font_apply_btn)
	vb_c.add_child(font_box)

	vb_c.add_child(HSeparator.new())

	var cam_help := Label.new()
	cam_help.text = (
		"우클릭: 시점모드 켜기/끄기 (Esc 해제)\n"
		+ "WASD: 이동, Ctrl: 빠른 이동\n"
		+ "스크롤: 화각 조절, F: 화각 초기화\n"
		+ "Space: 재생 / 정지"
	)
	cam_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	cam_help.add_theme_font_size_override("font_size", fs_label)
	vb_c.add_child(cam_help)

	# ═════════════════════════════════════════════════════════
	# 탭 5: 테스트
	# ═════════════════════════════════════════════════════════
	var vb_test := _make_tab(tab, "테스트")

	# ── 순간 이벤트 (한 번 발생) ──
	var ev_lbl := Label.new()
	ev_lbl.text = "순간 이벤트"
	ev_lbl.add_theme_font_size_override("font_size", _fs)
	vb_test.add_child(ev_lbl)
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", maxi(2, int(4 * s)))
	for pair: Array in [["번개", "lightning"], ["별똥별", "meteor"], ["유성우", "shower"]]:
		var tbtn := Button.new()
		tbtn.text                  = pair[0]
		tbtn.add_theme_font_size_override("font_size", fs_ctrl)
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ename: String = pair[1]
		tbtn.pressed.connect(func(): test_event_requested.emit(ename))
		test_row.add_child(tbtn)
	vb_test.add_child(test_row)
	vb_test.add_child(HSeparator.new())

	# ── 지속 특수현상 (체크박스 켜기/끄기 + 강도 슬라이더) ──
	var sp_lbl := Label.new()
	sp_lbl.text = "특수현상 (켜기/끄기 + 강도)"
	sp_lbl.add_theme_font_size_override("font_size", _fs)
	vb_test.add_child(sp_lbl)
	# 오로라: 토글 + KP(색·강도) 슬라이더
	vb_test.add_child(_phenomenon_toggle("오로라", "aurora"))
	vb_test.add_child(_phenomenon_slider("  KP 지수", 0.0, 9.0, 5.0, "aurora_kp", 0.1))
	# 일식: 토글 + 진행도
	vb_test.add_child(_phenomenon_toggle("일식 (개기↔부분)", "solar_eclipse"))
	vb_test.add_child(_phenomenon_slider("  진행도", 0.0, 1.0, 1.0, "solar_t", 0.01))
	# 월식: 토글 + 진행도
	vb_test.add_child(_phenomenon_toggle("월식 (블러드문)", "lunar_eclipse"))
	vb_test.add_child(_phenomenon_slider("  진행도", 0.0, 1.0, 1.0, "lunar_t", 0.01))
	# 블루문·무지개·혜성: 토글만
	vb_test.add_child(_phenomenon_toggle("블루문", "blue_moon"))
	vb_test.add_child(_phenomenon_toggle("무지개", "rainbow"))
	vb_test.add_child(_phenomenon_toggle("혜성", "comet"))
	# 연출 복귀: 현상 켜면 그 조건(시각·위도·날씨·카메라)으로 이동 → 이 버튼으로 원상복구
	vb_test.add_child(HSeparator.new())
	var restore_btn := Button.new()
	restore_btn.text = "↩ 원래 설정으로 복귀"
	restore_btn.add_theme_font_size_override("font_size", fs_ctrl)
	restore_btn.pressed.connect(func(): showcase_restore_requested.emit())
	vb_test.add_child(restore_btn)

	settings_btn.pressed.connect(func(): panel.visible = not panel.visible)

# ── 특수현상 헬퍼 ────────────────────────────────────────────────────
func _phenomenon_toggle(text: String, name: String) -> Control:
	var cb := CheckBox.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", _fs)
	cb.toggled.connect(func(on: bool): test_toggle_requested.emit(name, on))
	return cb

func _phenomenon_slider(text: String, lo: float, hi: float, val: float, name: String, step: float) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = "%s: %.2f" % [text, val]
	l.add_theme_font_size_override("font_size", _fs)
	box.add_child(l)
	var sl := HSlider.new()
	sl.min_value             = lo
	sl.max_value             = hi
	sl.step                  = step
	sl.value                 = val
	sl.custom_minimum_size   = Vector2(0, _slider_h)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v):
		test_param_changed.emit(name, v)
		l.text = "%s: %.2f" % [text, v]
	)
	box.add_child(sl)
	return box

# ── 헬퍼 ─────────────────────────────────────────────────────────────
func _labeled(text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs)
	box.add_child(l)
	box.add_child(control)
	return box

func _int_slider_row(text: String, lo: int, hi: int, val: int, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = "%s: %d" % [text, val]
	l.add_theme_font_size_override("font_size", _fs)
	box.add_child(l)
	var sl := HSlider.new()
	sl.min_value             = float(lo)
	sl.max_value             = float(hi)
	sl.step                  = 1.0
	sl.value                 = float(val)
	sl.custom_minimum_size   = Vector2(0, _slider_h)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v):
		on_change.call(int(v))
		l.text = "%s: %d" % [text, int(v)]
		_apply()
	)
	box.add_child(sl)
	return box

func _slider_row(text: String, lo: float, hi: float, val: float, on_change: Callable, step: float = -1.0) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = "%s: %.2f" % [text, val]
	l.add_theme_font_size_override("font_size", _fs)
	box.add_child(l)
	var sl := HSlider.new()
	sl.min_value             = lo
	sl.max_value             = hi
	sl.step                  = step if step > 0.0 else (hi - lo) / 500.0
	sl.value                 = val
	sl.custom_minimum_size   = Vector2(0, _slider_h)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v):
		on_change.call(v)
		l.text = "%s: %.2f" % [text, v]
		_apply()
	)
	box.add_child(sl)
	return box

func _toggle_weather_controls(enabled: bool) -> void:
	for ctrl in _auto_wx_controls:
		if ctrl is OptionButton:
			(ctrl as OptionButton).disabled = not enabled
		elif ctrl is HSlider:
			(ctrl as HSlider).editable = enabled
		if ctrl is Control:
			(ctrl as Control).modulate.a = 1.0 if enabled else 0.45

static func _speed_text(day_sec: float) -> String:
	if day_sec >= 86000.0:
		return "하루 길이: 86400초/일 (실제속도 1×)"
	return "하루 길이: %.0f초/일 (%.0f×)" % [day_sec, 86400.0 / max(day_sec, 0.01)]
