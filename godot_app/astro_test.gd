## headless 천문 검수 테스트
## 실행: godot --headless --script astro_test.gd
extends SceneTree

func _init() -> void:
	var all_pass := true

	# ──────────────────────────────────────────────
	# 검사 1 : 태양 적위
	# ──────────────────────────────────────────────
	print("\n── 검사 1: 태양 적위 ──")
	var decl_cases: Array = [
		{"label":"춘분(3/20) day≈79",  "y":2024,"mo":3, "d":20, "exp":0.0,   "tol":1.0},
		{"label":"하지(6/21) day≈172", "y":2024,"mo":6, "d":21, "exp":23.44, "tol":1.0},
		{"label":"추분(9/22) day≈265", "y":2024,"mo":9, "d":22, "exp":0.0,   "tol":1.0},
		{"label":"동지(12/21) day≈355","y":2024,"mo":12,"d":21, "exp":-23.44,"tol":1.0},
	]
	for c in decl_cases:
		var jd: float = Astronomy.julian_day(c["y"], c["mo"], c["d"], 12.0)
		var t: float  = (jd - 2451545.0) / 36525.0
		var s: Dictionary = Astronomy._sun_geocentric(t)
		var dec: float = s["dec"]
		var err: float = dec - float(c["exp"])
		var passed: bool = absf(err) <= float(c["tol"])
		if not passed: all_pass = false
		print("  %s %s : dec=%.3f°  기대=%.2f°  오차=%+.3f°" % [
			"PASS" if passed else "FAIL", c["label"], dec, float(c["exp"]), err])

	# ──────────────────────────────────────────────
	# 검사 2 : 정오 남중고도
	# 서울=UTC+8.47h(127°E), 런던=UTC±0h, 적도(0°E)=UTC±0h
	# ──────────────────────────────────────────────
	print("\n── 검사 2: 정오 남중고도 ──")
	# utc_noon: 해당 경도에서 태양시 정오≈12h LMT → UTC = 12 - lon/15
	var noon_cases: Array = [
		{"label":"서울 하지",  "y":2024,"mo":6, "d":21,"lat":37.5,"lon":127.0,"utc_noon":3.47,"exp":75.9,"tol":2.0},
		{"label":"서울 춘분",  "y":2024,"mo":3, "d":20,"lat":37.5,"lon":127.0,"utc_noon":3.47,"exp":52.5,"tol":2.0},
		{"label":"서울 동지",  "y":2024,"mo":12,"d":21,"lat":37.5,"lon":127.0,"utc_noon":3.47,"exp":29.1,"tol":2.0},
		{"label":"런던 하지",  "y":2024,"mo":6, "d":21,"lat":51.5,"lon":0.0,  "utc_noon":12.0,"exp":61.9,"tol":2.0},
		{"label":"런던 춘분",  "y":2024,"mo":3, "d":20,"lat":51.5,"lon":0.0,  "utc_noon":12.0,"exp":38.5,"tol":2.0},
		{"label":"런던 동지",  "y":2024,"mo":12,"d":21,"lat":51.5,"lon":0.0,  "utc_noon":12.0,"exp":15.1,"tol":2.0},
		{"label":"적도 하지",  "y":2024,"mo":6, "d":21,"lat":0.0, "lon":0.0,  "utc_noon":12.0,"exp":66.6,"tol":2.0},
		{"label":"적도 춘분",  "y":2024,"mo":3, "d":20,"lat":0.0, "lon":0.0,  "utc_noon":12.0,"exp":90.0,"tol":2.0},
		{"label":"적도 동지",  "y":2024,"mo":12,"d":21,"lat":0.0, "lon":0.0,  "utc_noon":12.0,"exp":66.6,"tol":2.0},
	]
	for c in noon_cases:
		var best: float = -999.0
		# ±2시간 범위를 1분 단위로 스캔해 최대 고도 탐색
		for mi in range(-120, 121):
			var utc: float = float(c["utc_noon"]) + float(mi) / 60.0
			var av: Vector2 = Astronomy.sun_altaz(c["y"], c["mo"], c["d"], utc, c["lat"], c["lon"])
			if av.x > best:
				best = av.x
		var err: float = best - float(c["exp"])
		var passed: bool = absf(err) <= float(c["tol"])
		if not passed: all_pass = false
		print("  %s %s : alt=%.2f°  기대=%.1f°  오차=%+.2f°" % [
			"PASS" if passed else "FAIL", c["label"], best, float(c["exp"]), err])

	# ──────────────────────────────────────────────
	# 검사 3 : 낮 길이 (1분 간격 샘플링)
	# 대기굴절 포함 시뮬이므로 기하값보다 7~8분 길게 나오는 방향은 PASS 처리
	# ──────────────────────────────────────────────
	print("\n── 검사 3: 낮 길이 ──")
	var daylen_cases: Array = [
		{"label":"적도 하지",       "y":2024,"mo":6, "d":21,"lat":0.0,  "lon":0.0,  "exp_h":12.0+0.0/60.0,"tol_m":15.0},
		{"label":"적도 춘분",       "y":2024,"mo":3, "d":20,"lat":0.0,  "lon":0.0,  "exp_h":12.0+0.0/60.0,"tol_m":15.0},
		{"label":"적도 동지",       "y":2024,"mo":12,"d":21,"lat":0.0,  "lon":0.0,  "exp_h":12.0+0.0/60.0,"tol_m":15.0},
		{"label":"서울 하지",       "y":2024,"mo":6, "d":21,"lat":37.5,"lon":127.0,"exp_h":14.0+35.0/60.0,"tol_m":15.0},
		{"label":"서울 춘분",       "y":2024,"mo":3, "d":20,"lat":37.5,"lon":127.0,"exp_h":12.0+0.0/60.0,"tol_m":15.0},
		{"label":"서울 동지",       "y":2024,"mo":12,"d":21,"lat":37.5,"lon":127.0,"exp_h":9.0+25.0/60.0,"tol_m":15.0},
		{"label":"런던 하지",       "y":2024,"mo":6, "d":21,"lat":51.5,"lon":0.0,  "exp_h":16.0+24.0/60.0,"tol_m":15.0},
		{"label":"런던 춘분",       "y":2024,"mo":3, "d":20,"lat":51.5,"lon":0.0,  "exp_h":12.0+0.0/60.0,"tol_m":15.0},
		{"label":"런던 동지",       "y":2024,"mo":12,"d":21,"lat":51.5,"lon":0.0,  "exp_h":7.0+36.0/60.0,"tol_m":15.0},
		{"label":"북극권 하지(백야)","y":2024,"mo":6, "d":21,"lat":66.56,"lon":0.0,"exp_h":24.0,"tol_m":15.0},
		{"label":"북극권 춘분",     "y":2024,"mo":3, "d":20,"lat":66.56,"lon":0.0, "exp_h":12.0,"tol_m":15.0},
		{"label":"북극권 동지(극야)","y":2024,"mo":12,"d":21,"lat":66.56,"lon":0.0,"exp_h":0.0,"tol_m":15.0},
	]
	for c in daylen_cases:
		var day_min: float = 0.0
		for step in range(1440):
			var utc: float = float(step) / 60.0
			var av: Vector2 = Astronomy.sun_altaz(c["y"], c["mo"], c["d"], utc, float(c["lat"]), float(c["lon"]))
			if av.x > 0.0:
				day_min += 1.0
		var day_h: float = day_min / 60.0
		var err_m: float = (day_h - float(c["exp_h"])) * 60.0
		# 대기굴절로 인해 더 길게 나오는 방향(err_m > 0)은 최대 8분 추가 허용
		var passed: bool
		var refraction_bonus: float = 8.0
		if float(c["exp_h"]) >= 23.9:  # 백야: 24h − 소수 허용
			passed = day_min >= 1430.0
		elif float(c["exp_h"]) <= 0.1:  # 극야: 대기굴절로 수분은 보일 수 있음
			passed = day_min <= 30.0
		else:
			passed = absf(err_m) <= float(c["tol_m"]) or (err_m > 0.0 and err_m <= float(c["tol_m"]) + refraction_bonus)
		if not passed: all_pass = false
		var eh: int = int(float(c["exp_h"]))
		var em: int = int((float(c["exp_h"]) - float(eh)) * 60.0 + 0.5)
		print("  %s %s : %.0fh%.0fm  기대=%dh%02dm  오차=%+.1f분" % [
			"PASS" if passed else "FAIL",
			c["label"],
			floor(day_h), fmod(day_min, 60.0),
			eh, em, err_m])

	# ──────────────────────────────────────────────
	# 검사 4 : 극주야 경계
	# ──────────────────────────────────────────────
	print("\n── 검사 4: 극주야 경계 ──")

	# 66.56°N 하지 → 백야여야 함
	var min_6656_summer: float = _count_day_minutes(2024, 6, 21, 66.56, 0.0)
	var r4a: bool = min_6656_summer >= 1430.0
	if not r4a: all_pass = false
	print("  %s 66.56°N 하지: %.0f분 (백야=1440분 기대, 굴절 포함)" % ["PASS" if r4a else "FAIL", min_6656_summer])

	# 65.5°N 하지 → 백야 아님(경계 1° 안쪽)
	var min_655_summer: float = _count_day_minutes(2024, 6, 21, 65.5, 0.0)
	var r4b: bool = min_655_summer < 1439.0
	if not r4b: all_pass = false
	print("  %s 65.5°N 하지: %.0f분 (백야 아님 기대)" % ["PASS" if r4b else "FAIL", min_655_summer])

	# 66.56°N 동지 → 극야여야 함 (굴절로 소수 분은 허용)
	var min_6656_winter: float = _count_day_minutes(2024, 12, 21, 66.56, 0.0)
	var r4c: bool = min_6656_winter <= 30.0
	if not r4c: all_pass = false
	print("  %s 66.56°N 동지: %.0f분 (극야=0분 기대, ≤30분 허용)" % ["PASS" if r4c else "FAIL", min_6656_winter])

	# 65.5°N 동지 → 극야 아님
	var min_655_winter: float = _count_day_minutes(2024, 12, 21, 65.5, 0.0)
	var r4d: bool = min_655_winter > 30.0
	if not r4d: all_pass = false
	print("  %s 65.5°N 동지: %.0f분 (극야 아님 기대)" % ["PASS" if r4d else "FAIL", min_655_winter])

	# ──────────────────────────────────────────────
	# 검사 5 : 거리≠계절 정합성
	# ──────────────────────────────────────────────
	print("\n── 검사 5: 거리≠계절 정합성 ──")
	# 1월 3일(근일점) 서울 정오고도 vs 7월 4일(원일점)
	var best_jan: float = _peak_alt(2024, 1, 3, 37.5, 127.0, 3.47)
	var best_jul: float = _peak_alt(2024, 7, 4, 37.5, 127.0, 3.47)
	# 계절이 거리가 아닌 자전축 기울기로 결정된다면: 여름 고도 > 겨울 고도 + 20°
	var r5: bool = best_jul > best_jan + 20.0
	if not r5: all_pass = false
	print("  %s 근일점(1/3) 서울 정오고도=%.1f°  원일점(7/4) 서울 정오고도=%.1f°" % [
		"PASS" if r5 else "FAIL", best_jan, best_jul])
	if r5:
		print("    → 여름이 겨울보다 %.1f° 높음 ✓ 자전축 기울기로 계절 결정됨" % (best_jul - best_jan))
	else:
		print("    → [FAIL] 차이 %.1f°: 계절 구현 확인 필요" % (best_jul - best_jan))

	# 적위 부호로 재확인: 1월 초 dec < 0 (태양이 남반구에) → 북반구 겨울
	var jd_jan: float = Astronomy.julian_day(2024, 1, 3, 12.0)
	var t_jan: float = (jd_jan - 2451545.0) / 36525.0
	var dec_jan: float = Astronomy._sun_geocentric(t_jan)["dec"]
	var jd_jul: float = Astronomy.julian_day(2024, 7, 4, 12.0)
	var t_jul: float = (jd_jul - 2451545.0) / 36525.0
	var dec_jul: float = Astronomy._sun_geocentric(t_jul)["dec"]
	print("    적위 확인: 근일점(1/3) dec=%.2f°  원일점(7/4) dec=%.2f°" % [dec_jan, dec_jul])
	if dec_jan < 0.0 and dec_jul > 0.0:
		print("    → 근일점에 태양이 적도 남쪽(-), 원일점에 북쪽(+) ✓ 부호 정상")
	else:
		print("    → [주의] 적위 부호 확인 필요")

	# ──────────────────────────────────────────────
	print("\n══════════════════════════════════════")
	if all_pass:
		print("최종 결과: ALL PASS ✓")
	else:
		print("최종 결과: FAIL 항목 있음 ✗")
	print("══════════════════════════════════════\n")
	quit()

# ── 헬퍼 ──
func _count_day_minutes(y: int, mo: int, d: int, lat: float, lon: float) -> float:
	var cnt: float = 0.0
	for step in range(1440):
		var utc: float = float(step) / 60.0
		var av: Vector2 = Astronomy.sun_altaz(y, mo, d, utc, lat, lon)
		if av.x > 0.0:
			cnt += 1.0
	return cnt

func _peak_alt(y: int, mo: int, d: int, lat: float, lon: float, utc_noon: float) -> float:
	var best: float = -999.0
	for mi in range(-120, 121):
		var utc: float = utc_noon + float(mi) / 60.0
		var av: Vector2 = Astronomy.sun_altaz(y, mo, d, utc, lat, lon)
		if av.x > best:
			best = av.x
	return best
