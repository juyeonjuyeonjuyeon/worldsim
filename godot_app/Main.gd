extends Node3D
## WS Forest Weather — 독립 실행판(Godot). forest_rain_live.py(블렌더 실시간
## 도구)와 같은 날씨/시간/조명 개념을 별도 엔진으로 재구현 — 블렌더 설치 없이
## 더블클릭으로 실행되는 .exe로 빌드하기 위함. 천체력은 skyfield 대신
## Astronomy.gd(NOAA 태양 공식 + Meeus 저정밀 달 공식)을 사용.

const FIELD_HALF: float = 15.0

# ── 실제 기상학 기준값 ──
# 광학두께(optical depth, τ)는 구름이 빛을 얼마나 막는지의 실제 물리량 —
# 베어-램버트 법칙(Beer-Lambert law)으로 직사광 투과율 = exp(-τ). 불투명/반투명
# 경계가 τ=10(AMS Glossary of Meteorology). 얇은 시러스 <0.1~1, 적운 1~10대,
# 대형 적운형 강수운(쿠물로님버스)은 수십~1000 이상까지 올라감(AMS Glossary).
const TAU_CIRRUS: float = 0.6
const TAU_CUMULUS: float = 4.0
const TAU_OVERCAST: float = 18.0
# WMO 강수강도 경계(mm/hr): 약한 비 ≤2.5, 보통 2.5~7.6, 강한 7.6~50, 폭우 >50
# (WMO 가이드 및 각국 기상청 공통 분류). 이 경계에서 강수를 만드는 전형적
# 구름(약~보통 비=난층운, 강한 비~폭우=적운형 강수운)의 광학두께를 매칭함.
const RAIN_RATE_BREAKPOINTS: Array = [0.0, 2.5, 7.6, 50.0]
const RAIN_TAU_BREAKPOINTS: Array = [8.0, 12.0, 25.0, 70.0]
const SNOW_TAU_BREAKPOINTS: Array = [6.0, 10.0, 20.0, 55.0]
# WMO 옥타(하늘을 8등분해 구름이 덮은 칸 수) — 시러스/큐뮬러스는 흔히 일부만
# 덮고(부분 옥타), 흐림과 지속 강수운은 거의 항상 전천(8/8)을 덮음.
const OKTA_CIRRUS: float = 3.0 / 8.0
const OKTA_CUMULUS: float = 4.0 / 8.0
const OKTA_OVERCAST: float = 8.0 / 8.0

# ── 날씨/시간 상태 (블렌더판 WS_WeatherProps와 대응) ──
var weather_type: String = "RAIN"   # CLEAR/CIRRUS/CUMULUS/OVERCAST/RAIN/SNOW
var rain_rate: float = 20.0
var wind_enabled: bool = true
var wind_speed: float = 1.6
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

# ── 노드 참조 ──
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var moon_mesh: MeshInstance3D
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var stars_mm: MultiMeshInstance3D
var cloud_mesh: MeshInstance3D
var cloud_shader_mat: ShaderMaterial
var rain_particles: GPUParticles3D
var snow_particles: GPUParticles3D
var ground_mesh: MeshInstance3D
var ground_mat: StandardMaterial3D
var leaf_mats: Array = []
var leaf_base_colors: Array = []
var tree_sway_pivots: Array = []
var tree_sway_phase: Array = []
var tree_sway_freq: Array = []
var sway_time: float = 0.0
var ground_wetness: float = 0.0
var ground_snow: float = 0.0
var puddle_nodes: Array = []
var puddle_max_r: Array = []
var sky_brightness_safe: float = 1.0
var cloud_tau_current: float = 0.0
var sky_overcast_amt_current: float = 0.0

# ── 자유 카메라(WASD 이동 + 우클릭 드래그 시점) ──
var camera: Camera3D
var cam_yaw: float = 0.0
var cam_pitch: float = 0.0
var cam_move_speed: float = 8.0
var mouse_look_active: bool = false

var star_data: Array = []

var rain_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer
var snow_player: AudioStreamPlayer
var thunder_streams: Array = []
var next_thunder_in: float = -1.0
var pending_thunder_in: float = -1.0
var pending_thunder_volume: float = 1.0
var lightning_flash_remaining: float = 0.0

const RAIN_FALL_TIME_SEC: float = 1.4  # y=9 출발 빗방울이 땅까지 떨어지는 대략적 시간
var _was_raining: bool = false
var _rain_started_elapsed: float = 0.0
var _rain_tier: int = -1

var ui_status_label: Label

func _ready() -> void:
	randomize()
	_load_star_catalog()
	_build_ground()
	_build_trees()
	_build_puddles()
	_build_sky_and_lights()
	_build_camera()
	_build_stars()
	_build_clouds()
	_build_rain_snow()
	_build_sound()
	_build_ui()
	_update_all(0.0)

func _build_camera() -> void:
	# 블렌더판 카메라(8,-16,6.5, Z-up)를 Y-up으로 옮긴 초기 위치/각도에서 시작 —
	# 이후엔 WASD+마우스로 자유롭게 움직일 수 있음(_process의 카메라 처리부 참고).
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.current = true
	add_child(camera)
	camera.position = Vector3(8, 6.5, 16)
	camera.look_at_from_position(Vector3(8, 6.5, 16), Vector3(0, 1.5, 0), Vector3.UP)
	var fwd: Vector3 = -camera.global_transform.basis.z
	cam_yaw = atan2(-fwd.x, -fwd.z)
	cam_pitch = asin(clampf(fwd.y, -1.0, 1.0))

# =====================================================================
# 빌드
# =====================================================================
func _load_star_catalog() -> void:
	var f := FileAccess.open("res://stars.json", FileAccess.READ)
	if f == null:
		push_warning("stars.json을 못 찾음 — 별 없이 진행")
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_ARRAY:
		star_data = parsed

