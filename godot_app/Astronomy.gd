extends RefCounted
class_name Astronomy
## 실제 천문 계산 — Blender판(forest_rain_live.py)은 skyfield(NASA JPL 천체력)를
## 썼지만, 여기 독립 실행 프로그램은 외부 천체력 파일을 들고 다닐 필요 없이
## 그 자체로 동작해야 해서 공인된 저정밀 공식으로 대체함:
##   - 태양: NOAA Solar Position Algorithm (정밀도 약 0.01도)
##   - 달: Meeus "Astronomical Algorithms" 저정밀 급수(정밀도 약 0.3~0.5도)
## 둘 다 일반 천문 계산에서 흔히 쓰이는 공인 근사식이며, 결과가 skyfield와
## 완전히 똑같지는 않지만 같은 날 같은 시각의 실제 태양/달 위치를 충분히
## 정확하게 재현함.

const DEG2RAD: float = PI / 180.0
const RAD2DEG: float = 180.0 / PI

static func julian_day(year: int, month: int, day: int, hour_utc: float) -> float:
	var y: int = year
	var m: int = month
	if m <= 2:
		y -= 1
		m += 12
	var a: float = floor(float(y) / 100.0)
	var b: float = 2.0 - a + floor(a / 4.0)
	return floor(365.25 * float(y + 4716)) + floor(30.6001 * float(m + 1)) + float(day) + b - 1524.5 + hour_utc / 24.0

# 태양 황경/적위/적경 + 자전 보정용 항(균시차 등)을 한 번에 계산
static func _sun_geocentric(t: float) -> Dictionary:
	var l0: float = fmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m: float = 357.52911 + t * (35999.05029 - 0.0001537 * t)
	var mr: float = m * DEG2RAD
	var e: float = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
	var c: float = sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) \
		+ sin(2.0 * mr) * (0.019993 - 0.000101 * t) \
		+ sin(3.0 * mr) * 0.000289
	var true_lon: float = l0 + c
	var omega: float = 125.04 - 1934.136 * t
	var lambda_: float = true_lon - 0.00569 - 0.00478 * sin(omega * DEG2RAD)
	var eps0: float = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
	var eps: float = eps0 + 0.00256 * cos(omega * DEG2RAD)
	var lr: float = lambda_ * DEG2RAD
	var epsr: float = eps * DEG2RAD
	var ra: float = atan2(cos(epsr) * sin(lr), cos(lr)) * RAD2DEG
	var dec: float = asin(sin(epsr) * sin(lr)) * RAD2DEG
	# 균시차(분) — 실제 태양시와 평균태양시 차이(지구 궤도 타원/자전축 기울기 보정)
	var yterm: float = tan(epsr / 2.0)
	yterm = yterm * yterm
	var eqtime: float = 4.0 * RAD2DEG * (yterm * sin(2.0 * l0 * DEG2RAD) - 2.0 * e * sin(mr)
		+ 4.0 * e * yterm * sin(mr) * cos(2.0 * l0 * DEG2RAD)
		- 0.5 * yterm * yterm * sin(4.0 * l0 * DEG2RAD) - 1.25 * e * e * sin(2.0 * mr))
	return {"ra": ra, "dec": dec, "eqtime": eqtime, "eps": eps, "l0": l0, "m": m, "true_lon": true_lon}

## 고도(altitude)/방위(azimuth, 북=0 동=90 나침반 방위각) 공통 변환 — 적경/적위 +
## 그 시각의 그리니치 평균시각(GMST)·관측자 위경도만 있으면 어떤 천체든 동일.
## 대기 굴절 자동 보정 포함: 지평선(0°)≈+29', 5°≈+10', 10°≈+5' (Bennett 1982 / Meeus 16.4절)
static func radec_to_altaz(ra_deg: float, dec_deg: float, gmst_deg_val: float, lat_deg: float, lon_deg: float) -> Vector2:
	var lst: float = fmod(gmst_deg_val + lon_deg, 360.0)
	var h: float = (lst - ra_deg) * DEG2RAD
	var lat: float = lat_deg * DEG2RAD
	var dec: float = dec_deg * DEG2RAD
	var alt: float = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h))
	var az: float = atan2(sin(h), cos(h) * sin(lat) - tan(dec) * cos(lat))
	az = fmod(az * RAD2DEG + 180.0, 360.0)  # 천문 관례(남=0)를 나침반 관례(북=0)로
	var alt_deg: float = alt * RAD2DEG
	# 대기 굴절 보정 (진고도→겉보기 고도): -2° 이상에서만 적용
	# R = 1.02/tan(alt + 10.3/(alt+5.11)) arcmin, 최대 0.62° 제한
	if alt_deg > -2.0:
		var R: float = 1.02 / tan((alt_deg + 10.3 / (alt_deg + 5.11)) * DEG2RAD)
		alt_deg += clampf(R / 60.0, 0.0, 0.62)
	return Vector2(alt_deg, az)

