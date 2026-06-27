class_name WorldSimUI
extends CanvasLayer

signal settings_confirmed(s: Dictionary)
signal view_mode_requested(mode: String)
signal aspect_requested(ratio: String)
signal test_event_requested(event_name: String)

const _CFG := "user://window_state.cfg"

# UI 상태 (저장/복원 대상)
var font_scale: float  = 2.0
var panel_w_saved: int = 0
var panel_h_saved: int = 0

# 내부 상태
var _cur_scale: float        = 2.0
var _pending := {}
var _fs: int                 = 16
var _slider_h: int           = 20
var _panel: Panel            = null
var _scroll: ScrollContainer = null
var _vb: VBoxContainer       = null
var _handle: Control         = null
var _resizing: bool          = false
var status_label: Label      = null

# ── 저장 / 복원 ──────────────────────────────────────────────────────
func load_state(window: Window) -> void:
	var cfg := ConfigFile.new()
	var ok  := cfg.load(_CFG) == OK
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

# ── 패널 리사이즈 ────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
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
	if _scroll:
		_scroll.size = Vector2(inner_w, new_h - int(12 * _cur_scale))
	if _vb:
		_vb.custom_minimum_size.x = max(80, inner_w - int(20 * _cur_scale))
	panel_w_saved = new_w
	panel_h_saved = new_h

