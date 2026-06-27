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
static func radec_to_altaz(ra_deg: float, dec_deg: float, gmst_deg_val: float, lat_deg: float, lon_deg: float) -> Vector2:
	var lst: float = fmod(gmst_deg_val + lon_deg, 360.0)
	var h: float = (lst - ra_deg) * DEG2RAD
	var lat: float = lat_deg * DEG2RAD
	var dec: float = dec_deg * DEG2RAD
	var alt: float = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h))
	var az: float = atan2(sin(h), cos(h) * sin(lat) - tan(dec) * cos(lat))
	az = fmod(az * RAD2DEG + 180.0, 360.0)  # 천문 관례(남=0)를 나침반 관례(북=0)로
	return Vector2(alt * RAD2DEG, az)

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