func _build_ground() -> void:
	ground_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	ground_mesh.mesh = plane
	ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.16, 0.24, 0.08)
	ground_mat.roughness = 0.85
	ground_mesh.material_override = ground_mat
	add_child(ground_mesh)

	# 이전엔 horizon이 따로 고정 색(hmat)을 썼는데, ground_mat은 비/눈에 따라
	# 매 프레임 색이 바뀌므로(_update_weather_visual) 비가 올수록 안쪽 땅만
	# 점점 어두워지고 바깥 지평선은 그대로라 60m 경계가 색 차이로 또렷한
	# 선처럼 보였음. 같은 재질(ground_mat)을 공유시켜 항상 같이 바뀌게 함.
	var horizon := MeshInstance3D.new()
	var hp := PlaneMesh.new()
	hp.size = Vector2(800, 800)
	horizon.mesh = hp
	horizon.position.y = -0.01  # z-fighting 방지용 최소 오프셋만(이전 -0.05는 단차로 보일 만큼 컸음)
	horizon.material_override = ground_mat
	add_child(horizon)

func _make_tree(x: float, z: float, scale_: float, seed_: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var trunk_h: float = 2.8 * scale_
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.10 * scale_
	cyl.bottom_radius = 0.14 * scale_
	cyl.height = trunk_h
	trunk.mesh = cyl
	trunk.position = Vector3(x, trunk_h * 0.5, z)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.18, 0.11, 0.04)
	trunk_mat.roughness = 0.9
	trunk.material_override = trunk_mat
	add_child(trunk)

	var n_leaves: int = rng.randi_range(8, 13)
	var crown_base: float = trunk_h * 0.55
	# 바람에 흔들리는 단위 — 잎들을 이 피벗에 매달아 피벗만 회전시키면
	# 나무 전체가 바람 세기에 비례해 휘청거림(블렌더판 sway_pivot과 동일).
	var pivot := Node3D.new()
	pivot.position = Vector3(x, crown_base, z)
	add_child(pivot)
	tree_sway_pivots.append(pivot)
	tree_sway_phase.append(rng.randf_range(0.0, TAU))
	tree_sway_freq.append(rng.randf_range(0.3, 0.6))
	for i in range(n_leaves):
		var t: float = float(i) / float(n_leaves)
		var sp: float = (1.0 - t * 0.4) * scale_ * 1.1
		var ang: float = rng.randf_range(0.0, TAU)
		var cx: float = sp * cos(ang) * rng.randf_range(0.2, 1.0)
		var cz: float = sp * sin(ang) * rng.randf_range(0.2, 1.0)
		var cy: float = t * trunk_h * 0.7 + rng.randf_range(-0.1, 0.1) * scale_
		var cr: float = scale_ * rng.randf_range(0.30, 0.55)
		var g: float = rng.randf_range(0.18, 0.30)
		var leaf := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = cr
		sph.height = cr * 2.0
		leaf.mesh = sph
		leaf.position = Vector3(cx, cy, cz)
		var leaf_color := Color(0.04, g, 0.04)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = leaf_color
		lmat.roughness = 0.9
		leaf.material_override = lmat
		pivot.add_child(leaf)
		leaf_mats.append(lmat)
		leaf_base_colors.append(leaf_color)

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(22):
		var x: float = rng.randf_range(-19, 19)
		var z: float = rng.randf_range(-19, 19)
		if abs(x) < 5 and abs(z) < 5:
			continue
		_make_tree(x, z, rng.randf_range(0.7, 1.8), rng.randi())

func _build_puddles() -> void:
	# 웅덩이는 "항상 그 자리에 고정 크기로" 있으면 안 되고 — 블렌더판처럼
	# 비가 와야 차오르고 안 오면 말라서 사라져야 함. 여기서는 최대 크기만
	# 만들어두고 실제 보이는 크기는 _update_weather_visual에서 ground_wetness
	# 비율로 매 프레임 스케일링함(0이면 사실상 안 보임).
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in range(8):
		var x: float = rng.randf_range(-12, 12)
		var z: float = rng.randf_range(-12, 12)
		var r: float = rng.randf_range(0.8, 2.4)
		var p := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 0.02
		p.mesh = cyl
		p.position = Vector3(x, 0.02, z)
		p.scale = Vector3(0.001, 1.0, 0.001)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.03, 0.06, 0.08)
		pmat.roughness = 0.05
		pmat.metallic = 0.1
		p.material_override = pmat
		add_child(p)
		puddle_nodes.append(p)
		puddle_max_r.append(r)

func _build_sky_and_lights() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.light_energy = 1.0
	sun_light.shadow_enabled = true
	add_child(sun_light)

	moon_light = DirectionalLight3D.new()
	moon_light.light_energy = 0.0
	moon_light.light_color = Color(0.75, 0.82, 1.0)
	moon_light.shadow_enabled = false
	add_child(moon_light)

	moon_mesh = MeshInstance3D.new()
	var msph := SphereMesh.new()
	msph.radius = 3.0
	msph.height = 6.0
	moon_mesh.mesh = msph
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.9, 0.9, 0.95)
	mmat.emission_enabled = true
	mmat.emission = Color(0.9, 0.9, 0.95)
	mmat.emission_energy_multiplier = 2.0
	moon_mesh.material_override = mmat
	add_child(moon_mesh)

func _build_stars() -> void:
	stars_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = max(star_data.size(), 1)
	stars_mm.multimesh = mm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1, 1, 1)
	smat.emission_enabled = true
	smat.emission = Color(1, 1, 1)
	smat.emission_energy_multiplier = 3.0
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	stars_mm.material_override = smat
	add_child(stars_mm)