# ── 전체 UI 구성 ─────────────────────────────────────────────────────
func _build_all(init: Dictionary) -> void:
	var vp: Vector2   = get_viewport().get_visible_rect().size
	var s: float      = clampf(font_scale, 0.5, 4.0)
	_cur_scale         = s

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

	# ── 상단 정보 바 ─────────────────────────────────────────
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

	var settings_btn := Button.new()
	settings_btn.text = "⚙  설정"
	settings_btn.add_theme_font_size_override("font_size", fs_top)
	settings_btn.custom_minimum_size = Vector2(btn_w, 0)
	top_hb.add_child(settings_btn)

	# ── 파라미터 패널 ────────────────────────────────────────
	var panel := Panel.new()
	panel.position     = Vector2(int(8 * s), panel_y)
	panel.size         = Vector2(panel_w, panel_h)
	panel.clip_contents = true
	add_child(panel)

	var ui_theme := Theme.new()
	ui_theme.set_font_size("font_size", "Label",        fs_label)
	ui_theme.set_font_size("font_size", "Button",       fs_ctrl)
	ui_theme.set_font_size("font_size", "OptionButton", fs_ctrl)
	ui_theme.set_font_size("font_size", "CheckBox",     fs_ctrl)
	panel.theme = ui_theme

	var inner_w: int = panel_w - int(12 * s)
	var scroll  := ScrollContainer.new()
	scroll.position               = Vector2(int(6 * s), int(6 * s))
	scroll.size                   = Vector2(inner_w, panel_h - int(12 * s))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size    = Vector2(inner_w - int(20 * s), 0)
	vb.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	_panel  = panel
	_scroll = scroll
	_vb     = vb

	# ── 리사이즈 핸들 (패널 내부 우하단) ───────────────────
	var hsz    := int(20 * s)
	var handle := Panel.new()
	handle.position                  = Vector2(panel_w - hsz, panel_h - hsz)
	handle.size                      = Vector2(hsz, hsz)
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

	# ── pending ──────────────────────────────────────────────
	_pending = {
		"font_scale":         font_scale,
		"weather_type":       init.get("weather_type",       "RAIN"),
		"rain_rate":          init.get("rain_rate",          20.0),
		"overcast_intensity": init.get("overcast_intensity", 0.6),
		"wind_enabled":       init.get("wind_enabled",       true),
		"wind_speed":         init.get("wind_speed",         1.6),
		"wind_direction":     init.get("wind_direction",     0.0),
		"latitude":           init.get("latitude",           37.5665),
		"longitude":          init.get("longitude",          126.978),
		"utc_offset":         init.get("utc_offset",         9.0),
		"time_of_day":        init.get("time_of_day",        12.0),
		"real_time_mode":     init.get("real_time_mode",     false),
		"day_length_sec":     init.get("day_length_sec",     120.0),
		"rain_streak_scale":    init.get("rain_streak_scale",    1.0),
		"snow_size_scale":      init.get("snow_size_scale",      1.0),
		"show_constellations":  init.get("show_constellations",  false),
	}

	# ── 설정 컨트롤 ─────────────────────────────────────────
	vb.add_child(_slider_row("글자 크기", 0.5, 4.0, font_scale, func(v: float):
		_pending["font_scale"] = v))

	var weather_list := ["CLEAR", "CIRRUS", "CUMULUS", "OVERCAST", "RAIN", "SNOW"]
	var weather_opt  := OptionButton.new()
	weather_opt.add_theme_font_size_override("font_size", fs_ctrl)
	weather_opt.get_popup().add_theme_font_size_override("font_size", fs_ctrl)
	for w in weather_list:
		weather_opt.add_item(w)
	weather_opt.select(max(0, weather_list.find(init.get("weather_type", "RAIN"))))
	vb.add_child(_labeled("날씨", weather_opt))

	var rain_row := _slider_row("강수강도", 0.5, 60.0,
		init.get("rain_rate", 20.0), func(v): _pending["rain_rate"] = v)
	vb.add_child(rain_row)
	var rain_streak_row := _slider_row("빗줄기 크기", 0.3, 2.5,
		init.get("rain_streak_scale", 1.0), func(v): _pending["rain_streak_scale"] = v)
	vb.add_child(rain_streak_row)
	var snow_size_row := _slider_row("눈송이 크기", 0.3, 2.5,
		init.get("snow_size_scale", 1.0), func(v): _pending["snow_size_scale"] = v)
	vb.add_child(snow_size_row)
	var overcast_row := _slider_row("흐림 정도", 0.0, 1.0,
		init.get("overcast_intensity", 0.6), func(v): _pending["overcast_intensity"] = v)
	vb.add_child(overcast_row)

	var refresh_rows := func():
		var wt: String = _pending.get("weather_type", "CLEAR")
		rain_row.visible        = wt == "RAIN" or wt == "SNOW"
		rain_streak_row.visible = wt == "RAIN"
		snow_size_row.visible   = wt == "SNOW"
		overcast_row.visible    = wt == "OVERCAST"
	weather_opt.item_selected.connect(func(idx):
		_pending["weather_type"] = weather_opt.get_item_text(idx)
		refresh_rows.call())
	refresh_rows.call()

	var check_h: int = maxi(24, int(fs_ctrl * 1.6))

	var const_check := CheckBox.new()
	const_check.text = "별자리 선 표시"
	const_check.button_pressed = init.get("show_constellations", false)
	const_check.add_theme_font_size_override("font_size", fs_ctrl)
	const_check.custom_minimum_size = Vector2(0, check_h)
	const_check.toggled.connect(func(p): _pending["show_constellations"] = p)
	vb.add_child(const_check)

	var wind_check := CheckBox.new()
	wind_check.text = "바람"
	wind_check.button_pressed = init.get("wind_enabled", true)
	wind_check.add_theme_font_size_override("font_size", fs_ctrl)
	wind_check.custom_minimum_size = Vector2(0, check_h)
	wind_check.toggled.connect(func(p): _pending["wind_enabled"] = p)
	vb.add_child(wind_check)

	vb.add_child(_slider_row("바람 속도",    0.0,   12.0, init.get("wind_speed",     1.6),  func(v): _pending["wind_speed"]     = v))
	vb.add_child(_slider_row("바람 방향(°)", 0.0,  360.0, init.get("wind_direction", 0.0),  func(v): _pending["wind_direction"] = v))
	vb.add_child(_slider_row("위도",      -90.0, 90.0,   init.get("latitude",      37.5665), func(v): _pending["latitude"]     = v))
	vb.add_child(_slider_row("경도",      -180.0, 180.0, init.get("longitude",     126.978), func(v): _pending["longitude"]    = v))
	vb.add_child(_slider_row("UTC오프셋", -12.0, 14.0,   init.get("utc_offset",    9.0),     func(v): _pending["utc_offset"]   = v))
	vb.add_child(_slider_row("시간(현지)", 0.0, 24.0,    init.get("time_of_day",   12.0),    func(v): _pending["time_of_day"]  = v))

	var rt_check := CheckBox.new()
	rt_check.text = "재생으로 시간 자동 진행"
	rt_check.button_pressed = init.get("real_time_mode", false)
	rt_check.add_theme_font_size_override("font_size", fs_ctrl)
	rt_check.custom_minimum_size = Vector2(0, check_h)
	rt_check.toggled.connect(func(p): _pending["real_time_mode"] = p)
	vb.add_child(rt_check)

	vb.add_child(_slider_row("하루 길이(초)", 5.0, 600.0, init.get("day_length_sec", 120.0), func(v): _pending["day_length_sec"] = v))

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
	vb.add_child(_labeled("시점", view_row))

	var aspect_row := HBoxContainer.new()
	for ar: String in ["16:9", "9:16", "1:1"]:
		var abtn := Button.new()
		abtn.text = ar
		abtn.pressed.connect(func(): aspect_requested.emit(ar))
		aspect_row.add_child(abtn)
	vb.add_child(_labeled("화면비율", aspect_row))

	var cam_help := Label.new()
	cam_help.text         = "카메라: 우클릭으로 시점모드 켜고끄기 (Esc로도 끔), WASD 이동, 스크롤로 속도조절."
	cam_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	cam_help.add_theme_font_size_override("font_size", fs_label)
	vb.add_child(cam_help)

	# ── 확인 버튼 ────────────────────────────────────────────
	var btn_ok := Button.new()
	btn_ok.text = "확인"
	btn_ok.add_theme_font_size_override("font_size", fs_ctrl)
	btn_ok.pressed.connect(func(): settings_confirmed.emit(_pending.duplicate()))
	vb.add_child(btn_ok)

	# ── 테스트 버튼 ──────────────────────────────────────────
	vb.add_child(HSeparator.new())
	var test_lbl := Label.new()
	test_lbl.text = "테스트"
	test_lbl.add_theme_font_size_override("font_size", _fs)
	vb.add_child(test_lbl)
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", maxi(2, int(4 * s)))
	for pair: Array in [["번개", "lightning"], ["별똥별", "meteor"], ["유성우", "shower"], ["혜성 토글", "comet"]]:
		var tbtn := Button.new()
		tbtn.text = pair[0]
		tbtn.add_theme_font_size_override("font_size", fs_ctrl)
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ename: String = pair[1]
		tbtn.pressed.connect(func(): test_event_requested.emit(ename))
		test_row.add_child(tbtn)
	vb.add_child(test_row)

	settings_btn.pressed.connect(func(): panel.visible = not panel.visible)

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

func _slider_row(text: String, lo: float, hi: float, val: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = "%s: %.2f" % [text, val]
	l.add_theme_font_size_override("font_size", _fs)
	box.add_child(l)
	var sl := HSlider.new()
	sl.min_value             = lo
	sl.max_value             = hi
	sl.step                  = (hi - lo) / 500.0
	sl.value                 = val
	sl.custom_minimum_size   = Vector2(0, _slider_h)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v):
		on_change.call(v)
		l.text = "%s: %.2f" % [text, v])
	box.add_child(sl)
	return box
