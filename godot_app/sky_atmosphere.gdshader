shader_type sky;

// 태양 방향 벡터 (월드 공간, Y=sin(elevation), X/Z=방위 성분)
uniform vec3 u_sun_dir = vec3(0.0, 1.0, 0.0);
// Preetham 혼탁도 (1=청명, 10=매우 탁함, 기본 3.0)
uniform float u_turbidity : hint_range(1.0, 10.0) = 3.0;
// 야간 하늘 색 (GDScript에서 scotopic·달빛 계산 후 전달, 선형 sRGB)
uniform vec3 u_night_top    = vec3(0.00190, 0.00218, 0.00358);
uniform vec3 u_night_horizon = vec3(0.00080, 0.00085, 0.00140);
// 구름 흐림 정도 (0=맑음, 1=완전 흐림)
uniform float u_overcast_amt : hint_range(0.0, 1.0) = 0.0;
// 번개 플래시 강도 (0=없음, 1=최대)
uniform float u_lightning : hint_range(0.0, 1.0) = 0.0;

// Preetham 휘도 스케일: θ_s=45°, T=3일 때 청색≈0.95 기준
const float SCALE = 0.05;

// Preetham Perez 분포 함수
// cos_theta: cos(시선 천정각), gamma: 시선~태양 사이 각도(라디안)
float perez(float cos_theta, float gamma, float a, float b, float c, float d, float e) {
	float cos_g = cos(gamma);
	return (1.0 + a * exp(b / max(cos_theta, 1e-3)))
	     * (1.0 + c * exp(d * gamma) + e * cos_g * cos_g);
}

// Preetham(1999) 대기 산란: eye 방향, sun 방향, 혼탁도 T → 선형 sRGB
// eye.y > 0 (지평선 위)만 유효; 지평선 아래는 호출 전 클램프
vec3 preetham(vec3 eye, vec3 sun, float T) {
	float sun_y   = clamp(sun.y, 0.0, 1.0);
	float theta_s = acos(sun_y);            // 태양 천정각

	float cos_theta = max(eye.y, 1e-3);
	float gamma     = acos(clamp(dot(eye, sun), -1.0, 1.0)); // 시선~태양 각

	// Perez 계수 — Y(휘도), x, y(색도)
	float aY= 0.1787*T-1.4630, bY=-0.3554*T+0.4275, cY=-0.0227*T+5.3251;
	float dY= 0.1206*T-2.5771, eY=-0.0670*T+0.3703;
	float ax=-0.0193*T-0.2592, bx=-0.0665*T+0.0008, cx=-0.0004*T+0.2125;
	float dx=-0.0641*T-0.8989, ex=-0.0033*T+0.0452;
	float ay=-0.0167*T-0.2608, by=-0.0950*T+0.0092, cy=-0.0079*T+0.2102;
	float dy=-0.0441*T-1.6537, ey=-0.0109*T+0.0529;

	// 천정 휘도 Y_z
	float chi = (4.0/9.0 - T/120.0) * (PI - 2.0*theta_s);
	float Yz = max((4.0453*T - 4.9710)*tan(chi) - 0.2155*T + 2.4192, 0.0) * SCALE;

	// 천정 색도 x_z, y_z
	float T2=T*T, ts=theta_s, ts2=ts*ts, ts3=ts2*ts;
	float xz = T2*( 0.00166*ts3-0.00375*ts2+0.00209*ts)
	          +T*(-0.02903*ts3+0.06377*ts2-0.03202*ts+0.00394)
	          +(  0.11693*ts3-0.21196*ts2+0.06052*ts+0.25886);
	float yz = T2*( 0.00275*ts3-0.00610*ts2+0.00317*ts)
	          +T*(-0.04214*ts3+0.08970*ts2-0.04153*ts+0.00516)
	          +(  0.15346*ts3-0.26756*ts2+0.06670*ts+0.26688);

	// Perez 분포: 천정 기준 정규화
	float fY0 = perez(1.0, theta_s, aY, bY, cY, dY, eY);
	float fx0 = perez(1.0, theta_s, ax, bx, cx, dx, ex);
	float fy0 = perez(1.0, theta_s, ay, by, cy, dy, ey);
	float fY  = perez(cos_theta, gamma, aY, bY, cY, dY, eY);
	float fx  = perez(cos_theta, gamma, ax, bx, cx, dx, ex);
	float fy  = perez(cos_theta, gamma, ay, by, cy, dy, ey);

	float Y = Yz * fY / max(fY0, 1e-4);
	float x = xz * fx / max(fx0, 1e-4);
	float y = yz * fy / max(fy0, 1e-4);

	// CIE xyY → XYZ
	float Xc = (x / max(y, 1e-4)) * Y;
	float Zc = ((1.0 - x - y) / max(y, 1e-4)) * Y;

	// XYZ → 선형 sRGB (D65)
	float R =  3.2406*Xc - 1.5372*Y  - 0.4986*Zc;
	float G = -0.9689*Xc + 1.8758*Y  + 0.0415*Zc;
	float B =  0.0557*Xc - 0.2040*Y  + 1.0570*Zc;
	return max(vec3(R, G, B), vec3(0.0));
}

