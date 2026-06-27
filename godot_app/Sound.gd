class_name WorldSimSound
extends Node

const RAIN_FALL_TIME_SEC: float = 2.1

var lightning_flash_intensity: float = 0.0  # Sky가 읽음 — 0=없음, 1=최대섬광
var lightning_bolt_dist_km: float   = 5.0  # Sky가 읽음 — 볼트 위치 계산용

var _flash_distance: float = 5.0   # 현재 낙뢰 거리 (km)
var _flash_decay_t: float  = -1.0  # 섬광 경과 시간 (-1=비활성)
var _restrike_count: int   = 0     # 남은 재섬광 횟수
var _restrike_timer: float = -1.0  # 다음 재섬광까지 시간 (초)

var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _snow_player: AudioStreamPlayer
var _thunder_streams: Array = []

var _was_raining: bool = false
var _rain_started_elapsed: float = 0.0
var _rain_tier: int = -1
var _pending_thunder_in: float = -1.0
var _pending_thunder_volume: float = 1.0

func build() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master_idx, false)
	AudioServer.set_bus_volume_db(master_idx, 0.0)

	_rain_player = AudioStreamPlayer.new()
	_rain_player.stream = _load_loop_wav("res://sounds/rain_medium.wav")
	_rain_player.bus = "Master"
	add_child(_rain_player)

	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _load_loop_wav("res://sounds/wind_loop.wav")
	_wind_player.bus = "Master"
	add_child(_wind_player)

	_snow_player = AudioStreamPlayer.new()
	_snow_player.stream = _load_loop_wav("res://sounds/snow_loop.wav")
	_snow_player.bus = "Master"
	add_child(_snow_player)

	for snd_name in ["thunder_close", "thunder_mid", "thunder_far"]:
		var s = load("res://sounds/%s.wav" % snd_name)
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_DISABLED
			s.loop_end = int(s.get_length() * s.mix_rate)
		if s != null:
			_thunder_streams.append(s)

	_rain_player.play()
	_wind_player.play()
	_snow_player.play()

func update(weather_type: String, wind_enabled: bool, wind_speed: float, rain_rate: float, delta: float) -> void:
	_update_rain(weather_type, wind_enabled, wind_speed, rain_rate, delta)
	_update_thunder(weather_type, rain_rate, delta)

# ── 내부 ─────────────────────────────────────────────────────────────
func _update_rain(weather_type: String, wind_enabled: bool, wind_speed: float, rain_rate: float, delta: float) -> void:
	var is_rain: bool = weather_type == "RAIN"
	if is_rain and not _was_raining:
		_rain_started_elapsed = 0.0
	if is_rain:
		_rain_started_elapsed += delta
	_was_raining = is_rain
	var fade_in: float = clampf(_rain_started_elapsed / RAIN_FALL_TIME_SEC, 0.0, 1.0)

	var tier: int = 0 if rain_rate <= 7.6 else (1 if rain_rate <= 50.0 else 2)
	if is_rain and tier != _rain_tier:
		_rain_tier = tier
		var path: String = ["res://sounds/rain_light.wav", "res://sounds/rain_medium.wav", "res://sounds/rain_heavy.wav"][tier]
		_rain_player.stream = _load_loop_wav(path)
		_rain_player.play()

	_rain_player.volume_db = linear_to_db(clampf(rain_rate / 25.0, 0.0, 1.0) * fade_in) if is_rain else -80.0
	_wind_player.volume_db = linear_to_db(clampf(wind_speed / 5.0, 0.0, 1.2)) if (wind_enabled and wind_speed > 0.05) else -80.0
	var snow_vol: float = clampf(0.10 * clampf(rain_rate / 30.0, 0.2, 1.0), 0.03, 0.35)
	_snow_player.volume_db = linear_to_db(snow_vol) if weather_type == "SNOW" else -80.0

func _update_thunder(weather_type: String, rain_rate: float, delta: float) -> void:
	# ── 1. 섬광 지수감쇠 ───────────────────────────────────────────────
	# 가까울수록 밝음: 0.3km→강도≈1.0, 6km→강도≈0.20
	if _flash_decay_t >= 0.0:
		_flash_decay_t += delta
		var max_i: float = clampf(1.2 - _flash_distance / 7.0, 0.20, 1.0)
		lightning_flash_intensity = max_i * exp(-_flash_decay_t * 12.0)
		if lightning_flash_intensity < 0.01:
			lightning_flash_intensity = 0.0
			_flash_decay_t = -1.0

	# ── 2. 재섬광 타이머 ────────────────────────────────────────────────
	# 한 낙뢰 내에서 0~3회 다트 리더 재방전 (0.05~0.10s 간격)
	if _restrike_count > 0:
		_restrike_timer -= delta
		if _restrike_timer <= 0.0:
			_restrike_count -= 1
			_flash_decay_t = 0.0
			# 재섬광은 첫 섬광보다 50~80% 강도 (에너지 감소)
			lightning_flash_intensity = clampf(1.2 - _flash_distance / 7.0, 0.20, 1.0) * randf_range(0.50, 0.80)
			_restrike_timer = randf_range(0.05, 0.10)

	# ── 3. 대기 중인 천둥음 재생 ────────────────────────────────────────
	if _pending_thunder_in >= 0.0:
		_pending_thunder_in -= delta
		if _pending_thunder_in <= 0.0:
			_play_thunder(_pending_thunder_volume, _flash_distance)
			_pending_thunder_in = -1.0

	# ── 4. 새 낙뢰 이벤트 생성 ──────────────────────────────────────────
	# 진행 중인 섬광·재섬광·천둥 대기가 모두 없을 때만 새 이벤트 가능
	if _pending_thunder_in < 0.0 and _restrike_count == 0 and _flash_decay_t < 0.0 and weather_type == "RAIN":
		var threshold: float = 7.6
		if rain_rate > threshold:
			var intensity: float = clampf((rain_rate - threshold) / (60.0 - threshold), 0.0, 1.0)
			var avg_interval: float = max(4.0, 70.0 - 65.0 * intensity * intensity)
			if randf() < delta / avg_interval:
				_flash_distance         = randf_range(0.3, 6.0)
				lightning_bolt_dist_km  = _flash_distance
				var dist_f: float       = clampf(_flash_distance / 6.0, 0.0, 1.0)
				_pending_thunder_in     = _flash_distance * 1000.0 / 343.0
				_pending_thunder_volume = clampf(1.4 - dist_f * 1.1, 0.15, 1.3)
				_restrike_count         = randi_range(0, 3)
				_restrike_timer         = randf_range(0.05, 0.10)
				_flash_decay_t          = 0.0
				lightning_flash_intensity = clampf(1.2 - _flash_distance / 7.0, 0.20, 1.0)

func _play_thunder(volume_mult: float, distance_km: float) -> void:
	if _thunder_streams.is_empty():
		return
	var p := AudioStreamPlayer.new()
	add_child(p)
	# 거리별 음원 선택: close<1.5km, mid<3.5km, far≥3.5km
	var idx: int = 0 if distance_km < 1.5 else (1 if distance_km < 3.5 else 2)
	p.stream = _thunder_streams[min(idx, _thunder_streams.size() - 1)]
	p.volume_db = linear_to_db(clampf(volume_mult, 0.05, 2.0))
	p.finished.connect(func(): p.queue_free())
	p.play()

func _load_loop_wav(path: String) -> AudioStream:
	var s = load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s
