extends RefCounted

# WS Forest — 순수 수학/물리 정적 헬퍼
# Sky.gd에서 분리(2026-06-29). 상태 없는 static 함수만 — 로직 변경 없음(verbatim).
# 소비 측에서 const SkyMath = preload("res://SkyMath.gd") 로 불러 SkyMath.X 로 참조.
#
# 주의: _sun_illuminance / _exposure_for_lux / _preetham_sky_colors 는
#       CLAUDE.md '절대 변경 금지'(노출·톤매핑·천문 산란) 영역. 이동만, 값/로직 불변.

# 별빛 조도 하한 (lux) — 칠흑 야간에도 별빛이 주는 최소 조도. _exposure_for_lux 기준점.
const STARLIGHT_FLOOR_LUX: float = 0.0008

# ── 수학 헬퍼 (static) ───────────────────────────────────────────────
static func _altaz_to_dir(alt_deg: float, az_deg: float) -> Vector3:
	var elev := deg_to_rad(alt_deg)
	var az   := deg_to_rad(az_deg)
	return Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))

static func _lerp_breakpoints(x: float, xs: Array, ys: Array) -> float:
	if x <= xs[0]: return ys[0]
	for i in range(xs.size() - 1):
		if x <= xs[i + 1]:
			var f: float = (x - xs[i]) / (xs[i + 1] - xs[i])
			return lerp(ys[i], ys[i + 1], f)
	return ys[ys.size() - 1]

# B-V 색지수 기반 스펙트럼 색상 — 실제 B-V값에서 변환한 RGB (감마 보정 없음, HDR 값 그대로)
# 참조: Allen's Astrophysical Quantities, 5th ed. / SIMBAD catalog B-V indices
# [RA°, Dec°, R, G, B] — RA/Dec는 J2000.0 도 단위, 허용 오차 ±0.8°
static func _star_spectral_color(ra: float, dec: float) -> Color:
	# 밝은 별 스펙트럼 색 테이블 (1등성 이상 + 색이 특히 뚜렷한 별)
	# 청색(B형): (0.72, 0.82, 1.0) / 청백(A형): (0.84, 0.90, 1.0) / 백색(F형): (1.0, 0.97, 0.88)
	# 황색(G형): (1.0, 0.92, 0.72) / 주황(K형): (1.0, 0.78, 0.48) / 적색(M형): (1.0, 0.55, 0.30)
	const TABLE: Array = [
		# 이름         RA       Dec       R     G     B        스펙트럼
		[101.287, -16.716, 0.87, 0.92, 1.00],  # Sirius      A1V  청백
		[ 95.988, -52.696, 0.98, 0.98, 1.00],  # Canopus     F0I  백
		[213.915,  19.182, 1.00, 0.76, 0.44],  # Arcturus    K1.5 주황
		[279.235,  38.784, 0.82, 0.89, 1.00],  # Vega        A0V  청백
		[ 79.172,  45.998, 1.00, 0.92, 0.70],  # Capella     G5   황
		[ 78.634,  -8.201, 0.78, 0.87, 1.00],  # Rigel       B8I  청백
		[114.828,   5.225, 1.00, 0.97, 0.87],  # Procyon     F5   백황
		[ 24.429, -57.237, 0.76, 0.85, 1.00],  # Achernar    B6V  청
		[ 88.792,   7.407, 1.00, 0.52, 0.28],  # Betelgeuse  M2I  적등
		[297.696,   8.868, 1.00, 0.98, 0.90],  # Altair      A7V  백
		[ 68.980,  16.509, 1.00, 0.72, 0.38],  # Aldebaran   K5   적주황
		[247.352, -26.432, 1.00, 0.46, 0.24],  # Antares     M1.5 적
		[201.298, -11.161, 0.74, 0.84, 1.00],  # Spica       B1V  청
		[116.329,  28.026, 1.00, 0.86, 0.62],  # Pollux      K0   주황
		[344.413, -29.622, 1.00, 0.98, 0.93],  # Fomalhaut   A4V  백
		[310.358,  45.280, 1.00, 0.99, 0.96],  # Deneb       A2I  백
		[152.093,  11.967, 0.80, 0.88, 1.00],  # Regulus     B7V  청백
		[104.656, -28.972, 0.75, 0.84, 1.00],  # Adhara      B2II 청
		[113.649,  31.889, 0.86, 0.92, 1.00],  # Castor      A1V  청백
		[ 81.283,   6.350, 0.75, 0.85, 1.00],  # Bellatrix   B2   청
		[ 81.572,  28.608, 0.82, 0.89, 1.00],  # Elnath      B7   청백
		[253.084, -42.998, 1.00, 0.97, 0.88],  # Sargas      F1   백
		[193.507,  55.960, 0.90, 0.94, 1.00],  # Alioth      A0   청백
		[276.992, -34.385, 0.90, 0.95, 1.00],  # Kaus Aus.   B9   백
		[ 99.428,  16.399, 1.00, 0.99, 0.94],  # Alhena      A0   백
		[219.919, -60.833, 1.00, 0.94, 0.76],  # Rigil Kent. G2V  황
		[210.956, -60.373, 0.73, 0.83, 1.00],  # Hadar       B1   청
		# 남반구 밝은 별 (남위 25° 이남에서 관측 가능)
		[186.650, -63.099, 0.72, 0.82, 1.00],  # Acrux  α Cru B0.5 청
		[191.930, -59.689, 0.72, 0.82, 1.00],  # Mimosa β Cru B0.5 청
		[187.791, -57.113, 1.00, 0.50, 0.25],  # Gacrux γ Cru M4   적 (남반구 붉은 별 대표)
		[125.629, -59.509, 1.00, 0.82, 0.56],  # Avior  ε Car K0+B 주황백
		[138.301, -69.717, 0.90, 0.95, 1.00],  # Miaplacidus β Car A2 청백
		[204.972, -53.466, 0.73, 0.83, 1.00],  # ε Cen  B1   청
		[ 29.692, -61.400, 0.80, 0.88, 1.00],  # β Eri  A3   청백
	]
	const TOL2: float = 0.64   # 허용 오차 0.8°의 제곱
	for entry in TABLE:
		var dra: float  = ra  - entry[0]
		var ddec: float = dec - entry[1]
		if dra * dra + ddec * ddec < TOL2:
			return Color(entry[2], entry[3], entry[4])
	return Color(1.0, 1.0, 1.0)   # 목록에 없는 별: 흰색

