shader_type sky;

// 태양 방향 벡터 (월드 공간, Y=sin(elevation)). 지평선 아래면 Y<0.
uniform vec3 u_sun_dir = vec3(0.0, 1.0, 0.0);
// 대기 혼탁도 (Mie 산란 강도에 비례 — 1=청명, 10=탁함)
uniform float u_turbidity : hint_range(1.0, 10.0) = 3.0;
// 야간 배경광 (별빛 산란+영구 대기광, GDScript에서 계산해 전달, 선형 sRGB·÷노출)
uniform vec3 u_night_top    = vec3(0.00190, 0.00218, 0.00358);
uniform vec3 u_night_horizon = vec3(0.00080, 0.00085, 0.00140);
// 구름 흐림 정도 (0=맑음, 1=완전 흐림)
uniform float u_overcast_amt : hint_range(0.0, 1.0) = 0.0;
// 번개 플래시 강도
uniform float u_lightning : hint_range(0.0, 1.0) = 0.0;
// 현재 tonemap 노출 배율 — 하늘을 노출 독립화(÷노출 후 tonemap×노출이 상쇄)
uniform float u_exposure = 1.0;

// ── 단일산란 대기 모델 (Nishita/Bruneton류) ──────────────────────────────
// 시선 광선을 대기에서 ray-march, 각 샘플에서 태양까지 광선이 지구에 가리는지
// 판정 → 태양이 지평선 아래일 때 박명이 기하학적으로 창발(손으로 칠하지 않음).
const float Rg = 6360000.0;   // 지구 반경 (m)
const float Rt = 6420000.0;   // 대기 상한 반경 (60km 대기)
const float Hr = 7994.0;      // Rayleigh 밀도 척도고도 (8km)
const float Hm = 1200.0;      // Mie 밀도 척도고도 (1.2km)
// Rayleigh 산란계수 (파장별, /m) — 청색이 가장 강함 → 낮 하늘 파랑, 일몰 빨강
const vec3  betaR = vec3(5.8e-6, 13.5e-6, 33.1e-6);
// Mie 산란계수 (파장 무관, 에어로졸) — 전방산란으로 태양 주변 흰 광환
const vec3  betaM = vec3(21e-6);
const float MieG  = 0.76;     // Mie 비대칭 인자 (전방산란)
const float SUN_I = 22.0;     // 태양 강도 (밝기 캘리브레이션)
const int   VIEW_SAMPLES  = 16;
const int   LIGHT_SAMPLES = 8;

// 광선-구 교차의 먼 쪽 t (원점이 구 내부 가정). 교차 없으면 -1.
float ray_sphere_far(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	float disc = b * b - c;
	if (disc < 0.0) return -1.0;
	return -b + sqrt(disc);
}

// 단일산란 적분 — ro: 카메라 위치, rd: 시선 방향(단위), sun: 태양 방향(단위)
vec3 atmosphere(vec3 ro, vec3 rd, vec3 sun, float mie_mul) {
	float tmax = ray_sphere_far(ro, rd, Rt);
	if (tmax < 0.0) return vec3(0.0);
	float seg = tmax / float(VIEW_SAMPLES);

	float mu = dot(rd, sun);                       // 시선~태양 cos
	float phaseR = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = MieG;
	float phaseM = 3.0 / (8.0 * PI)
		* ((1.0 - g * g) * (1.0 + mu * mu))
		/ ((2.0 + g * g) * pow(max(1.0 + g * g - 2.0 * g * mu, 1e-4), 1.5));

	vec3 sumR = vec3(0.0), sumM = vec3(0.0);
	float odR = 0.0, odM = 0.0;                    // 시선 경로 광학두께(카메라→샘플)

	for (int i = 0; i < VIEW_SAMPLES; i++) {
		vec3 p = ro + rd * (seg * (float(i) + 0.5));
		float h = length(p) - Rg;
		float hr = exp(-h / Hr) * seg;
		float hm = exp(-h / Hm) * seg;
		odR += hr; odM += hm;

		// 이 샘플에서 태양까지의 광선 — 지구에 가리면(그림자) 빛 없음
		float tl = ray_sphere_far(p, sun, Rt);
		float segL = tl / float(LIGHT_SAMPLES);
		float odLR = 0.0, odLM = 0.0;
		bool lit = true;
		for (int j = 0; j < LIGHT_SAMPLES; j++) {
			vec3 pl = p + sun * (segL * (float(j) + 0.5));
			float hl = length(pl) - Rg;
			if (hl < 0.0) { lit = false; break; }  // 태양광이 지구에 막힘 → 그림자
			odLR += exp(-hl / Hr) * segL;
			odLM += exp(-hl / Hm) * segL;
		}
		if (lit) {
			// 투과율 = exp(-(시선OD + 태양OD)·β). Mie 소광 ≈ 1.1× 산란.
			vec3 tau = betaR * (odR + odLR) + betaM * mie_mul * 1.1 * (odM + odLM);
			vec3 att = exp(-tau);
			sumR += att * hr;
			sumM += att * hm;
		}
	}
	return SUN_I * (sumR * betaR * phaseR + sumM * betaM * mie_mul * phaseM);
}

void sky() {
	vec3 sun = normalize(u_sun_dir);
	vec3 eye = EYEDIR;

	// 카메라: 지표 1km 위 (수평선 정밀도 확보). 시선은 지평선 위로 클램프.
	vec3 ro = vec3(0.0, Rg + 1000.0, 0.0);
	vec3 eye_above = normalize(vec3(eye.x, max(eye.y, 0.0008), eye.z));
	float mie_mul = u_turbidity / 3.0;   // 혼탁도 → Mie 강도

	// ── 산란된 햇빛 (낮+박명 창발) ── 노출 독립화
	vec3 sky_col = atmosphere(ro, eye_above, sun, mie_mul) / max(u_exposure, 0.001);

	// ── 야간 배경광 (별빛+영구 대기광) ── GDScript에서 ÷노출(exp_norm) 적용됨.
	// 물리적으로 항상 존재하는 가산 성분: 낮엔 산란광에 묻히고, 산란광이 박명에
	// 사라지면 자연스레 드러남 → 크로스페이드 불필요(자동 핸드오프).
	float night_h  = clamp(1.0 - eye.y, 0.0, 1.0);
	vec3  night_col = mix(u_night_top, u_night_horizon, night_h);

	vec3 result = sky_col + night_col;

	// 구름 흐림: 산란광을 회색으로 수렴 (야간엔 약하게)
	float sun_elev_deg = degrees(asin(clamp(sun.y, -1.0, 1.0)));
	float day_amt = clamp((sun_elev_deg + 6.0) / 12.0, 0.0, 1.0);
	vec3  overcast_grey = vec3(0.42, 0.44, 0.47) / max(u_exposure, 0.001);
	result = mix(result, overcast_grey, u_overcast_amt * day_amt);

	// 지평선 아래(지면): 어두운 갈색으로 페이드
	if (eye.y < 0.0) {
		float gt = clamp(-eye.y * 8.0, 0.0, 1.0);
		gt = gt * gt;
		result = mix(result, vec3(0.05, 0.045, 0.04) / max(u_exposure, 0.001), gt);
	}

	// 번개 플래시
	if (u_lightning > 0.01) {
		float fh = clamp(1.0 - eye.y * 2.0, 0.0, 1.0);
		vec3 flash_col = mix(vec3(0.75, 0.80, 0.95), vec3(0.85, 0.87, 0.95), fh);
		result = mix(result, flash_col, u_lightning);
	}

	COLOR = result;
}