static func gmst_deg(jd: float) -> float:
	var t: float = (jd - 2451545.0) / 36525.0
	var g: float = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000.0
	return fmod(g, 360.0)

## 태양 고도/방위 — year/month/day/hour_utc(UTC 소수시), 관측자 위경도(도)
static func sun_altaz(year: int, month: int, day: int, hour_utc: float, lat_deg: float, lon_deg: float) -> Vector2:
	var jd: float = julian_day(year, month, day, hour_utc)
	var t: float = (jd - 2451545.0) / 36525.0
	var s: Dictionary = _sun_geocentric(t)
	var g: float = gmst_deg(jd)
	var ra: float = s["ra"]
	var dec: float = s["dec"]
	return radec_to_altaz(ra, dec, g, lat_deg, lon_deg)

## 달 — 저정밀 급수(Meeus Ch.47 축약). RA/Dec와 위상(0=신월,1=보름)을 같이 반환.
static func moon_state(year: int, month: int, day: int, hour_utc: float, lat_deg: float, lon_deg: float) -> Dictionary:
	var jd: float = julian_day(year, month, day, hour_utc)
	var t: float = (jd - 2451545.0) / 36525.0
	var lp: float = fmod(218.3164591 + 481267.88134236 * t, 360.0)
	var d: float = fmod(297.8502042 + 445267.1115168 * t, 360.0)
	var m: float = fmod(357.5291092 + 35999.0502909 * t, 360.0)
	var mp: float = fmod(134.9634114 + 477198.8676313 * t, 360.0)
	var f: float = fmod(93.2720993 + 483202.0175273 * t, 360.0)
	var dr: float = d * DEG2RAD
	var mr: float = m * DEG2RAD
	var mpr: float = mp * DEG2RAD
	var fr: float = f * DEG2RAD
	var lon: float = lp \
		+ 6.289 * sin(mpr) - 1.274 * sin(mpr - 2.0 * dr) + 0.658 * sin(2.0 * dr) \
		- 0.186 * sin(mr) - 0.059 * sin(2.0 * mpr - 2.0 * dr) - 0.057 * sin(mpr - 2.0 * dr + mr) \
		+ 0.053 * sin(mpr + 2.0 * dr) + 0.046 * sin(2.0 * dr - mr) + 0.041 * sin(mpr - mr) \
		- 0.035 * sin(dr) - 0.031 * sin(mpr + mr)
	var lat_ecl: float = 5.128 * sin(fr) + 0.281 * sin(mpr + fr) - 0.278 * sin(fr - mpr) - 0.173 * sin(2.0 * dr - fr)
	var s: Dictionary = _sun_geocentric(t)
	var eps_sun: float = s["eps"]
	var eps: float = eps_sun * DEG2RAD
	var lonr: float = lon * DEG2RAD
	var latr: float = lat_ecl * DEG2RAD
	var ra: float = atan2(sin(lonr) * cos(eps) - tan(latr) * sin(eps), cos(lonr)) * RAD2DEG
	var dec: float = asin(sin(latr) * cos(eps) + cos(latr) * sin(eps) * sin(lonr)) * RAD2DEG
	var g: float = gmst_deg(jd)
	var altaz: Vector2 = radec_to_altaz(ra, dec, g, lat_deg, lon_deg)
	# 위상 — 태양-달 평균 이각(d, 위에서 계산)으로부터의 표준 근사
	var phase_angle: float = 180.0 - d
	var k: float = (1.0 + cos(phase_angle * DEG2RAD)) / 2.0
	return {"alt": altaz.x, "az": altaz.y, "illum": clampf(k, 0.0, 1.0)}