static func _sun_illuminance(alt_deg: float) -> float:
	var anchors_alt := [-18.0, -12.0, -6.0, 0.0, 10.0, 30.0, 60.0, 90.0]
	# -12° 실측: 0.002–0.004 lux (항해박명 끝 — 지평선 겨우 구분), 10° 실측: ~9,000 lux
	var anchors_lux := [0.0008, 0.003, 3.4, 400.0, 9000.0, 50000.0, 90000.0, 100000.0]
	var a: float = clampf(alt_deg, -18.0, 90.0)
	for i in range(anchors_alt.size() - 1):
		if a <= anchors_alt[i + 1] or i == anchors_alt.size() - 2:
			var t0: float = anchors_alt[i]; var t1: float = anchors_alt[i + 1]
			var f: float = 0.0
			if t1 > t0: f = clampf((a - t0) / (t1 - t0), 0.0, 1.0)
			var l0: float = log(anchors_lux[i]) / log(10.0)
			var l1: float = log(anchors_lux[i + 1]) / log(10.0)
			return pow(10.0, lerp(l0, l1, f))
	return anchors_lux[anchors_lux.size() - 1]

static func _exposure_for_lux(total_lux: float) -> float:
	var anchors_lux := [STARLIGHT_FLOOR_LUX, 0.01, 0.1, 1.0, 3.4, 12.0, 40.0, 120.0, 400.0, 3000.0, 12000.0, 100000.0]
	var anchors_ev  := [19.5, 18.5, 17.2, 15.0, 12.5, 10.0, 8.0, 5.5, 3.5, 1.8, 0.6, 0.0]
	var lux: float     = max(total_lux, STARLIGHT_FLOOR_LUX)
	var log_lux: float = log(lux) / log(10.0)
	for i in range(anchors_lux.size() - 1):
		var l0: float = log(anchors_lux[i]) / log(10.0)
		var l1: float = log(anchors_lux[i + 1]) / log(10.0)
		if log_lux <= l1 or i == anchors_lux.size() - 2:
			var f: float = 0.0
			if l1 > l0: f = clampf((log_lux - l0) / (l1 - l0), 0.0, 1.0)
			return lerp(anchors_ev[i], anchors_ev[i + 1], f)
	return anchors_ev[anchors_ev.size() - 1]

