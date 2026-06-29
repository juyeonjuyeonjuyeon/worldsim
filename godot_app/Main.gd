extends Node3D
## WS Forest Weather — 독립 실행판(Godot). forest_rain_live.py(블렌더 실시간
## 도구)와 같은 날씨/시간/조명 개념을 별도 엔진으로 재구현 — 블렌더 설치 없이
## 더블클릭으로 실행되는 .exe로 빌드하기 위함. 천체력은 skyfield 대신
## Astronomy.gd(NOAA 태양 공식 + Meeus 저정밀 달 공식)을 사용.

const _SkyCls    = preload("res://Sky.gd")
const _EnvCls    = preload("res://Environment.gd")
const _SoundCls  = preload("res://Sound.gd")
const _CameraCls = preload("res://Camera.gd")
const _UICls     = preload("res://UI.gd")
const SkyMath    = preload("res://SkyMath.gd")  # 구간 보간 헬퍼 공용 (Sky.gd와 중복 제거)

# ── 실제 기상학 기준값 ──
# 광학두께(optical depth, τ)는 구름이 빛을 얼마나 막는지의 실제 물리량 —
# 베어-램버트 법칙(Beer-Lambert law)으로 직사광 투과율 = exp(-τ). 불투명/반투명
# 경계가 τ=10(AMS Glossary of Meteorology). 얇은 시러스 <0.1~1, 적운 1~10대,
# 대형 적운형 강수운(쿠물로님버스)은 수십~1000 이상까지 올라감(AMS Glossary).
const TAU_CIRRUS: float = 0.6
const TAU_CUMULUS: float = 4.0
const TAU_OVERCAST: float = 18.0
const TAU_OVERCAST_LIGHT: float = 4.0  # "흐림 정도" 슬라이더 0.0 쪽 끝값(엷은 흐림)
# WMO 강수강도 경계(mm/hr): 약한 비 ≤2.5, 보통 2.5~7.6, 강한 7.6~50, 폭우 >50
const RAIN_RATE_BREAKPOINTS: Array = [0.0, 2.5, 7.6, 50.0]
const RAIN_TAU_BREAKPOINTS: Array = [8.0, 12.0, 25.0, 70.0]
const SNOW_TAU_BREAKPOINTS: Array = [6.0, 10.0, 20.0, 55.0]
# WMO 옥타(하늘을 8등분해 구름이 덮은 칸 수)
const OKTA_CIRRUS: float = 3.0 / 8.0
const OKTA_CUMULUS: float = 4.0 / 8.0
const OKTA_OVERCAST: float = 8.0 / 8.0

# ── 날씨/시간 상태 ──
var weather_type: String = "CLEAR"  # CLEAR/CIRRUS/CUMULUS/OVERCAST/RAIN/SNOW
var rain_rate: float = 0.0
var overcast_intensity: float = 0.6
var wind_enabled: bool = true
var wind_speed: float = 1.6
var wind_direction: float = 0.0   # 나침반 방위각(0=북, 90=동, 180=남, 270=서)
var rain_streak_scale: float  = 1.0
var snow_size_scale: float    = 1.0
var show_constellations: bool = false
var show_trails: bool         = false
var latitude: float = 37.5665
var longitude: float = 126.9780
var utc_offset: float = 9.0
var sim_year: int = 2026
var sim_month: int = 6
var sim_day: int = 21
var time_of_day: float = 12.0
var real_time_mode: bool = false
var day_length_sec: float = 120.0
var elapsed_play_seconds: float = 0.0
var sim_temperature: float = 15.0
var use_fahrenheit: bool   = false
var auto_weather: bool     = false

var _auto_wx_sim_timer: float      = 0.0
var _auto_rain_target: float       = 0.0
var _auto_overcast_target: float   = 0.6
var _auto_wind_speed_target: float = 0.0
var _auto_wind_dir_target: float   = 0.0
var _auto_wx_rng := RandomNumberGenerator.new()

# ── 모듈 참조 ──
var _sky        = null
var _env        = null
var _sound      = null
var _camera     = null
var _ui         = null
var _eye_canvas: CanvasLayer = null
var _eye_rect: ColorRect     = null
var _paused: bool            = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _ui:
			_ui.save_state(get_window())
		get_tree().quit()