## 행성 위치·등급 — Meeus "Astronomical Algorithms" 저정밀 궤도 요소 기반 (정밀도 ~0.3°)
## planet: "mercury"|"venus"|"mars"|"jupiter"|"saturn"|"uranus"|"neptune"
## 반환: {"alt", "az", "mag", "ra", "dec"}
static func planet_state(planet: String, year: int, month: int, day: int,
		hour_utc: float, lat_deg: float, lon_deg: float) -> Dictionary:
	var jd: float = julian_day(year, month, day, hour_utc)
	var t: float  = (jd - 2451545.0) / 36525.0

	# 궤도 요소 배열 [L0_c, L0_r, a, e_c, e_r, i_c, i_r, Om_c, Om_r, w_c, w_r]
	# Meeus Table 33.a (c=상수항, r=세기당 변화율)
	var oe: Array
	match planet:
		"mercury": oe=[252.250906,149474.0722491, 0.387098, 0.20563175, 0.000020407,  7.004986, 0.0018215,  48.330893,1.1861890,  77.456119,1.5564776]
		"venus":   oe=[181.979801, 58519.2130302, 0.723330, 0.006773,  -0.000049514,  3.394662, 0.0010037,  76.679920,0.9011190, 131.563707,1.4022286]
		"mars":    oe=[355.433275, 19141.6964746, 1.523679, 0.09340065, 0.000090484,  1.849726,-0.0006011,  49.558093,0.7720923, 336.060234,1.8410449]
		"jupiter": oe=[ 34.351519,  3034.9056606, 5.202603, 0.048498,   0.000163,     1.303270,-0.0054966, 100.464441,1.0209550,  14.331309,1.6126682]
		"saturn":  oe=[ 50.077444,  1222.1138488, 9.537070, 0.05415060,-0.000213,     2.488878,-0.0037363, 113.665524,0.8770970,  93.056787,1.9637613]
		"uranus":  oe=[314.055005,   429.8640561,19.191263, 0.04716771,-0.0000019,    0.773197,-0.0016869,  74.005957,0.5211278, 173.005291,1.4863790]
		"neptune": oe=[304.348665,   219.8833092,30.068963, 0.00858587, 0.0000251,    1.769953, 0.0002256, 131.784057,1.1022039,  48.120276,1.4262957]
		_: return {}

	var L0: float = oe[0] + oe[1] * t
	var a_p: float= oe[2]
	var e_p: float= oe[3] + oe[4] * t
	var i_p: float= oe[5] + oe[6] * t
	var Om: float = oe[7] + oe[8] * t
	var w_p: float= oe[9] + oe[10]* t

	# 평균 이각 → 편심 이각 (케플러 방정식, 뉴턴법)
	var M_p: float = fmod(L0 - w_p, 360.0) * DEG2RAD
	var E_p: float = M_p
	for _i in range(10):
		E_p = E_p - (E_p - e_p * sin(E_p) - M_p) / (1.0 - e_p * cos(E_p))
	var nu_p: float = 2.0 * atan2(sqrt(1.0 + e_p) * sin(E_p * 0.5),
	                               sqrt(1.0 - e_p) * cos(E_p * 0.5))
	var r_p: float  = a_p * (1.0 - e_p * cos(E_p))

	# 태양 중심 황도 직교 좌표 (행성)
	var u_p: float  = nu_p + (w_p - Om) * DEG2RAD
	var i_r: float  = i_p * DEG2RAD
	var Om_r: float = Om  * DEG2RAD
	var l_p: float  = atan2(sin(u_p) * cos(i_r), cos(u_p)) + Om_r
	var b_p: float  = asin(clampf(sin(u_p) * sin(i_r), -1.0, 1.0))

	# 지구 태양 중심 위치
	var sun: Dictionary = _sun_geocentric(t)
	var l_e: float = fmod(sun["true_lon"] + 180.0, 360.0) * DEG2RAD
	var M_e: float = sun["m"] * DEG2RAD
	var e_e: float = 0.016708617 - t * 0.000042037
	var E_e: float = M_e
	for _i in range(5):
		E_e = E_e - (E_e - e_e * sin(E_e) - M_e) / (1.0 - e_e * cos(E_e))
	var r_e: float = 1.000001018 * (1.0 - e_e * cos(E_e))

	# 지심 황도 → 적도 좌표
	var dx: float = r_p*cos(b_p)*cos(l_p) - r_e*cos(l_e)
	var dy: float = r_p*cos(b_p)*sin(l_p) - r_e*sin(l_e)
	var dz: float = r_p*sin(b_p)
	var dist: float = maxf(sqrt(dx*dx + dy*dy + dz*dz), 0.001)
	var l_g: float  = atan2(dy, dx)
	var b_g: float  = atan2(dz, sqrt(dx*dx + dy*dy))
	var eps: float  = sun["eps"] * DEG2RAD
	var ra: float   = atan2(sin(l_g)*cos(eps) - tan(b_g)*sin(eps), cos(l_g)) * RAD2DEG
	var dec: float  = asin(clampf(sin(b_g)*cos(eps) + cos(b_g)*sin(eps)*sin(l_g), -1.0, 1.0)) * RAD2DEG
	var altaz: Vector2 = radec_to_altaz(ra, dec, gmst_deg(jd), lat_deg, lon_deg)

	# 이각 (태양-행성-지구 삼각형)
	var phi_r: float = acos(clampf((r_p*r_p + dist*dist - r_e*r_e) / (2.0*r_p*dist), -1.0, 1.0))
	var phi_d: float = phi_r * RAD2DEG

	# 등급 (Meeus Table 33.b / USNO Explanatory Supplement)
	var dt5: float = 5.0 * log(r_p * dist) / log(10.0)
	var mag: float
	match planet:
		"mercury":
			# 다항식 위상 함수 (내행성, 위상 변화 극심)
			mag = -0.36 + dt5 + 0.0380*phi_d - 0.000273*phi_d*phi_d + 0.000002*phi_d*phi_d*phi_d
		"venus":
			# Lambertian 구 — 금성은 구름으로 완전 덮여 Lambertian에 가장 가까움
			var lv: float = (sin(phi_r) + (PI - phi_r)*cos(phi_r)) / PI
			mag = -4.47 + dt5 - 2.5*log(maxf(lv, 1e-6)) / log(10.0)
		"mars":
			mag = -1.52 + dt5 + 0.016*phi_d
		"jupiter":
			mag = -9.395 + dt5 + 0.005*phi_d
		"saturn":
			# 토성 고리 기울기 B (Meeus Ch.45): i=28.06°, Ω=169.51°+3.82°×T
			# sin B = -sin(i)·cos(β)·sin(λ-Ω) + cos(i)·sin(β)
			# 밝기 보정 Δmag = -2.60·|sin B| + 1.25·sin²B (고리 최대 개방 ≈ -0.9등)
			var i_ring: float = 28.06 * DEG2RAD
			var Om_ring: float = fmod(169.51 + 3.82 * t, 360.0) * DEG2RAD
			var sinB: float = clampf(-sin(i_ring)*cos(b_g)*sin(l_g - Om_ring) + cos(i_ring)*sin(b_g), -1.0, 1.0)
			var ring_dm: float = -2.60 * abs(sinB) + 1.25 * sinB * sinB
			mag = -8.88 + dt5 + 0.044*phi_d + ring_dm
		"uranus":
			mag = -7.19 + dt5 + 0.0028*phi_d
		"neptune":
			mag = -6.87 + dt5 + 0.041*phi_d
		_:
			mag = 0.0

	return {"alt": altaz.x, "az": altaz.y, "mag": mag, "ra": ra, "dec": dec}