void sky() {
	vec3 sun_dir = normalize(u_sun_dir);
	vec3 eye     = EYEDIR;


	float sun_elev_deg = degrees(asin(clamp(sun_dir.y, -1.0, 1.0)));

	// 지평선 아래 시선은 지평선(y=0)으로 클램프해 Preetham 계산
	vec3 eye_above = normalize(vec3(eye.x, max(eye.y, 0.001), eye.z));
	vec3 sky_col   = preetham(eye_above, sun_dir, u_turbidity);

	// 야간 블렌드: -2° → -10° smoothstep (log 공간 보간)
	float dtn_raw = clamp((-sun_elev_deg - 2.0) / 8.0, 0.0, 1.0);
	float dtn_t   = dtn_raw * dtn_raw * (3.0 - 2.0 * dtn_raw);

	// 야간 하늘: 시선 고도에 따른 top↔horizon 그라디언트
	// night_h=0 → night_top(천정), night_h=1 → night_horizon(지평선)
	float night_h  = clamp(1.0 - eye.y, 0.0, 1.0);
	vec3  night_col = mix(u_night_top, u_night_horizon, night_h);

	// log 공간 보간: 560:1 밝기비를 지각 균등하게 전환
	const float eps = 1e-5;
	vec3 result;
	result.r = exp(mix(log(max(sky_col.r, eps)), log(max(night_col.r, eps)), dtn_t));
	result.g = exp(mix(log(max(sky_col.g, eps)), log(max(night_col.g, eps)), dtn_t));
	result.b = exp(mix(log(max(sky_col.b, eps)), log(max(night_col.b, eps)), dtn_t));

	// 구름 흐림: 야간(-6°이하)에서 overcast 효과 제거 (실제로 흐린 야간도 어두움)
	float sky_night_blend = clamp((-sun_elev_deg - 6.0) / 12.0, 0.0, 1.0);
	vec3  overcast_grey   = vec3(0.42, 0.44, 0.47);
	result = mix(result, overcast_grey, u_overcast_amt * (1.0 - sky_night_blend));

	// 지평선 아래(지면): 어두운 갈색으로 페이드
	if (eye.y < 0.0) {
		float gt = clamp(-eye.y * 8.0, 0.0, 1.0);
		gt = gt * gt;
		result = mix(result, vec3(0.05, 0.045, 0.04), gt);
	}

	// 번개 플래시
	if (u_lightning > 0.01) {
		float fh       = clamp(1.0 - eye.y * 2.0, 0.0, 1.0);
		vec3  flash_col = mix(vec3(0.75, 0.80, 0.95), vec3(0.85, 0.87, 0.95), fh);
		result          = mix(result, flash_col, u_lightning);
	}

	COLOR = result;
}