# ── Preetham(1999) 대기 산란 모델 ─────────────────────────────────────────
# "A Practical Analytic Model for Daylight", Preetham, Shirley, Smits (1999)
# sun_elev_deg: 태양 고도각 (0=지평선, 90=천정). 음수는 0으로 클램프 후 호출.
# turbidity: 대기 혼탁도 T (2=맑음, 10=탁함). 권장 기본값 3.0.
# 반환: [Color zenith_top, Color horizon] — 선형 광색(HDR, >1 가능), ProceduralSkyMaterial에 직접 설정.
# 보정 기준: T=3, θ_s=45°(고도45°) 에서 청색 채널 ≈ 0.95 (SCALE=0.05)
#
# ※ 현재 미사용: 하늘 색은 sky_atmosphere.gdshader(픽셀별 Preetham)가 담당.
#    이 CPU 경로는 LOD-저(웹) 폴백/검증용으로 보존. 삭제 대신 이동만 했다.
static func _preetham_sky_colors(sun_elev_deg: float, turbidity: float) -> Array:
	var T  := clampf(turbidity, 2.0, 10.0)
	var T2 := T * T
	# 태양 천정각 (0=태양이 바로 위, π/2=지평선)
	var ts  := deg_to_rad(clampf(90.0 - sun_elev_deg, 0.0, 90.0))
	var ts2 := ts * ts
	var ts3 := ts2 * ts

	# 천정 휘도 Yz (kcd/m²)
	var chi := (4.0/9.0 - T/120.0) * (PI - 2.0*ts)
	var Yz  := maxf((4.0453*T - 4.9710) * tan(chi) - 0.2155*T + 2.4192, 0.01)

	# 천정 색도 (CIE 1931 x, y)
	var xz := clampf(
		T2*(0.00216*ts3 - 0.00375*ts2 + 0.00209*ts)
		+ T*(-0.02903*ts3 + 0.06377*ts2 - 0.03202*ts + 0.00394)
		+ (0.11693*ts3 - 0.21196*ts2 + 0.06052*ts + 0.25886), 0.01, 0.8)
	var yz := clampf(
		T2*(0.00275*ts3 - 0.00610*ts2 + 0.00317*ts)
		+ T*(-0.04214*ts3 + 0.08970*ts2 - 0.04153*ts + 0.00516)
		+ (0.15346*ts3 - 0.26756*ts2 + 0.06670*ts + 0.26688), 0.01, 0.8)

	# Perez 계수 (Y=휘도, _x=색도x, _yy=색도y)
	var A_Y  :=  0.1787*T - 1.4630; var B_Y  := -0.3554*T + 0.4275
	var C_Y  := -0.0227*T + 5.3251; var D_Y  :=  0.1206*T - 2.5771; var E_Y  := -0.0670*T + 0.3703
	var A_x  := -0.0193*T - 0.2592; var B_x  := -0.0665*T + 0.0008
	var C_x  := -0.0004*T + 0.2125; var D_x  := -0.0641*T - 0.8989; var E_x  := -0.0033*T + 0.0452
	var A_yy := -0.0167*T - 0.2608; var B_yy := -0.0950*T + 0.0092
	var C_yy := -0.0079*T + 0.2102; var D_yy := -0.0441*T - 1.6537; var E_yy := -0.0109*T + 0.0529

	# Perez 분포 F(theta, gamma) = (1+A·e^(B/cosθ))·(1+C·e^(D·γ)+E·cos²γ)
	# 천정 기준값 (θ=0, γ=ts): cos(0)=1, cos(ts)=cos_ts
	var cos_ts := cos(ts)
	var f0Y  := (1.0+A_Y *exp(B_Y ))*(1.0+C_Y *exp(D_Y *ts)+E_Y *cos_ts*cos_ts)
	var f0x  := (1.0+A_x *exp(B_x ))*(1.0+C_x *exp(D_x *ts)+E_x *cos_ts*cos_ts)
	var f0yy := (1.0+A_yy*exp(B_yy))*(1.0+C_yy*exp(D_yy*ts)+E_yy*cos_ts*cos_ts)

	# 지평선 샘플 (θ=89°, γ = π/2−ts : 태양 방향 기준 지평선)
	# gm_h 하한 5°: ts→90°(태양 지평선)일 때 gm_h=0 → 최대 circumsolar glow가 되는
	# 극단값을 방지. 이 하한은 D항(360° 균일 적용 한계)과 별개의 B항 완화 수단.
	var th_h  := deg_to_rad(89.0)
	var gm_h  := maxf(deg_to_rad(5.0), PI * 0.5 - ts)
	var ct_h  := maxf(cos(th_h), 0.001)
	var cg_h  := cos(gm_h)
	var fhY  := (1.0+A_Y *exp(B_Y /ct_h))*(1.0+C_Y *exp(D_Y *gm_h)+E_Y *cg_h*cg_h)
	var fhx  := (1.0+A_x *exp(B_x /ct_h))*(1.0+C_x *exp(D_x *gm_h)+E_x *cg_h*cg_h)
	var fhyy := (1.0+A_yy*exp(B_yy/ct_h))*(1.0+C_yy*exp(D_yy*gm_h)+E_yy*cg_h*cg_h)

	# 지평선 xyY
	var hor_x := clampf(xz * fhx  / maxf(f0x,  0.001), 0.01, 0.8)
	var hor_y := clampf(yz * fhyy / maxf(f0yy, 0.001), 0.01, 0.8)
	var hor_Y := Yz * fhY / maxf(f0Y, 0.001)

	# xyY → XYZ → 선형 sRGB. SCALE=0.05: T=3, θ_s=45° 기준 청색채널≈0.95 목표
	const SCALE := 0.05
	var _to_rgb := func(cx:float, cy:float, Y:float) -> Color:
		if cy < 0.001: return Color(0.0, 0.0, 0.0)
		var X := Y * cx / cy
		var Z := Y * (1.0 - cx - cy) / cy
		return Color(
			maxf( 3.2405*X - 1.5371*Y - 0.4985*Z, 0.0),
			maxf(-0.9693*X + 1.8760*Y + 0.0416*Z, 0.0),
			maxf( 0.0556*X - 0.2040*Y + 1.0572*Z, 0.0))

	return [_to_rgb.call(xz,  yz,  Yz  * SCALE),
			_to_rgb.call(hor_x, hor_y, hor_Y * SCALE)]