## J2000.0 → 목표 에포크 세차 행렬 (IAU 1976 Lieske, 정밀도 ~0.001° / 2050년 이전)
## 반환: Godot Basis — P × v 로 직교좌표 변환
static func precession_matrix(jd: float) -> Basis:
	var t: float  = (jd - 2451545.0) / 36525.0
	var f: float  = DEG2RAD / 3600.0   # 각초 → 라디안
	var zeta: float  = ((2306.2181 + (1.39656 - 0.000139*t)*t)*t
	                   + (0.30188  - 0.000344*t)*t*t + 0.017998*t*t*t) * f
	var z:    float  = ((2306.2181 + (1.39656 - 0.000139*t)*t)*t
	                   + (1.09468  + 0.000066*t)*t*t + 0.018203*t*t*t) * f
	var theta: float = ((2004.3109 - (0.85330 + 0.000217*t)*t)*t
	                   - (0.42665  + 0.000217*t)*t*t - 0.041775*t*t*t) * f
	var sz: float = sin(zeta); var cz: float = cos(zeta)
	var sZ: float = sin(z);    var cZ: float = cos(z)
	var st: float = sin(theta); var ct: float = cos(theta)
	# P = Rz(-z) × Ry(θ) × Rz(-ζ), Godot Basis는 열벡터(column) 기준
	return Basis(
		Vector3(cZ*ct*cz - sZ*sz, -sZ*ct*cz - cZ*sz, -st*cz),
		Vector3(cZ*ct*sz + sZ*cz, -sZ*ct*sz + cZ*cz, -st*sz),
		Vector3(cZ*st,            -sZ*st,              ct    )
	)

## J2000.0 RA/Dec → 현재 에포크 RA/Dec (도 단위)
## P: precession_matrix(jd) 의 반환값을 재사용하면 효율적
static func precess_radec(ra_deg: float, dec_deg: float, P: Basis) -> Vector2:
	var ra: float  = ra_deg  * DEG2RAD
	var dec: float = dec_deg * DEG2RAD
	var v: Vector3 = P * Vector3(cos(dec)*cos(ra), cos(dec)*sin(ra), sin(dec))
	return Vector2(atan2(v.y, v.x) * RAD2DEG,
	               asin(clampf(v.z, -1.0, 1.0)) * RAD2DEG)