func _ready() -> void:
	_ui = _UICls.new()
	add_child(_ui)
	_ui.load_state(get_window())

	var sys_font := SystemFont.new()
	sys_font.antialiasing         = TextServer.FONT_ANTIALIASING_LCD
	sys_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	sys_font.hinting              = TextServer.HINTING_NORMAL
	ThemeDB.fallback_font         = sys_font

	randomize()
	_auto_wx_rng.randomize()

	_sky = _SkyCls.new()
	add_child(_sky)
	_sky.build()

	_env = _EnvCls.new()
	add_child(_env)
	_env.build()

	_sound = _SoundCls.new()
	add_child(_sound)
	_sound.build()

	_camera = _CameraCls.new()
	add_child(_camera)
	_camera.build()

	# 사람눈 뷰 후처리: 색 수차(Chromatic Aberration) + 비네트
	var eye_shader: Shader = load("res://eye_postfx.gdshader")
	var eye_mat := ShaderMaterial.new()
	eye_mat.shader = eye_shader
	_eye_rect = ColorRect.new()
	_eye_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_eye_rect.material = eye_mat
	_eye_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_rect.visible = _camera.eye_view
	_eye_canvas = CanvasLayer.new()
	_eye_canvas.layer = 0
	_eye_canvas.add_child(_eye_rect)
	add_child(_eye_canvas)

	_ui.settings_confirmed.connect(_on_settings_confirmed)
	_ui.view_mode_requested.connect(_set_view_mode)
	_ui.aspect_requested.connect(_set_aspect)
	_ui.test_event_requested.connect(_on_test_event)
	_ui.eye_view_requested.connect(_on_eye_view_requested)
	_ui.play_state_changed.connect(_on_play_state_changed)
	_ui.build(_ui_init_dict())
	_update_all(0.0)
	_maybe_auto_screenshot()

func _maybe_auto_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--auto-screenshot")
	if idx < 0:
		return
	var out_path: String = "user://auto_screenshot.png" if idx + 1 >= args.size() else args[idx + 1]
	var lat_idx := args.find("--lat")
	if lat_idx >= 0 and lat_idx + 1 < args.size():
		latitude = float(args[lat_idx + 1])
	var mon_idx := args.find("--month")
	if mon_idx >= 0 and mon_idx + 1 < args.size():
		sim_month = int(args[mon_idx + 1])
	var day_idx := args.find("--day")
	if day_idx >= 0 and day_idx + 1 < args.size():
		sim_day = int(args[day_idx + 1])
	var hum_force: float = -1.0
	var hum_idx := args.find("--humidity")
	if hum_idx >= 0 and hum_idx + 1 < args.size():
		hum_force = float(args[hum_idx + 1])
	var wx_idx := args.find("--weather")
	if wx_idx >= 0 and wx_idx + 1 < args.size():
		weather_type = args[wx_idx + 1]
		rain_rate = 15.0
	if args.has("--force-rainbow"):
		_sky.force_rainbow(true)
	if args.has("--constellations"):
		show_constellations = true
		show_trails = true
	var camy_idx := args.find("--camy")
	if camy_idx >= 0 and camy_idx + 1 < args.size():
		_camera.get_camera().position = Vector3(8.0, float(args[camy_idx + 1]), 16.0)
	var fixed_time: float = -999.0
	var time_idx := args.find("--time")
	if time_idx >= 0 and time_idx + 1 < args.size():
		fixed_time = float(args[time_idx + 1])
		time_of_day = fixed_time
		# 노출 스무딩을 시간 고정 상태에서 수렴시킴 (검수 결정성 확보).
		# 매 호출 elapsed 리셋 → 시간 드리프트 없이 delta만 공급.
		# _env.humidity는 _env.update보다 _sky.update가 먼저 읽으므로 매 호출 전 강제.
		for i in range(120):
			elapsed_play_seconds = 0.0
			time_of_day = fixed_time
			if hum_force >= 0.0: _env.humidity = hum_force
			_update_all(0.05)
	var yaw_idx := args.find("--yaw")
	if yaw_idx >= 0 and yaw_idx + 1 < args.size():
		_camera._yaw = deg_to_rad(float(args[yaw_idx + 1]))
	var pitch_idx := args.find("--pitch")
	if pitch_idx >= 0 and pitch_idx + 1 < args.size():
		_camera._pitch = deg_to_rad(float(args[pitch_idx + 1]))
	_camera.update(0.0)   # yaw/pitch 즉시 반영
	# 시간 고정 유지하며 여러 프레임 렌더 (하늘 radiance/노출 안정화)
	for _i in range(40):
		if fixed_time > -900.0:
			elapsed_play_seconds = 0.0
			time_of_day = fixed_time
		if hum_force >= 0.0: _env.humidity = hum_force
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("AUTO SCREENSHOT: " + out_path)
	# 하늘 색 진단: 우측 청천 컬럼(x=0.78W)을 천정→지평선으로 샘플링 (sRGB 0–255)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var sx: int = int(w * 0.78)
	for fy in [0.06, 0.14, 0.22, 0.30, 0.38, 0.44, 0.48]:
		var py: int = int(h * fy)
		var c: Color = img.get_pixel(sx, py)
		print("PIXEL y=%.2f  rgb=(%3d,%3d,%3d)" % [fy, int(c.r*255.0), int(c.g*255.0), int(c.b*255.0)])
	# 지평선 수평 스캔: 청천 픽셀(녹색 지면/나무 아닌 곳) 탐색용
	var hrow: int = args.find("--scanrow")
	var fyr: float = 0.50 if hrow < 0 or hrow + 1 >= args.size() else float(args[hrow + 1])
	var pyr: int = int(h * fyr)
	for fx in [0.40, 0.48, 0.56, 0.64, 0.72, 0.80, 0.88, 0.96]:
		var pxr: int = int(w * fx)
		var c2: Color = img.get_pixel(pxr, pyr)
		print("HSCAN y=%.2f x=%.2f rgb=(%3d,%3d,%3d)" % [fyr, fx, int(c2.r*255.0), int(c2.g*255.0), int(c2.b*255.0)])
	get_tree().quit()