func _build_clouds() -> void:
	cloud_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	cloud_mesh.mesh = plane
	cloud_mesh.position = Vector3(0, 20, 0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;
uniform float coverage : hint_range(0.0, 1.0) = 0.4;
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;
uniform float softness : hint_range(0.02, 0.6) = 0.25;
uniform vec2 drift = vec2(0.0, 0.0);
uniform vec3 cloud_color : source_color = vec3(0.85, 0.86, 0.88);
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i); float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0)); float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
void fragment() {
	vec2 uv = UV * noise_scale + drift;
	float n = noise(uv) * 0.5 + noise(uv * 2.3) * 0.3 + noise(uv * 4.1) * 0.2;
	float a = smoothstep(1.0 - coverage, 1.0 - coverage + softness, n) * density;
	// unshaded라 조명을 안 받으므로 노출 보정을 직접 안 곱하면 밤에 노출이
	// 수십만 배로 뛸 때 구름판도 그대로 하얗게 날아감 — 하늘색과 똑같은
	// "노출 안전 배율"(brightness)을 곱해서 같이 죽여줌.
	ALBEDO = cloud_color * brightness;
	ALPHA = a;
}
"""
	cloud_shader_mat = ShaderMaterial.new()
	cloud_shader_mat.shader = shader
	cloud_shader_mat.set_shader_parameter("coverage", 0.4)
	cloud_shader_mat.set_shader_parameter("density", 0.5)
	cloud_mesh.material_override = cloud_shader_mat
	add_child(cloud_mesh)

func _build_rain_snow() -> void:
	rain_particles = _make_precip_particles(false)
	add_child(rain_particles)
	snow_particles = _make_precip_particles(true)
	add_child(snow_particles)

func _make_precip_particles(is_snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 2000 if not is_snow else 1200
	p.lifetime = 3.0 if not is_snow else 8.0
	p.position = Vector3(0, 9, 0)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(FIELD_HALF, 0.1, FIELD_HALF)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 2.0 if not is_snow else 25.0
	mat.gravity = Vector3(0, -9.0 if not is_snow else -1.2, 0)
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.0
	p.process_material = mat
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.4, 0.02) if not is_snow else Vector3(0.05, 0.05, 0.05)
	p.draw_pass_1 = mesh
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.78, 0.87, 1.0, 0.7) if not is_snow else Color(0.95, 0.96, 0.98, 0.9)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = pmat
	return p

func _build_sound() -> void:
	# Master 버스가 어떤 이유로든 음소거/볼륨 0으로 남아있을 가능성을 방어
	var master_idx: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master_idx, false)
	AudioServer.set_bus_volume_db(master_idx, 0.0)

	rain_player = AudioStreamPlayer.new()
	rain_player.stream = _load_loop_wav("res://sounds/rain_medium.wav")
	rain_player.bus = "Master"
	add_child(rain_player)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = _load_loop_wav("res://sounds/wind_loop.wav")
	wind_player.bus = "Master"
	add_child(wind_player)
	snow_player = AudioStreamPlayer.new()
	snow_player.stream = _load_loop_wav("res://sounds/snow_loop.wav")
	snow_player.bus = "Master"
	add_child(snow_player)
	for name in ["thunder_close", "thunder_mid", "thunder_far"]:
		var s := load("res://sounds/%s.wav" % name)
		if s != null:
			thunder_streams.append(s)
	rain_player.play()
	wind_player.play()
	snow_player.play()

func _load_loop_wav(path: String) -> AudioStream:
	# loop_end를 0으로 두면(기본값) 루프 구간이 "0프레임"이 되어 재생 시작과
	# 거의 동시에 끝나버려(=playing이 금방 false) 소리가 전혀 안 들리는
	# 원인이었음 — 전체 길이를 프레임 수로 환산해 명시적으로 채워줘야 함.
	var s = load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s

# =====================================================================
# UI
# =====================================================================
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(280, 520)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(10, 10)
	vb.size = Vector2(260, 500)
	panel.add_child(vb)

	var weather_opt := OptionButton.new()
	for w in ["CLEAR", "CIRRUS", "CUMULUS", "OVERCAST", "RAIN", "SNOW"]:
		weather_opt.add_item(w)
	weather_opt.select(4)
	weather_opt.item_selected.connect(func(idx):
		weather_type = weather_opt.get_item_text(idx))
	vb.add_child(_labeled(vb, "날씨", weather_opt))

	vb.add_child(_slider_row(vb, "강수강도", 0.5, 60.0, rain_rate, func(v): rain_rate = v))
	var wind_check := CheckBox.new()
	wind_check.text = "바람"
	wind_check.button_pressed = wind_enabled
	wind_check.toggled.connect(func(p): wind_enabled = p)
	vb.add_child(wind_check)
	vb.add_child(_slider_row(vb, "바람 속도", 0.0, 12.0, wind_speed, func(v): wind_speed = v))
	vb.add_child(_slider_row(vb, "위도", -90.0, 90.0, latitude, func(v): latitude = v))
	vb.add_child(_slider_row(vb, "경도", -180.0, 180.0, longitude, func(v): longitude = v))
	vb.add_child(_slider_row(vb, "UTC오프셋", -12.0, 14.0, utc_offset, func(v): utc_offset = v))
	vb.add_child(_slider_row(vb, "시간(현지)", 0.0, 24.0, time_of_day, func(v): time_of_day = v))

	var rt_check := CheckBox.new()
	rt_check.text = "재생으로 시간 자동 진행"
	rt_check.button_pressed = real_time_mode
	rt_check.toggled.connect(func(p): real_time_mode = p; elapsed_play_seconds = 0.0)
	vb.add_child(rt_check)

	vb.add_child(_slider_row(vb, "하루 길이(초)", 5.0, 600.0, day_length_sec, func(v): day_length_sec = v))

	ui_status_label = Label.new()
	ui_status_label.text = "..."
	vb.add_child(ui_status_label)

	var cam_help := Label.new()
	cam_help.text = "카메라: 우클릭 드래그로 시점, WASD 이동, Space/Shift 위아래, 스크롤로 속도조절"
	cam_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(cam_help)

func _labeled(_parent: Control, text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	box.add_child(control)
	return box

func _slider_row(_parent: Control, text: String, lo: float, hi: float, val: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = "%s: %.2f" % [text, val]
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 500.0
	s.value = val
	s.custom_minimum_size = Vector2(240, 20)
	s.value_changed.connect(func(v):
		on_change.call(v)
		l.text = "%s: %.2f" % [text, v])
	box.add_child(s)
	return box

# =====================================================================
# 매 프레임 갱신
# =====================================================================
func _process(delta: float) -> void:
	_update_all(delta)
	_update_camera(delta)

func _input(event: InputEvent) -> void:
	# 우클릭을 누르고 있는 동안만 마우스로 시점 회전(그동안 마우스 커서를
	# 숨기고 가둠) — 떼면 커서가 돌아와 UI 패널 슬라이더를 다시 조작할 수 있음.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		mouse_look_active = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_look_active else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and mouse_look_active:
		var sens: float = 0.0035
		cam_yaw -= event.relative.x * sens
		cam_pitch = clampf(cam_pitch - event.relative.y * sens, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event is InputEventMouseButton and event.pressed and mouse_look_active:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_move_speed = clampf(cam_move_speed * 1.2, 0.5, 200.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_move_speed = clampf(cam_move_speed / 1.2, 0.5, 200.0)

func _update_camera(delta: float) -> void:
	camera.transform.basis = Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	# 이전엔 우클릭을 누르고 있을 때만 WASD가 동작했음(마우스 시점 모드와
	# 묶여있었음) — "키보드로 이동, 마우스로 시점"을 동시에 양손으로 하기
	# 불편하고, 우클릭 없이 WASD만 눌러보면 아무 반응이 없어 "키보드 조작이
	# 안 된다"로 보였을 만한 원인. 텍스트 입력 필드가 없는 UI라 키보드가
	# 슬라이더 조작과 충돌하지 않으므로, 이동은 항상 켜두고 시점 회전만
	# 우클릭 드래그로 제한(마우스가 슬라이더를 조작할 수 있게).
	var dir := Vector3.ZERO
	var basis: Basis = camera.transform.basis
	if Input.is_key_pressed(KEY_W):
		dir -= basis.z
	if Input.is_key_pressed(KEY_S):
		dir += basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= basis.x
	if Input.is_key_pressed(KEY_D):
		dir += basis.x
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir.length_squared() > 0.0:
		var speed: float = cam_move_speed * (2.5 if Input.is_key_pressed(KEY_CTRL) else 1.0)
		camera.position += dir.normalized() * speed * delta

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

func _update_all(delta: float) -> void:
	if real_time_mode:
		elapsed_play_seconds += delta
	var dt: Dictionary = _current_datetime()
	var hour_utc: float = dt["hour"] - utc_offset
	var sun_altaz: Vector2 = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var moon: Dictionary = Astronomy.moon_state(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)

	_update_sky_and_lights(sun_altaz, moon)
	_update_stars(dt, hour_utc)
	_update_weather_visual(delta)
	_update_tree_sway(delta)
	_update_sound(delta)
	_update_thunder(delta)

	if ui_status_label:
		var thunder_status: String = ""
		if pending_thunder_in >= 0.0:
			thunder_status = " | 천둥 도착까지 %.1f초" % pending_thunder_in
		ui_status_label.text = "%04d-%02d-%02d %05.2f시 | 태양고도 %.1f | 달위상 %.2f%s" % [
			dt["year"], dt["month"], dt["day"], dt["hour"], sun_altaz.x, moon["illum"], thunder_status]

const STARLIGHT_FLOOR_LUX: float = 0.0008
const REF_LUX: float = 100000.0

static func _sun_illuminance(alt_deg: float) -> float:
	var anchors_alt := [-18.0, -12.0, -6.0, 0.0, 10.0, 30.0, 60.0, 90.0]
	var anchors_lux := [0.0008, 0.008, 3.4, 400.0, 12000.0, 50000.0, 90000.0, 100000.0]
	var a: float = clampf(alt_deg, -18.0, 90.0)
	for i in range(anchors_alt.size() - 1):
		if a <= anchors_alt[i + 1] or i == anchors_alt.size() - 2:
			var t0: float = anchors_alt[i]
			var t1: float = anchors_alt[i + 1]
			var f: float = 0.0
			if t1 > t0:
				f = clampf((a - t0) / (t1 - t0), 0.0, 1.0)
			var l0: float = log(anchors_lux[i]) / log(10.0)
			var l1: float = log(anchors_lux[i + 1]) / log(10.0)
			return pow(10.0, lerp(l0, l1, f))
	return anchors_lux[anchors_lux.size() - 1]

static func _exposure_for_lux(total_lux: float) -> float:
	var anchors_lux := [STARLIGHT_FLOOR_LUX, 1.0, 3.4, 400.0, 12000.0, 100000.0]
	var anchors_ev := [19.5, 19.0, 7.0, 2.0, 0.0, 0.0]
	var lux: float = max(total_lux, STARLIGHT_FLOOR_LUX)
	var log_lux: float = log(lux) / log(10.0)
	for i in range(anchors_lux.size() - 1):
		var l0: float = log(anchors_lux[i]) / log(10.0)
		var l1: float = log(anchors_lux[i + 1]) / log(10.0)
		if log_lux <= l1 or i == anchors_lux.size() - 2:
			var f: float = 0.0
			if l1 > l0:
				f = clampf((log_lux - l0) / (l1 - l0), 0.0, 1.0)
			return lerp(anchors_ev[i], anchors_ev[i + 1], f)
	return anchors_ev[anchors_ev.size() - 1]

static func _lerp_breakpoints(x: float, xs: Array, ys: Array) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(xs.size() - 1):
		if x <= xs[i + 1]:
			var f: float = (x - xs[i]) / (xs[i + 1] - xs[i])
			return lerp(ys[i], ys[i + 1], f)
	return ys[ys.size() - 1]

## 날씨/강수강도 → 실제 광학두께(τ)·옥타(구름량). 위 실측 기상학 기준값을
## 그대로 사용 — "비가 강할수록 임의로 더 흐리게"가 아니라 WMO 강수강도
## 구간과 그 구간을 만드는 실제 구름 종류의 광학두께를 매칭한 것.
func _weather_cloud_props() -> Dictionary:
	match weather_type:
		"CIRRUS":
			return {"tau": TAU_CIRRUS, "okta": OKTA_CIRRUS}
		"CUMULUS":
			return {"tau": TAU_CUMULUS, "okta": OKTA_CUMULUS}
		"OVERCAST":
			return {"tau": TAU_OVERCAST, "okta": OKTA_OVERCAST}
		"RAIN":
			var tau: float = _lerp_breakpoints(rain_rate, RAIN_RATE_BREAKPOINTS, RAIN_TAU_BREAKPOINTS)
			return {"tau": tau, "okta": clampf(0.85 + 0.15 * clampf(rain_rate / 30.0, 0.0, 1.0), 0.85, 1.0)}
		"SNOW":
			var tau_s: float = _lerp_breakpoints(rain_rate, RAIN_RATE_BREAKPOINTS, SNOW_TAU_BREAKPOINTS)
			return {"tau": tau_s, "okta": clampf(0.80 + 0.15 * clampf(rain_rate / 30.0, 0.0, 1.0), 0.80, 1.0)}
	return {"tau": 0.0, "okta": 0.0}

func _altaz_to_dir(alt_deg: float, az_deg: float) -> Vector3:
	var elev := deg_to_rad(alt_deg)
	var az := deg_to_rad(az_deg)
	# 북=+Z, 동=+X 가정(나침반 방위각 그대로)
	var x: float = sin(az) * cos(elev)
	var z: float = cos(az) * cos(elev)
	var y: float = sin(elev)
	return Vector3(x, y, z)

func _update_sky_and_lights(sun_altaz: Vector2, moon: Dictionary) -> void:
	var elevation: float = sun_altaz.x
	var azimuth: float = sun_altaz.y
	var sun_dir: Vector3 = _altaz_to_dir(elevation, azimuth)
	sun_light.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)

	var moon_alt: float = moon["alt"]
	var moon_az: float = moon["az"]
	var moon_illum: float = moon["illum"]
	var moon_dir: Vector3 = _altaz_to_dir(moon_alt, moon_az)
	moon_light.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	moon_mesh.position = moon_dir * 100.0
	moon_mesh.visible = moon_alt > -2.0

	var daylight: float = clampf((elevation + 6.0) / 26.0, 0.0, 1.0)
	var night_blend: float = clampf(-elevation / 6.0, 0.0, 1.0)
	var white := Color(1, 1, 1)
	var orange := Color(1.0, 0.6, 0.3)
	var moonlt := Color(0.65, 0.72, 0.95)
	var warm: float = clampf(1.0 - elevation / 20.0, 0.0, 1.0)
	var day_or_sunset: Color = white.lerp(orange, warm)
	var sun_color: Color = day_or_sunset.lerp(moonlt, night_blend)
	sun_light.light_color = sun_color

	var sun_lux: float = _sun_illuminance(elevation)
	var moon_lux: float = 0.0
	if moon_alt > 0.0:
		moon_lux = 0.27 * moon_illum * sin(deg_to_rad(moon_alt))
	var total_lux: float = sun_lux + moon_lux + STARLIGHT_FLOOR_LUX

	# 인간 눈 노출 보정 — 밤에는 최대 2^19.5(~74만)배까지 밝기를 끌어올림.
	# 빛(태양/달 램프)과 하늘색 둘 다 이 배율을 그대로 맞으면 박명 중간
	# 어디선가(꼭 깊은 밤만의 문제가 아니라 노출이 이미 큰 모든 구간에서)
	# 하얗게 날아감 — "노출×밝기 ≤ 안전한 상한"이 항상 보장되도록 노출의
	# 역수로 직접 캡을 걸어야 어느 시각에도 절대 안 날아감.
	var exposure_ev: float = _exposure_for_lux(total_lux)
	if lightning_flash_remaining > 0.0:
		exposure_ev = 0.0
	var exposure_mult: float = pow(2.0, exposure_ev)
	sun_light.light_energy = min(clampf(sun_lux / 100000.0 * 3.0, 0.0, 6.0), 6.0 / exposure_mult)
	moon_light.light_energy = min(clampf(moon_lux / 0.27 * 0.6, 0.0, 0.6), 0.6 / exposure_mult)

	var day_sunset_brightness: float = min(1.0, 1.0 / exposure_mult)
	sky_brightness_safe = day_sunset_brightness
	var sky_night_blend: float = clampf((-elevation - 6.0) / 12.0, 0.0, 1.0)
	var day_top := Color(0.35, 0.55, 0.95) * day_sunset_brightness
	var sunset_top := Color(0.45, 0.35, 0.55) * day_sunset_brightness
	var night_top := Color(0.0000001, 0.000000115, 0.00000016)
	var top: Color = day_top.lerp(sunset_top, warm * (1.0 - sky_night_blend)).lerp(night_top, sky_night_blend)
	var day_horizon := Color(0.75, 0.80, 0.90) * day_sunset_brightness
	var sunset_horizon := Color(1.0, 0.55, 0.30) * day_sunset_brightness
	var night_horizon := Color(0.00000005, 0.00000005, 0.00000008)
	var horizon: Color = day_horizon.lerp(sunset_horizon, warm * (1.0 - sky_night_blend)).lerp(night_horizon, sky_night_blend)

	# 비/흐림/눈일 때는 하늘 자체가 구름에 덮여 회색빛으로 보여야 함 — 지금까지는
	# 구름판(평면)만 깔리고 그 뒤 하늘색은 맑은 날과 똑같아서 "비 오는데 하늘은
	# 쌩쌩한 파란 하늘" 같은 모순이 있었음. 낮~박명 구간에만 회색을 섞고(밤엔
	# 이미 night_top이 알아서 어두워지므로 안 더함).
	# τ(광학두께)는 위 _weather_cloud_props()에서 실제 WMO 강수강도 구간 +
	# AMS 기상학 사전의 구름 광학두께를 매칭한 실측 기준값. "흐려 보이는 정도"는
	# 베어-램버트 형태(포화 지수곡선)를 빌려 1-exp(-τ/12)로 — τ 자체는 실측이지만
	# 이 정규화 상수(12)는 "사람이 보기에 흐려 보이는 정도"를 정량화하는 단일
	# 표준 공식이 없어서 시각적으로 고른 값임(정직하게 밝힘).
	var cloud_props: Dictionary = _weather_cloud_props()
	var cloud_tau: float = cloud_props["tau"]
	cloud_tau_current = cloud_tau
	var direct_transmittance: float = exp(-cloud_tau)  # 실제 베어-램버트 직사광 투과율
	var sky_overcast_amt: float = 1.0 - exp(-cloud_tau / 12.0)
	sky_overcast_amt_current = sky_overcast_amt
	var overcast_grey: Color = Color(0.42, 0.44, 0.47) * day_sunset_brightness
	top = top.lerp(overcast_grey, sky_overcast_amt * (1.0 - sky_night_blend))
	horizon = horizon.lerp(overcast_grey, sky_overcast_amt * (1.0 - sky_night_blend))

	top.a = 1.0
	horizon.a = 1.0
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	var ground_bottom: Color = Color(0.05, 0.05, 0.05) * day_sunset_brightness
	ground_bottom.a = 1.0
	sky_mat.ground_bottom_color = ground_bottom

	# 구름이 직사광을 산란시켜 디퓨즈광으로 바뀜 — 베어-램버트 투과율
	# (direct_transmittance = exp(-τ))을 그대로 곱함. 임의 비율이 아니라
	# 위에서 구한 실제 광학두께가 그대로 결정하는 실측 기반 감쇠.
	sun_light.light_energy *= direct_transmittance

	world_env.environment.tonemap_exposure = exposure_mult

	var sat: float = clampf((log(max(total_lux, 1e-5)) / log(10.0) + 2.0) / (log(400.0) / log(10.0) + 2.0), 0.0, 1.0)
	world_env.environment.adjustment_enabled = true
	world_env.environment.adjustment_saturation = lerp(0.15, 1.0, sat)

func _update_stars(dt: Dictionary, hour_utc: float) -> void:
	if star_data.is_empty():
		return
	var elevation_check: Vector2 = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var night_blend: float = clampf(-elevation_check.x / 6.0, 0.0, 1.0)
	stars_mm.visible = night_blend > 0.01
	if not stars_mm.visible:
		return
	var jd: float = Astronomy.julian_day(dt["year"], dt["month"], dt["day"], hour_utc)
	var g: float = Astronomy.gmst_deg(jd)
	var mm := stars_mm.multimesh
	var radius: float = 400.0
	var n: int = star_data.size()
	for i in range(n):
		var star: Dictionary = star_data[i]
		var altaz: Vector2 = Astronomy.radec_to_altaz(star["ra"], star["dec"], g, latitude, longitude)
		var dir: Vector3 = _altaz_to_dir(altaz.x, altaz.y)
		var mag: float = star["mag"]
		var scale_: float = clampf(remap(mag, -1.5, 5.0, 2.5, 0.3), 0.3, 2.5)
		var xf := Transform3D(Basis().scaled(Vector3(scale_, scale_, scale_)), dir * radius)
		mm.set_instance_transform(i, xf)
	# 구름이 끼면(흐림/비/큐뮬러스 등) 별이 가려져 덜 보여야 함 — 맑은 밤이
	# 구름 낀 밤보다 별이 또렷한 실제 현상. WMO 옥타(하늘을 덮은 비율)를
	# 그대로 "가려지는 비율"로 씀 — 옥타 자체가 이미 실측 기준값.
	var cloud_block: float = _weather_cloud_props()["okta"]
	var star_vis: float = night_blend * (1.0 - cloud_block)
	var mat: StandardMaterial3D = stars_mm.material_override
	mat.emission_energy_multiplier = lerp(0.0, 4.0, star_vis)

func _update_weather_visual(delta: float) -> void:
	var is_rain: bool = weather_type == "RAIN"
	var is_snow: bool = weather_type == "SNOW"
	rain_particles.emitting = is_rain
	snow_particles.emitting = is_snow

	# 구름의 모양(고도/결 크기/경계 부드러움)은 시각적 스타일 선택이지만, 범위
	# (coverage=옥타)·짙기(density)·색은 위 _weather_cloud_props()의 실제 WMO
	# 강수강도/광학두께 기준값에서 그대로 가져옴 — 비/눈이 강할수록 이미 거기서
	# τ가 커지므로 여기서 또 따로 강도를 매칭할 필요가 없음(이중 적용 방지).
	var shape_presets := {
		"CLEAR": {"visible": false, "y": 20.0, "scale": 6.0, "soft": 0.25},
		"CIRRUS": {"visible": true, "y": 32.0, "scale": 14.0, "soft": 0.45},
		"CUMULUS": {"visible": true, "y": 16.0, "scale": 3.5, "soft": 0.18},
		"OVERCAST": {"visible": true, "y": 13.0, "scale": 2.0, "soft": 0.10},
		"RAIN": {"visible": true, "y": 18.0, "scale": 5.0, "soft": 0.20},
		"SNOW": {"visible": true, "y": 18.0, "scale": 4.5, "soft": 0.22},
	}
	var shape: Dictionary = shape_presets.get(weather_type, shape_presets["CLEAR"])
	var cloud_props: Dictionary = _weather_cloud_props()
	var coverage: float = cloud_props["okta"]
	var density: float = sky_overcast_amt_current
	var light_grey := Color(0.95, 0.95, 0.96)
	var dark_grey := Color(0.20, 0.21, 0.23)
	var cloud_color: Color = light_grey.lerp(dark_grey, density)

	cloud_mesh.visible = shape["visible"]
	cloud_mesh.position.y = shape["y"]
	cloud_shader_mat.set_shader_parameter("coverage", coverage)
	cloud_shader_mat.set_shader_parameter("density", clampf(density, 0.0, 1.0))
	cloud_shader_mat.set_shader_parameter("noise_scale", shape["scale"])
	cloud_shader_mat.set_shader_parameter("softness", shape["soft"])
	cloud_shader_mat.set_shader_parameter("cloud_color", cloud_color)
	cloud_shader_mat.set_shader_parameter("brightness", sky_brightness_safe)

	# 지면 실안개 — 비/눈 올 때만, 노출 폭주 방지를 위해 같은 안전 배율을 곱함.
	# 짙기도 같은 τ 기반 흐림 정도(density)에 비례.
	var env: Environment = world_env.environment
	var fog_amt: float = 0.0
	if is_rain:
		fog_amt = lerp(0.015, 0.05, density)
	elif is_snow:
		fog_amt = lerp(0.02, 0.07, density)
	elif weather_type == "OVERCAST":
		fog_amt = 0.02
	env.fog_enabled = fog_amt > 0.0
	if env.fog_enabled:
		env.fog_density = fog_amt
		var fog_c: Color = Color(0.6, 0.62, 0.65) * sky_brightness_safe
		fog_c.a = 1.0
		env.fog_light_color = fog_c
	var wind_amt: float = wind_speed if wind_enabled else 0.0
	var drift_raw = cloud_shader_mat.get_shader_parameter("drift")
	var drift: Vector2 = drift_raw if drift_raw != null else Vector2.ZERO
	drift += Vector2(wind_amt, wind_amt * 0.6) * delta * 0.05
	cloud_shader_mat.set_shader_parameter("drift", drift)

	# 비/눈이 바람을 맞아 옆으로 흩날리게 — 중력 벡터에 수평 성분을 얹음
	# (질량이 작은 눈이 비보다 바람에 더 잘 밀리도록 계수를 더 크게 줌).
	var rain_pmat: ParticleProcessMaterial = rain_particles.process_material as ParticleProcessMaterial
	rain_pmat.gravity = Vector3(wind_amt * 0.6, -9.0, wind_amt * 0.35)
	var snow_pmat: ParticleProcessMaterial = snow_particles.process_material as ParticleProcessMaterial
	snow_pmat.gravity = Vector3(wind_amt * 1.1, -1.2, wind_amt * 0.7)

	# 강수강도(rain_rate)가 지금까지 구름 짙기/소리 볼륨/천둥 빈도에만
	# 영향을 줬고, 화면에 보이는 비/눈의 "양"과 "크기"는 항상 고정값이었음
	# (amount=2000/1200, 입자 크기도 항상 동일) — 슬라이더를 올려도 비가
	# 똑같아 보이던 버그. 마샬-팔머 분포의 총 입자농도 N_total ∝ R^0.21
	# 관계(Λ가 이미 R^-0.21을 따름)로 "양"을, 같은 분포가 강할수록 평균
	# 방울이 커지는 경향으로 "크기"를 함께 강도에 비례시킴.
	var rain_frac: float = clampf(pow(rain_rate / 50.0, 0.21), 0.15, 1.0)
	rain_particles.amount_ratio = rain_frac
	var rain_size: float = 0.7 + 0.5 * rain_frac
	rain_pmat.scale_min = rain_size * 0.75
	rain_pmat.scale_max = rain_size * 1.35

	# 눈은 건-마샬(Gunn-Marshall) 분포 — 적설 강도가 강할수록 결정 대신
	# 뭉친 큰 송이(aggregate) 비중이 늘어 평균 크기가 커짐.
	var snow_frac: float = clampf(rain_rate / 30.0, 0.1, 1.0)
	snow_particles.amount_ratio = snow_frac
	var snow_size: float = 0.6 + 0.8 * snow_frac
	snow_pmat.scale_min = snow_size * 0.7
	snow_pmat.scale_max = snow_size * 1.5

	if is_rain:
		ground_wetness = clampf(ground_wetness + delta / 60.0, 0.0, 1.0)
		ground_snow = clampf(ground_snow - delta * 0.25, 0.0, 1.0)
	elif is_snow:
		ground_snow = clampf(ground_snow + delta / 90.0, 0.0, 1.0)
		ground_wetness = clampf(ground_wetness - delta, 0.0, 1.0)
	else:
		ground_wetness = clampf(ground_wetness - delta, 0.0, 1.0)
		ground_snow = clampf(ground_snow - delta * 0.25, 0.0, 1.0)

	var dry_color := Color(0.16, 0.24, 0.08)
	var wet_color := Color(0.05, 0.13, 0.03)
	var snow_color := Color(0.92, 0.94, 0.97)
	var c: Color = dry_color.lerp(wet_color, ground_wetness).lerp(snow_color, ground_snow)
	ground_mat.albedo_color = c
	ground_mat.roughness = lerp(0.85, 0.3, ground_wetness)

	for i in range(leaf_mats.size()):
		var base: Color = leaf_base_colors[i]
		var m: StandardMaterial3D = leaf_mats[i]
		m.albedo_color = base.lerp(snow_color, ground_snow)

	# 웅덩이 — 비가 와서 젖은 만큼만 차오르고(ground_wetness), 눈이 덮이면
	# (ground_snow) 안 보이게. 항상 고정 크기로 떠 있던 버그 수정.
	for i in range(puddle_nodes.size()):
		var node: MeshInstance3D = puddle_nodes[i]
		var max_r: float = puddle_max_r[i]
		var visible_r: float = max(0.001, ground_wetness * (1.0 - ground_snow)) * max_r
		node.scale = Vector3(visible_r, 1.0, visible_r)

func _update_tree_sway(delta: float) -> void:
	var wind_amt: float = wind_speed if wind_enabled else 0.0
	sway_time += delta
	var wind_factor: float = clampf(wind_amt / 6.0, 0.0, 1.0)
	var max_angle: float = deg_to_rad(10.0) * wind_factor
	for i in range(tree_sway_pivots.size()):
		var pivot: Node3D = tree_sway_pivots[i]
		var phase: float = tree_sway_phase[i]
		var freq: float = tree_sway_freq[i]
		var angle: float = sin(sway_time * freq * TAU + phase) * max_angle
		pivot.rotation = Vector3(0.0, 0.0, angle)

func _update_sound(delta: float) -> void:
	# 버그였던 부분: "비가 땅에 닿기 전에 소리가 난다"는 지적의 실제 원인 —
	# 날씨를 RAIN으로 바꾸는 순간 rain_player 볼륨이 그 프레임에 즉시 목표치로
	# 뛰는데, 빗방울은 y=9에서 떨어지기 시작해 땅(y=0)까지 도달하는 데 실제로
	# 약 1.4초(중력 -9.0, 초기속도 ~0.75 기준 자유낙하 추정)가 걸림 — 그 1.4초
	# 동안은 화면에 땅에 닿는 빗방울이 아직 하나도 없는데 비 소리는 이미
	# 풀볼륨으로 나고 있었음. RAIN이 된 시점부터 그 낙하시간만큼 볼륨을
	# 서서히 올려서 "보이는 비"와 "들리는 비"의 시작 시점을 맞춤.
	var is_rain: bool = weather_type == "RAIN"
	if is_rain and not _was_raining:
		_rain_started_elapsed = 0.0
	if is_rain:
		_rain_started_elapsed += delta
	_was_raining = is_rain
	var fade_in: float = clampf(_rain_started_elapsed / RAIN_FALL_TIME_SEC, 0.0, 1.0)

	# 강수강도(WMO 경계)에 따라 약~중~강 빗소리 파일 자체를 바꿔줌 — 이전엔
	# rain_light/heavy.wav가 만들어져 있었는데도 한 번도 안 쓰이고 항상
	# rain_medium.wav만 재생되던(볼륨만 바뀌던) 죽은 에셋이었음.
	var tier: int = 0 if rain_rate <= 7.6 else (1 if rain_rate <= 50.0 else 2)
	if is_rain and tier != _rain_tier:
		_rain_tier = tier
		var path: String = ["res://sounds/rain_light.wav", "res://sounds/rain_medium.wav", "res://sounds/rain_heavy.wav"][tier]
		rain_player.stream = _load_loop_wav(path)
		rain_player.play()

	rain_player.volume_db = linear_to_db(clampf(rain_rate / 25.0, 0.0, 1.6) * fade_in) if is_rain else -80.0
	wind_player.volume_db = linear_to_db(clampf(wind_speed / 5.0, 0.0, 1.2)) if (wind_enabled and wind_speed > 0.05) else -80.0
	var snow_vol: float = clampf(0.10 * clampf(rain_rate / 30.0, 0.2, 1.0), 0.03, 0.35)
	snow_player.volume_db = linear_to_db(snow_vol) if weather_type == "SNOW" else -80.0

func _update_thunder(delta: float) -> void:
	# 번개가 이미 "쳤다"면(번쩍임을 보여준 시점에 확정) 그 소리(천둥)는 실제
	# 음속(343m/s)만큼 늦게 도착하는 게 물리적으로 당연함 — 그 사이에 날씨를
	# 바꿔도 이미 친 번개의 천둥소리는 취소되면 안 됨(실제로 안 취소되니까).
	# 예전엔 weather_type이 RAIN이 아니게 되는 순간 대기 중인 천둥까지 같이
	# 취소해버려서, 번쩍이는 건 봤는데 (그 사이 다른 날씨를 눌러보다가) 천둥
	# 소리를 못 듣는 것처럼 보였던 버그.
	#
	# 버그였던 부분(번쩍임이 한 프레임만 보이던 원인): 아래 "번개 적용" 블록이
	# 이 함수의 맨 끝에 있었는데, pending_thunder_in이 0 이상이 되는 바로
	# 다음 프레임부터 위 if에서 즉시 return 해버려서 그 블록에 영원히 도달을
	# 못 했음. 즉, 번쩍임을 trigger한 "그 한 프레임"에만 sky_mat이 흰색으로
	# 칠해지고, 바로 다음 프레임에 _update_sky_and_lights가 정상 하늘색으로
	# 덮어써버리는데 _update_thunder는 return 때문에 다시 칠할 기회가 없었음
	# — 그래서 0.15초짜리 번쩍임이 실제로는 1프레임(<0.02초)만 보였던 것.
	# 수정: "번개 적용" 블록을 모든 분기 이후, 매 프레임 무조건 평가되는
	# 위치로 옮겨서 lightning_flash_remaining>0인 동안 계속 다시 칠하게 함.
	if pending_thunder_in >= 0.0:
		pending_thunder_in -= delta
		if pending_thunder_in <= 0.0:
			_play_thunder(pending_thunder_volume)
			pending_thunder_in = -1.0
	elif weather_type == "RAIN":
		# 천둥은 적운형 강수운(쿠물로님버스)에서만 생기고, 그건 WMO 강한 비
		# 경계(7.6mm/hr) 이상에서나 나타나는 구름 — 약한~보통 비를 만드는
		# 난층운에서는 실제로 천둥이 거의 안 침.
		var threshold: float = 7.6
		if rain_rate > threshold:
			var intensity: float = clampf((rain_rate - threshold) / (60.0 - threshold), 0.0, 1.0)
			var avg_interval: float = max(4.0, 70.0 - 65.0 * intensity * intensity)
			if randf() < delta / avg_interval:
				# 거리 상한 12km->6km: 멀수록 지연이 최대 35초까지 길어져
				# 실제로 기다려 들은 사람이 거의 없었을 만한 길이였음. 6km면
				# 최대 ~17.5초로, 여전히 "멀리서" 느낌은 나되 기다려서 들을
				# 수 있는 범위.
				var distance_km: float = randf_range(0.3, 6.0)
				var distance_factor: float = clampf(distance_km / 6.0, 0.0, 1.0)
				pending_thunder_in = distance_km * 1000.0 / 343.0
				pending_thunder_volume = clampf(1.4 - distance_factor * 1.1, 0.15, 1.3)
				lightning_flash_remaining = 0.15

	if lightning_flash_remaining > 0.0:
		lightning_flash_remaining -= delta
		# 밤에는 하늘색이 거의 0에 가까운 고정값이라 노출만 만져선 안 보임
		# (0에 아무리 곱해도 0) — 번개가 가장 인상적인 게 바로 밤이라
		# 하늘색/노출을 같이 밝은 흰색으로 직접 덮어써야 실제로 "번쩍"임.
		sky_mat.sky_top_color = Color(0.75, 0.8, 0.95)
		sky_mat.sky_horizon_color = Color(0.85, 0.87, 0.95)
		world_env.environment.tonemap_exposure = 1.0

func _play_thunder(volume_mult: float) -> void:
	if thunder_streams.is_empty():
		return
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = thunder_streams[randi() % thunder_streams.size()]
	p.volume_db = linear_to_db(clampf(volume_mult, 0.05, 2.0))
	p.finished.connect(func(): p.queue_free())
	p.play()
