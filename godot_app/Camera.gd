class_name WorldSimCamera
extends Node

const EYE_HEIGHT: float    = 1.7
const GROUND_VIEW_ALT: float = 45.0
const MOVE_BOUND: float    = 25.0

var view_mode: String = "NORMAL"

# 수직 FOV (도). 올바른 원근 화각 기준:
#   사람 눈 ≈ 모니터 시청 거리 의존 (~28-32°) — 직선 왜곡 없는 "창문" 투영
#   50mm 사진 렌즈 환경 ~27° (16:9), 일반 게임 60-75°
# 기본값 50°: 게임 감각과 현실 사이 절충점
const FOV_DEFAULT: float = 50.0
const FOV_MIN: float     = 10.0   # 10° = 강한 망원 (태양/달 착시 극대화)
const FOV_MAX: float     = 90.0   # 90° = 광각

var _fov: float = FOV_DEFAULT

var _cam: Camera3D
var _yaw: float   = 0.0
var _pitch: float = 0.0
var _move_speed: float   = 8.0
var _mouse_look: bool    = false

func build() -> void:
	_cam = Camera3D.new()
	_cam.fov = _fov
	_cam.current = true
	add_child(_cam)
	_cam.position = Vector3(8, EYE_HEIGHT, 16)
	_cam.look_at_from_position(_cam.position, Vector3(0, 1.5, 0), Vector3.UP)
	var fwd: Vector3 = -_cam.global_transform.basis.z
	_yaw   = atan2(-fwd.x, -fwd.z)
	_pitch = asin(clampf(fwd.y, -1.0, 1.0))

func get_camera() -> Camera3D:
	return _cam

func set_view_mode(mode: String) -> void:
	view_mode = mode
	match mode:
		"NORMAL":
			_cam.position.y = EYE_HEIGHT
			_pitch = 0.0
		"SKY":
			_cam.position.y = EYE_HEIGHT
			_pitch = deg_to_rad(89.0)
		"GROUND":
			_cam.position.y = GROUND_VIEW_ALT
			_pitch = deg_to_rad(-89.0)

func update(delta: float) -> void:
	_cam.transform.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var yaw_fwd   := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var yaw_right := Vector3( cos(_yaw), 0.0, -sin(_yaw))
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir += yaw_fwd
	if Input.is_key_pressed(KEY_S): dir -= yaw_fwd
	if Input.is_key_pressed(KEY_D): dir += yaw_right
	if Input.is_key_pressed(KEY_A): dir -= yaw_right
	if dir.length_squared() > 0.0:
		var speed: float = _move_speed * (2.5 if Input.is_key_pressed(KEY_CTRL) else 1.0)
		_cam.position += dir.normalized() * speed * delta

	_cam.position.x = clampf(_cam.position.x, -MOVE_BOUND, MOVE_BOUND)
	_cam.position.z = clampf(_cam.position.z, -MOVE_BOUND, MOVE_BOUND)
	_cam.position.y = GROUND_VIEW_ALT if view_mode == "GROUND" else EYE_HEIGHT

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_mouse_look = not _mouse_look
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_look else Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _mouse_look:
		_mouse_look = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		# F 키: 화각 기본값(50°) 리셋
		_fov = FOV_DEFAULT
		_cam.fov = _fov
		return
	if event is InputEventMouseMotion and _mouse_look:
		var sens: float = 0.0035
		_yaw -= event.relative.x * sens
		if view_mode == "NORMAL":
			_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _mouse_look:
				# 시점 회전 중 스크롤: 이동 속도 조정
				_move_speed = clampf(_move_speed * 1.2, 0.5, 200.0)
			else:
				# 일반 모드 스크롤: 줌인 (FOV 감소)
				_fov = clampf(_fov - 3.0, FOV_MIN, FOV_MAX)
				_cam.fov = _fov
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _mouse_look:
				_move_speed = clampf(_move_speed / 1.2, 0.5, 200.0)
			else:
				# 일반 모드 스크롤: 줌아웃 (FOV 증가)
				_fov = clampf(_fov + 3.0, FOV_MIN, FOV_MAX)
				_cam.fov = _fov