func _ui_init_dict() -> Dictionary:
	return {
		"weather_type":       weather_type,
		"rain_rate":          rain_rate,
		"overcast_intensity": overcast_intensity,
		"wind_enabled":       wind_enabled,
		"wind_speed":         wind_speed,
		"wind_direction":     wind_direction,
		"latitude":           latitude,
		"longitude":          longitude,
		"utc_offset":         utc_offset,
		"sim_year":           sim_year,
		"sim_month":          sim_month,
		"sim_day":            sim_day,
		"time_of_day":        time_of_day,
		"real_time_mode":     real_time_mode,
		"day_length_sec":     day_length_sec,
		"view_mode":          _camera.view_mode,
		"rain_streak_scale":     rain_streak_scale,
		"snow_size_scale":       snow_size_scale,
		"show_constellations":   show_constellations,
		"show_trails":           show_trails,
		"eye_view":              _camera.eye_view,
		"use_fahrenheit":        use_fahrenheit,
		"auto_weather":          auto_weather,
	}

func _on_settings_confirmed(s: Dictionary) -> void:
	var need_rebuild: bool = s.get("font_scale", _ui.font_scale) != _ui.font_scale
	if need_rebuild:
		_ui.font_scale = s["font_scale"]
	weather_type       = s.get("weather_type",       weather_type)
	rain_rate          = s.get("rain_rate",          rain_rate)
	overcast_intensity = s.get("overcast_intensity", overcast_intensity)
	wind_enabled       = s.get("wind_enabled",       wind_enabled)
	wind_speed         = s.get("wind_speed",         wind_speed)
	wind_direction     = s.get("wind_direction",     wind_direction)
	latitude           = s.get("latitude",           latitude)
	longitude          = s.get("longitude",          longitude)
	utc_offset         = s.get("utc_offset",         utc_offset)
	sim_year           = int(s.get("sim_year",   sim_year))
	sim_month          = int(s.get("sim_month",  sim_month))
	sim_day            = int(s.get("sim_day",    sim_day))
	time_of_day        = s.get("time_of_day",        time_of_day)
	if s.get("_reset_elapsed", false):
		elapsed_play_seconds = 0.0
	var new_rt: bool   = s.get("real_time_mode",     real_time_mode)
	if new_rt != real_time_mode:
		real_time_mode = new_rt
		elapsed_play_seconds = 0.0
	day_length_sec     = s.get("day_length_sec",     day_length_sec)
	rain_streak_scale    = s.get("rain_streak_scale",    rain_streak_scale)
	snow_size_scale      = s.get("snow_size_scale",      snow_size_scale)
	show_constellations  = s.get("show_constellations",  show_constellations)
	show_trails          = s.get("show_trails",          show_trails)
	use_fahrenheit       = s.get("use_fahrenheit",       use_fahrenheit)
	var prev_auto: bool  = auto_weather
	auto_weather         = s.get("auto_weather",         auto_weather)
	if auto_weather and not prev_auto:
		_auto_wx_sim_timer = 0.0  # 즉시 첫 날씨 결정
	if need_rebuild:
		_ui.build(_ui_init_dict())
	_update_all(0.0)