# 재귀 중점 변위 — [Vector3, Vector3] 쌍 배열 반환 (번개 볼트 형상)
static func _gen_bolt_segs(from: Vector3, to: Vector3, roughness: float, depth: int) -> Array:
	if depth <= 0:
		return [[from, to]]
	var d: float       = from.distance_to(to)
	var along: Vector3 = (to - from).normalized()
	# along이 거의 수직(Y축)이면 X를 레퍼런스로, 아니면 Y를 레퍼런스로
	var up_ref: Vector3 = Vector3(1.0, 0.0, 0.0) if abs(along.y) >= 0.9 else Vector3(0.0, 1.0, 0.0)
	var perp1: Vector3  = along.cross(up_ref).normalized()
	var perp2: Vector3  = along.cross(perp1).normalized()
	var mid: Vector3    = (from + to) * 0.5
	mid += perp1 * randf_range(-1.0, 1.0) * d * roughness
	mid += perp2 * randf_range(-1.0, 1.0) * d * roughness * 0.5
	var segs: Array = []
	segs.append_array(_gen_bolt_segs(from, mid, roughness * 0.65, depth - 1))
	segs.append_array(_gen_bolt_segs(mid,  to,  roughness * 0.65, depth - 1))
	return segs

static func _day_of_year(month: int, day: int) -> int:
	const DAYS: Array = [0,31,59,90,120,151,181,212,243,273,304,334]
	return DAYS[month - 1] + day
