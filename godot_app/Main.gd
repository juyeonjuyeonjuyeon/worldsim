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
var weather_type: String = "RAIN"   # CLEAR/CIRRUS/CUMULUS/OVERCAST/RAIN/SNOW
var rain_rate: float = 20.0
var overcast_intensity: float = 0.6
var wind_enabled: bool = true
var wind_speed: float = 1.6
var wind_direction: float = 0.0   # 나침반 방위각(0=북, 90=동, 180=남, 270=서)
var rain_streak_scale: float  = 1.0
var snow_size_scale: float    = 1.0
var show_constellations: bool = false
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

# ── 모듈 참조 ──
var _sky    = null
var _env    = null
var _sound  = null
var _camera = null
var _ui     = null

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

	_ui.settings_confirmed.connect(_on_settings_confirmed)
	_ui.view_mode_requested.connect(_set_view_mode)
	_ui.aspect_requested.connect(_set_aspect)
	_ui.test_event_requested.connect(_on_test_event)
	_ui.build(_ui_init_dict())
	_update_all(0.0)

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
	var new_rt: bool   = s.get("real_time_mode",     real_time_mode)
	if new_rt != real_time_mode:
		real_time_mode = new_rt
		elapsed_play_seconds = 0.0
	day_length_sec     = s.get("day_length_sec",     day_length_sec)
	rain_streak_scale    = s.get("rain_streak_scale",    rain_streak_scale)
	snow_size_scale      = s.get("snow_size_scale",      snow_size_scale)
	show_constellations  = s.get("show_constellations",  show_constellations)
	_ui.save_state(get_window())
	if need_rebuild:
		_ui.build(_ui_init_dict())
	_update_all(0.0)

func _on_test_event(event_name: String) -> void:
	match event_name:
		"lightning": _sound.trigger_lightning()
		"meteor":    _sky.trigger_meteor(false)
		"shower":    _sky.trigger_meteor(true)
		"comet":     _sky.trigger_comet_test()

func _set_view_mode(mode: String) -> void:
	_camera.set_view_mode(mode)

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
	_update_all(delta)

func _update_all(delta: float) -> void:
	if real_time_mode:
		elapsed_play_seconds += delta
	var dt: Dictionary = _current_datetime()
	var hour_utc: float = dt["hour"] - utc_offset
	var sun_altaz: Vector2 = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var moon: Dictionary = Astronomy.moon_state(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var cloud_props: Dictionary = _weather_cloud_props()

	sim_temperature = _estimate_temperature(dt["month"], fmod(dt["hour"], 24.0))
	_sky.show_constellations = show_constellations
	_sky.update(
		sun_altaz, moon, cloud_props,
		weather_type, wind_speed, wind_direction, wind_enabled,
		_sound.lightning_flash_intensity,
		_sound.lightning_bolt_dist_km,
		dt, hour_utc, latitude, longitude,
		sim_temperature, _env.ground_wetness, delta)

	_env.update(
		weather_type, rain_rate, wind_speed, wind_direction, wind_enabled,
		cloud_props, sim_month,
		_sky.sky_brightness_safe, _sky.sky_overcast_amt_current,
		rain_streak_scale, snow_size_scale,
		sim_temperature, delta)

	_sound.update(weather_type, wind_enabled, wind_speed, rain_rate, delta)

	_camera.update(delta)

	if _ui:
		var h: int = int(dt["hour"])
		var m: int = int(fmod(dt["hour"], 1.0) * 60)
		var lat_str: String = "%.2f°%s" % [abs(latitude), "N" if latitude >= 0.0 else "S"]
		var lng_str: String = "%.2f°%s" % [abs(longitude), "E" if longitude >= 0.0 else "W"]
		_ui.update_status("%04d-%02d-%02d  %02d:%02d  |  %s  %s" % [
			dt["year"], dt["month"], dt["day"], h, m, lat_str, lng_str])

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
			var tau: float = _lerp_breakpoints(rain_rate, RAIN_RATE_BREAKPOINTS, RAIN_TAU_BREAKPOINTS)
			return {"tau": tau, "okta": clampf(0.85 + 0.15 * clampf(rain_rate / 30.0, 0.0, 1.0), 0.85, 1.0), "rain_rate": rain_rate}
		"SNOW":
			var tau_s: float = _lerp_breakpoints(rain_rate, RAIN_RATE_BREAKPOINTS, SNOW_TAU_BREAKPOINTS)
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

static func _estimate_temperature(month: int, hour_local: float) -> float:
	# 서울 월평균 기온 (1월~12월, °C) — 기상청 평년값 기반
	const MONTHLY_AVG: Array = [-2.5, 0.3, 5.2, 12.1, 17.2, 22.1, 25.0, 25.7, 21.4, 14.8, 7.2, 0.4]
	var base: float = MONTHLY_AVG[clampi(month - 1, 0, 11)]
	# 일교차: 오후 2시 최고, 새벽 최저. 진폭 ±6°C
	var day_offset: float = -6.0 * cos((hour_local - 14.0) * PI / 12.0)
	return base + day_offset

static func _lerp_breakpoints(x: float, xs: Array, ys: Array) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(xs.size() - 1):
		if x <= xs[i + 1]:
			var f: float = (x - xs[i]) / (xs[i + 1] - xs[i])
			return lerp(ys[i], ys[i + 1], f)
	return ys[ys.size() - 1]