func _on_test_event(event_name: String) -> void:
	match event_name:
		"lightning": _sound.trigger_lightning()
		"meteor":    _sky.trigger_meteor(false)
		"shower":    _sky.trigger_meteor(true)
		"comet":     _sky.trigger_comet_test()
		# TODO Phase 1: 특수현상 — 효과 미구현
		"solar_eclipse":  push_warning("TODO solar_eclipse: 일식 셰이더 미구현 (Phase 1)")
		"lunar_eclipse":  push_warning("TODO lunar_eclipse: 월식 붉은달 셰이더 미구현 (Phase 1)")
		"aurora":         # 오로라 KP 이벤트 강제 발생 (latitude 50°+ 필요)
			_sky._aurora_kp = randf_range(5.0, 9.0)
			_sky._aurora_next_event = 300.0
		"rainbow_force":  _sky.force_rainbow(!_sky._rainbow_force)  # 누를 때마다 토글

func _set_view_mode(mode: String) -> void:
	_camera.set_view_mode(mode)

func _on_eye_view_requested(enabled: bool) -> void:
	_camera.set_eye_view(enabled)
	if _eye_rect:
		_eye_rect.visible = enabled

func _on_play_state_changed(playing: bool) -> void:
	_paused = not playing
	if _camera:
		_camera.paused = _paused
	_update_all(0.0)  # 상태바 ⏸ 즉시 반영

func _set_aspect(ratio: String) -> void:
	var size: Vector2i
	match ratio:
		"16:9":  size = Vector2i(1280, 720)
		"9:16":  size = Vector2i(540, 960)
		"1:1":   size = Vector2i(800, 800)
		_:       return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)

# ── 매 프레임 갱신 ─────────────────────────────────────────────────
func _process(delta: float) -> void:
	_camera.update(delta)   # 정지 중에도 시점 회전은 허용
	if not _paused:
		_update_all(delta)

