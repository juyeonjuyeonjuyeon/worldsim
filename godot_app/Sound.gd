class_name WorldSimSound
extends Node

const RAIN_FALL_TIME_SEC: float = 2.1

var lightning_flash_remaining: float = 0.0  # Sky가 읽어서 번개 시각 처리

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
	if _pending_thunder_in >= 0.0:
		_pending_thunder_in -= delta
		if _pending_thunder_in <= 0.0:
			_play_thunder(_pending_thunder_volume)
			_pending_thunder_in = -1.0
	elif weather_type == "RAIN":
		var threshold: float = 7.6
		if rain_rate > threshold:
			var intensity: float = clampf((rain_rate - threshold) / (60.0 - threshold), 0.0, 1.0)
			var avg_interval: float = max(4.0, 70.0 - 65.0 * intensity * intensity)
			if randf() < delta / avg_interval:
				var distance_km: float = randf_range(0.3, 6.0)
				var distance_factor: float = clampf(distance_km / 6.0, 0.0, 1.0)
				_pending_thunder_in  = distance_km * 1000.0 / 343.0
				_pending_thunder_volume = clampf(1.4 - distance_factor * 1.1, 0.15, 1.3)
				lightning_flash_remaining = 0.15

	if lightning_flash_remaining > 0.0:
		lightning_flash_remaining -= delta

func _play_thunder(volume_mult: float) -> void:
	if _thunder_streams.is_empty():
		return
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = _thunder_streams[randi() % _thunder_streams.size()]
	p.volume_db = linear_to_db(clampf(volume_mult, 0.05, 2.0))
	p.finished.connect(func(): p.queue_free())
	p.play()

func _load_loop_wav(path: String) -> AudioStream:
	var s = load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s