func _update_all(delta: float) -> void:
	if real_time_mode:
		elapsed_play_seconds += delta
	var dt: Dictionary = _current_datetime()
	var hour_utc: float = dt["hour"] - utc_offset
	var sun_altaz: Vector2 = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var moon: Dictionary = Astronomy.moon_state(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var cloud_props: Dictionary = _weather_cloud_props()

	sim_temperature = _estimate_temperature(dt["month"], int(dt["day"]), fmod(dt["hour"], 24.0), latitude, longitude, weather_type)
	if auto_weather:
		_update_auto_weather(delta, dt["month"])
	_sky.show_constellations = show_constellations
	_sky.show_trails         = show_trails
	_sky.update(
		sun_altaz, moon, cloud_props,
		weather_type, wind_speed, wind_direction, wind_enabled,
		_sound.lightning_flash_intensity,
		_sound.lightning_bolt_dist_km,
		dt, hour_utc, latitude, longitude,
		sim_temperature, _env.ground_wetness, delta,
		_camera.eye_view, _env.humidity)

	var _cam_pos: Vector3 = _camera.get_camera().global_position
	_env.update(
		weather_type, rain_rate, wind_speed, wind_direction, wind_enabled,
		cloud_props, sim_month, latitude,
		_sky.sky_brightness_safe, _sky.sky_overcast_amt_current,
		rain_streak_scale, snow_size_scale,
		sim_temperature, fmod(dt["hour"], 24.0), delta,
		_cam_pos)

	_sound.update(weather_type, wind_enabled, wind_speed, rain_rate, delta)

	if _ui:
		_ui.update_time_ui(dt)
		var h: int = int(dt["hour"])
		var m: int = int(fmod(dt["hour"], 1.0) * 60)
		var lat_str: String = "%.2f°%s" % [abs(latitude), "N" if latitude >= 0.0 else "S"]
		var lng_str: String = "%.2f°%s" % [abs(longitude), "E" if longitude >= 0.0 else "W"]
		var pause_tag: String = "  ⏸" if _paused else ""
		var temp_disp: String = ("%.1f°F" % (sim_temperature * 9.0 / 5.0 + 32.0)) if use_fahrenheit \
			else ("%.1f°C" % sim_temperature)
		var hum_str: String = "습도 %.0f%%" % _env.humidity
		var evt_str: String = ("  |  " + _sky.planet_events) if _sky.planet_events != "" else ""
		_ui.update_status("%04d-%02d-%02d  %02d:%02d  |  %s  %s  |  %s  %s%s%s" % [
			dt["year"], dt["month"], dt["day"], h, m, lat_str, lng_str,
			temp_disp, hum_str, evt_str, pause_tag])

# ── 날씨 → 구름 물리 파라미터 ───────────────────────────────────────
func _weather_cloud_props() -> Dictionary:
	match weather_type:
		"CIRRUS":
			return {"tau": TAU_CIRRUS, "okta": OKTA_CIRRUS, "rain_rate": 0.0}
		"CUMULUS":
			return {"tau": TAU_CUMULUS, "okta": OKTA_CUMULUS, "rain_rate": 0.0}
		"OVERCAST":
			var tau_o: float = lerp(TAU_OVERCAST_LIGHT, TAU_OVERCAST, overcast_intensity)
			return {"tau": tau_o, "okta": OKTA_OVERCAST, "rain_rate": 0.0}
		"RAIN":
			var tau: float = SkyMath._lerp_breakpoints(rain_rate, RAIN_RATE_BREAKPOINTS, RAIN_TAU_BREAKPOINTS)
			return {"tau": tau, "okta": clampf(0.85 + 0.15 * clampf(rain_rate / 30.0, 0.0, 1.0), 0.85, 1.0), "rain_rate": rain_rate}
		"SNOW":
			var tau_s: float = SkyMath._lerp_breakpoints(rain_rate, RAIN_RATE_BREAKPOINTS, SNOW_TAU_BREAKPOINTS)
			return {"tau": tau_s, "okta": clampf(0.80 + 0.15 * clampf(rain_rate / 30.0, 0.0, 1.0), 0.80, 1.0), "rain_rate": rain_rate}
	return {"tau": 0.0, "okta": 0.0, "rain_rate": 0.0}

func _current_datetime() -> Dictionary:
	if real_time_mode:
		var elapsed_sim_hours: float = (elapsed_play_seconds / max(day_length_sec, 0.001)) * 24.0
		var total_hours: float = time_of_day + elapsed_sim_hours
		var day_offset: int = int(floor(total_hours / 24.0))
		var hour: float = fmod(total_hours, 24.0)
		if hour < 0:
			hour += 24.0
		var base := Time.get_unix_time_from_datetime_dict({"year": sim_year, "month": sim_month, "day": sim_day, "hour": 0, "minute": 0, "second": 0})
		base += day_offset * 86400
		var d := Time.get_datetime_dict_from_unix_time(int(base))
		return {"year": d["year"], "month": d["month"], "day": d["day"], "hour": hour}
	return {"year": sim_year, "month": sim_month, "day": sim_day, "hour": time_of_day}

static func _estimate_temperature(month: int, day: int, hour_local: float, latitude: float, longitude: float, p_weather: String) -> float:
	# 위도별 기후 근사 — 경도 보정 포함
	# 위도별 연 평균 기온: 0°=26°C, 25°=22°C, 45°=11°C, 65°=0°C, 90°=-20°C
	const LAT_P:     Array = [0.0, 25.0, 45.0, 65.0, 90.0]
	const MEAN_P:    Array = [26.0, 22.0, 11.0, 0.0, -20.0]
	# 위도별 계절 진폭 (연 최고·최저 절반폭): 적도≈1°C, 중위도≈10°C, 극지≈12°C
	const AMP_P:     Array = [1.0, 5.0, 10.0, 14.0, 12.0]
	# 위도별 일교차 진폭: 열대≈4°C, 아열대≈7°C, 온대≈9°C, 한대≈8°C, 극≈4°C
	const DIURNAL_P: Array = [4.0, 7.0, 9.0, 8.0, 4.0]
	var abs_lat: float      = abs(latitude)
	# 경도 보정: 대륙성·해양성·몬순 지역별 연평균·계절진폭 보정
	var bias: Dictionary    = _get_climate_bias(latitude, longitude, month)
	var annual_mean: float  = SkyMath._lerp_breakpoints(abs_lat, LAT_P, MEAN_P) + float(bias["mean_offset"])
	var seasonal_amp: float = SkyMath._lerp_breakpoints(abs_lat, LAT_P, AMP_P) * float(bias["amp_mult"])
	var diurnal_amp: float  = SkyMath._lerp_breakpoints(abs_lat, LAT_P, DIURNAL_P)
	# 날짜 연속 월 — 월 경계를 매끄럽게 보간 (1일=month, 말일≈month+1)
	var month_f: float = float(month) + float(day - 1) / 30.0
	# 남반구: 6개월 계절 반전
	if latitude < 0.0:
		month_f = fmod(month_f - 1.0 + 6.0, 12.0) + 1.0
	# 최고 기온 8월, 최저 2월 기준 코사인 (북반구 기준)
	var phase: float        = cos((month_f - 8.0) * 2.0 * PI / 12.0)
	var monthly_base: float = annual_mean + seasonal_amp * phase
	# 날씨별 온도 보정: 비=증발냉각, 눈·흐림=약간 냉각; 구름은 일교차도 줄임
	var weather_offset: float = 0.0
	var diurnal_scale:  float = 1.0
	match p_weather:
		"RAIN":
			weather_offset = -2.5
			diurnal_scale  = 0.45
		"SNOW":
			weather_offset = -1.0
			diurnal_scale  = 0.50
		"OVERCAST":
			weather_offset = -0.5
			diurnal_scale  = 0.60
		"CUMULUS":
			diurnal_scale  = 0.85
	# 일교차: 오후 2시 최고, 새벽 2시 최저 (위도별 진폭, 날씨에 따라 축소)
	# cos(hour-14)는 14시=1(최대), 2시=-1(최소) → +부호로 14시 최고기온
	var day_offset: float = diurnal_amp * diurnal_scale * cos((hour_local - 14.0) * PI / 12.0)
	return monthly_base + day_offset + weather_offset

func _update_auto_weather(delta: float, cur_month: int) -> void:
	var sim_speed: float = 86400.0 / maxf(day_length_sec, 1.0)
	_auto_wx_sim_timer -= delta * sim_speed
	if _auto_wx_sim_timer <= 0.0:
		_roll_auto_weather(cur_month)
	rain_rate          = move_toward(rain_rate,          _auto_rain_target,     delta * 3.0)
	overcast_intensity = move_toward(overcast_intensity, _auto_overcast_target, delta * 0.12)
	# 풍속: 0.8 m/s per second 속도로 변화
	wind_speed = move_toward(wind_speed, _auto_wind_speed_target, delta * 0.8)
	# 풍향: 최단 방향으로 초당 20° 회전 (원형 보간)
	var dir_diff: float = fmod((_auto_wind_dir_target - wind_direction + 540.0), 360.0) - 180.0
	wind_direction = fmod(wind_direction + clampf(dir_diff, -delta * 20.0, delta * 20.0) + 360.0, 360.0)

func _roll_auto_weather(cur_month: int) -> void:
	var params: Dictionary = WorldSimWeather.get_params(latitude, cur_month)
	var bias:   Dictionary = _get_climate_bias(latitude, longitude, cur_month)
	# 다음 날씨 지속: 1-4 시뮬레이션 일 (= 86400 sim초/일)
	_auto_wx_sim_timer = _auto_wx_rng.randf_range(86400.0, 86400.0 * 4.0)

	var adj_precip: float = clampf(float(params["precip_prob"]) * float(bias["precip_mult"]), 0.0, 0.98)
	if _auto_wx_rng.randf() < adj_precip:
		# 강수 결정 — 눈/비 판정: 기후 경향 + 온도 보정
		var sb: float = float(params["snow_bias"])
		if sim_temperature < 0.0:
			sb = clampf(sb + 0.35, 0.0, 0.97)
		elif sim_temperature > 4.0:
			sb = maxf(0.0, sb - 0.25)
		weather_type = "SNOW" if _auto_wx_rng.randf() < sb else "RAIN"
		var rate: float = float(params["rain_rate_mean"]) * _auto_wx_rng.randf_range(0.4, 2.5)
		_auto_rain_target = clampf(rate, 0.5, 55.0)
	else:
		_auto_rain_target = 0.0
		var cb: float  = float(params["cloud_cover"])
		var cr: float  = _auto_wx_rng.randf()
		if cr < cb * 0.28:
			weather_type          = "OVERCAST"
			_auto_overcast_target = _auto_wx_rng.randf_range(0.30, 0.88)
		elif cr < cb * 0.62:
			weather_type = "CUMULUS"
		elif cr < cb:
			weather_type = "CIRRUS"
		else:
			weather_type = "CLEAR"

	# 날씨 유형별 풍속 범위 (m/s)
	var ws_min: float; var ws_max: float
	match weather_type:
		"CLEAR":    ws_min = 0.0; ws_max = 3.0
		"CIRRUS":   ws_min = 2.0; ws_max = 7.0
		"CUMULUS":  ws_min = 3.0; ws_max = 9.0
		"OVERCAST": ws_min = 5.0; ws_max = 13.0
		"RAIN":     ws_min = 4.0; ws_max = 16.0
		"SNOW":     ws_min = 1.0; ws_max = 12.0
		_:          ws_min = 0.0; ws_max = 5.0
	_auto_wind_speed_target = _auto_wx_rng.randf_range(ws_min, ws_max)
	# 탁월풍 기반 풍향 — 완전 랜덤 대신 기후대 편향, 날씨별 편차 폭 추가
	var prevail_dir: float = _prevailing_wind_dir(latitude)
	var spread: float
	match weather_type:
		"CLEAR":    spread = 20.0   # 맑음: 안정적, 탁월풍에 가깝게
		"CIRRUS":   spread = 30.0
		"CUMULUS":  spread = 40.0
		"OVERCAST": spread = 55.0   # 저기압성 흐림: 기압 배치에 따라 편차 큼
		"RAIN":     spread = 65.0   # 비: 저기압 중심으로 회전, 방향 흐트러짐
		"SNOW":     spread = 50.0
		_:          spread = 40.0
	_auto_wind_dir_target = fmod(prevail_dir + _auto_wx_rng.randf_range(-spread, spread) + 360.0, 360.0)

static func _get_climate_bias(latitude: float, longitude: float, month: int) -> Dictionary:
	# 위도+경도 기반 기후 보정 (동일 위도라도 대륙/해양/몬순 차이 반영)
	# precip_mult: 강수 확률 배율  amp_mult: 계절 진폭 배율  mean_offset: 연평균 온도 보정(°C)
	var precip_mult: float = 1.0
	var amp_mult:    float = 1.0
	var mean_offset: float = 0.0
	# 남반구는 계절 6개월 반전 후 강수 패턴 체크
	var eff_m: int = (month - 1 + (6 if latitude < 0.0 else 0)) % 12  # 0-indexed

	# ── 인도아대륙 남아시아 몬순 ─────────────────────────────────────────
	if latitude >= 5.0 and latitude <= 30.0 and longitude >= 65.0 and longitude <= 92.0:
		amp_mult    *= 0.85
		mean_offset += 2.0   # 위도 모델보다 실제 기온이 높음
		if eff_m >= 5 and eff_m <= 8:     # Jun-Sep 우기 (남서 계절풍)
			precip_mult *= 4.0
		elif eff_m >= 9 and eff_m <= 10:  # Oct-Nov 후몬순 잔류
			precip_mult *= 1.2
		else:                              # Dec-May 건기
			precip_mult *= 0.12

	# ── 동아시아 대륙성 + 장마 (한국·만주·화북·동북 중국) ───────────────
	if latitude >= 32.0 and latitude <= 49.0 and longitude >= 115.0 and longitude <= 132.0:
		amp_mult    *= 1.9   # 시베리아 고기압 영향으로 계절 진폭 극대화
		mean_offset -= 4.0   # 위도 모델보다 실제 겨울이 훨씬 추움
		if eff_m >= 5 and eff_m <= 7:     # Jun-Aug 장마
			precip_mult *= 2.5
		elif eff_m >= 8 and eff_m <= 9:   # Sep-Oct 태풍·가을비
			precip_mult *= 1.4
		elif eff_m <= 1 or eff_m == 11:   # Dec-Feb 건조 고기압
			precip_mult *= 0.6

	# ── 일본 열도 해양성 + 장마 ──────────────────────────────────────────
	if latitude >= 30.0 and latitude <= 45.0 and longitude >= 130.0 and longitude <= 146.0:
		amp_mult    *= 1.15  # 한반도보다 해양성, 진폭 적당
		mean_offset += 1.0
		if eff_m >= 5 and eff_m <= 7:     # Jun-Aug 장마
			precip_mult *= 2.0
		elif eff_m >= 8 and eff_m <= 9:   # Sep-Oct 태풍
			precip_mult *= 1.6

	# ── 지중해 기후 (유럽·북아프리카·레반트) ────────────────────────────
	if latitude >= 30.0 and latitude <= 46.0 and longitude >= -10.0 and longitude <= 42.0:
		amp_mult    *= 0.9
		mean_offset += 2.0   # 해양·일조량이 연평균 끌어올림
		if eff_m >= 5 and eff_m <= 8:     # Jun-Sep 건기
			precip_mult *= 0.12
		elif eff_m <= 1 or eff_m >= 10:   # Nov-Mar 우기
			precip_mult *= 1.9

	# ── 서유럽 해양성 (멕시코만류 영향권: 영국·프랑스·저지대·독일 북부) ──
	if latitude >= 46.0 and latitude <= 62.0 and longitude >= -12.0 and longitude <= 20.0:
		amp_mult    *= 0.65  # 대서양이 계절 진폭 크게 완화
		mean_offset += 3.0   # 멕시코만류로 겨울 온화

	# ── 시베리아 대륙성 극한 ─────────────────────────────────────────────
	if latitude >= 50.0 and latitude <= 68.0 and longitude >= 60.0 and longitude <= 140.0:
		amp_mult    *= 1.7
		mean_offset -= 8.0   # 광대한 대륙이 겨울을 극단적으로 냉각
		if eff_m <= 1 or eff_m == 11:     # Dec-Feb 시베리아 고기압 → 건조
			precip_mult *= 0.5

	# ── 중앙아시아 건조 스텝·사막 (카자흐스탄·투르크메니스탄) ──────────
	if latitude >= 35.0 and latitude <= 52.0 and longitude >= 45.0 and longitude <= 80.0:
		amp_mult    *= 1.4
		mean_offset -= 2.0
		precip_mult *= 0.5   # 내륙 건조, 연중 적음

	# ── 미국 대평원 대륙성 ───────────────────────────────────────────────
	if latitude >= 35.0 and latitude <= 52.0 and longitude >= -110.0 and longitude <= -88.0:
		amp_mult *= 1.4

	# ── 캘리포니아 지중해 ────────────────────────────────────────────────
	if latitude >= 34.0 and latitude <= 42.0 and longitude >= -125.0 and longitude <= -116.0:
		amp_mult    *= 0.70  # 해양성 — 계절 진폭 작음
		mean_offset -= 1.0   # 캘리포니아 한류(California Current) 냉각
		if eff_m >= 5 and eff_m <= 8:     # Jun-Sep 건기
			precip_mult *= 0.05
		elif eff_m <= 1 or eff_m >= 10:   # Nov-Mar 우기
			precip_mult *= 1.8

	# ── 호주 북부 몬순 (12월-3월이 우기 = SH 여름) ──────────────────────
	if latitude >= -20.0 and latitude <= -5.0 and longitude >= 125.0 and longitude <= 155.0:
		amp_mult *= 0.85
		if eff_m >= 5 and eff_m <= 8:     # SH 여름(Dec-Mar)에 해당하는 eff_m
			precip_mult *= 3.5
		else:
			precip_mult *= 0.15

	# ── 남아프리카 지중해 (케이프타운) ──────────────────────────────────
	if latitude >= -36.0 and latitude <= -28.0 and longitude >= 16.0 and longitude <= 26.0:
		if eff_m <= 1 or eff_m == 11:     # SH 겨울(Jun-Aug) = 우기
			precip_mult *= 1.8
		elif eff_m >= 5 and eff_m <= 8:   # SH 여름(Dec-Feb) = 건기
			precip_mult *= 0.15

	# ── 남반구 서부 해양성 (남칠레·파타고니아·뉴질랜드 남도) ────────────
	if latitude <= -40.0 and latitude >= -58.0:
		var lon_ok: bool = longitude <= -65.0 or longitude >= 165.0
		if lon_ok:
			amp_mult    *= 0.60
			mean_offset += 2.0
			precip_mult *= 1.4

	return {"precip_mult": precip_mult, "amp_mult": amp_mult, "mean_offset": mean_offset}

static func _prevailing_wind_dir(latitude: float) -> float:
	# 위도별 탁월풍 방향 (바람이 '불어오는' 방향, 나침반 각도)
	# 북반구 기준: 무역풍대(0-30°) NE→E, 편서풍대(30-60°) WSW, 극동풍대(60-90°) ENE
	var abs_lat: float = abs(latitude)
	var nh_dir: float
	if abs_lat <= 30.0:
		# 무역풍대: 북동(45°) → 아열대고압 동풍(90°)
		nh_dir = lerp(45.0, 90.0, abs_lat / 30.0)
	elif abs_lat <= 60.0:
		# 편서풍대: 서남서(230°) → 서서남(245°)
		nh_dir = lerp(230.0, 245.0, (abs_lat - 30.0) / 30.0)
	else:
		# 극동풍대: 동북동(60°) 고정
		nh_dir = 60.0
	if latitude < 0.0:
		# 남반구: 남북 성분 반전 (180° - 북반구 방향) → SE 무역풍, WNW 편서풍 등
		nh_dir = fmod(180.0 - nh_dir + 360.0, 360.0)
	return nh_dir

# 구간 선형 보간 헬퍼는 SkyMath.gd로 통합. SkyMath._lerp_breakpoints 참조.
