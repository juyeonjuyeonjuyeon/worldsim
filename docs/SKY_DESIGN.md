# 하늘 색 물리 기반 재설계 (Sky Physical Scattering Design)

설계 기준: 2026-06-29  
대상 파일: `godot_app/Sky.gd` (`_update_sky_and_lights` 함수, lines ~781–968)  
현재 구현: 수동 색 테이블 + 단계별 lerp 체인 + brt/scotopic/노출 보정

---

## 1. 현행 구조의 문제점 — "조각조각" 구조

### 1-1. 색 테이블과 블렌드 체인

현재 하늘 색 계산 흐름:

```
elevation
  │
  ├─ warm          = clamp(1 - elev/28,   0, 1)   # 일몰 블렌드
  ├─ civil_t       = clamp(-elev/6,        0, 1)   # 시민박명
  ├─ naut_t        = clamp((-elev-6)/6,   0, 1)   # 항해박명
  └─ astro_t       = clamp((-elev-12)/6,  0, 1)   # 천문박명

색 테이블 (8개 하드코딩):
  day_top (0.35, 0.55, 0.95)    sunset_top (0.42, 0.33, 0.58)
  civil_top (0.18, 0.28, 0.72)  naut_top (0.06, 0.09, 0.30)
  day_horizon (0.75, 0.80, 0.90)  sunset_horizon (1.00, 0.52, 0.18)
  civil_hor (0.82, 0.28, 0.12)    naut_hor (0.16, 0.20, 0.52)

체인 lerp:
  top: day_top → sunset_top(warm) → civil_top(civil_t) → naut_top(naut_t) → night_top(astro_t)
  hor: day_hor → sunset_hor(warm) → civil_hor(civil_t) → naut_hor(naut_t) → night_hor(astro_t)
```

### 1-2. 왜 회귀가 반복되는가

문제의 핵심은 **색과 밝기가 분리되지 않았다**는 점이다.

- `ProceduralSkyMaterial`의 `sky_top_color`·`sky_horizon_color`는 **색+밝기 통합** 값이다.
- 기존 설계는 `brt = 1/exposure_mult`로 하늘 색을 어둡게 해서 밝기를 톤매핑에 위임하려 했다.
- 그런데 `ProceduralSkyMaterial`은 **`tonemap_exposure`의 선형 스케일을 받지 않는다**  
  (Godot 4.7 Forward+ 실험적 확인: sky_color × tonemap_exposure ≠ 최종 화면 밝기).
- 결과: brt=0.0625 (야간 노출)에서 sky_color=0.003 → Hable(0.003) ≈ 거의 0 → 칠흑.
- 수정하면: brt 제거 → 고정 "표시용" 값 × 16.0 지정 → 하지만 이제 노출이 바뀌어도 색 고정.

**조각 수정의 악순환:**
1. 박명이 갈색 → 8개 색 테이블 중 하나 수정  
2. 자정 교차 칠흑 → snap fix 추가 → 박명 갈색 재현 → snap fix 제거  
3. 야간 노출 고정 → 달빛 있을 때 너무 밝음 → moon_sky_factor 추가  
4. …  

근본 원인: **입력(태양 고도)에서 물리적으로 계산된 색이 없고, 출력(색 테이블)을 직접 수동 편집한다.**  
물리 기반 모델로 대체하면 이 순환이 끊긴다.

### 1-3. 현재 파이프라인 구성 요소 목록

대체 설계 전에 존재하는 구성 요소를 정리한다.

| 구성 요소 | 현재 위치 | 역할 |
|----------|----------|------|
| 색 테이블 8개 + lerp 체인 | `_update_sky_and_lights` 896–921번 줄 | 낮·박명·야간 하늘 색 |
| `warm`, `civil_t`, `naut_t`, `astro_t` 블렌드 인자 | 888–894번 줄 | 단계 전환 |
| `brt = sky_brightness_safe` (현재 제거) | — | 구버전 노출 보정 (현재 없음) |
| `scotopic_boost` + `scotopic_r/g/b` | 869–878번 줄 | 야간 색각 시뮬 |
| `night_top`, `night_horizon` (moon_sky_factor, scotopic) | 879–886번 줄 | 밤하늘 기본 색 |
| `overcast_grey` 블렌딩 | 939–941번 줄 | 구름/흐림 색 덮어씌기 |
| `_exposure_for_lux` → `_current_exposure` → `tonemap_exposure` | 844–862번 줄 | 씬 지오메트리 노출 |
| `sky_brightness_safe` | 862–863번 줄 | 달 셰이더 노출 보정 |
| `adjustment_saturation` | 953–962번 줄 | 조도 기반 채도 |

---

## 2. 물리 기반 대기 산란 이론 요약

### 2-1. 레일리 산란 (Rayleigh Scattering)

공기 분자(N₂, O₂, 직경 << λ)에 의한 산란.

- 산란 세기 ∝ 1/λ⁴ → 파란빛이 붉은빛보다 약 5.5배 강하게 산란
- 낮 하늘이 파란 이유, 일출/일몰이 붉은 이유
- 위상 함수: `P_R(θ) = (3/4)(1 + cos²θ)` — 앞·뒤 대칭

```
레일리 계수 (해수면 기준):
β_R(λ) = 5.8e-6 / (λ/550nm)⁴  [m⁻¹, λ=nm 단위]
→ RGB 근사: β_R = (5.8e-6, 13.6e-6, 33.1e-6)  [m⁻¹]
```

### 2-2. 미 산란 (Mie Scattering)

에어로졸(먼지, 연무, 물방울, 직경 ~ λ)에 의한 산란.

- 파장 독립적 (백색) → 연무가 끼면 하늘이 흰/회색
- 강한 앞 산란: Henyey-Greenstein 위상 함수 `g ≈ 0.76`
- 맑은 날 β_M ≈ 2e-6 m⁻¹, 연무 낀 날 β_M ≈ 1e-5 m⁻¹

### 2-3. 단일 산란 적분

카메라에서 픽셀 방향 **v** 로 보낸 광선 위의 각 점 **p**에서:

```
L_scatter = ∫ T(cam→p) × [β_R × P_R(θ) + β_M × P_M(θ)] × L_sun × T(p→sun) dp
```

- `T(A→B)` = 투과율 = `exp(-∫ (β_R + β_M) ds)` (Beer-Lambert)
- `L_sun` = 태양 복사도 (지구 대기 상단)
- 이 적분을 레이마칭 또는 사전 계산 테이블로 풀면 물리 기반 하늘이 나옴

---

## 3. 후보 모델 3종 비교

### 3-1. Preetham (1999) 분석 모델

**방식**: CIE xyY 색공간의 하늘 함수 `F(θ, γ)`를 5개 계수 테이블로 분석적 근사.  
입력: 태양 천정각(`θ_s`), 혼탁도(`T`, 1.9=매우맑음 ~ 10=연무).  
출력: 하늘 반구 임의 방향의 CIE xy 색도 + Y 휘도.

```
F(θ, γ) = (1 + a·exp(b/cosθ)) × (1 + c·exp(dγ) + e·cos²γ)
// θ: 천정각, γ: 태양과 이루는 각
// a~e: 태양 천정각·혼탁도에서 선형 보간된 계수 테이블
```

**장점**:
- 계산 비용 매우 낮음 (셰이더 내 분석 함수 몇 줄)
- 낮 하늘 품질 좋음
- 검증된 모델, 수많은 구현 참조 가능

**단점**:
- 태양이 지평선 아래(elevation < 0)면 모델 붕괴 → 박명·야간 처리 불가
- 혼탁도만 입력 → 구름, 구름 유형 연동 없음
- xyY → sRGB 변환 필요 (White Point D65 기준)

**현재 프로젝트 적합성**: **낮 하늘 전용** (elevation > 0°). 박명·야간은 별도 처리 필수.

---

### 3-2. Hosek-Wilkie (2012) 분석 모델

**방식**: Preetham 개선판. 9개 파장(RGB + 추가) × 9계수 테이블을 태양 천정각 × 혼탁도로 색인.  
태양 근처 "corona" 항 추가로 일출/일몰 품질 향상.

```
F_hw(θ, γ, θ_s, T) = (1 + a·exp(b/(cosθ+ε))) × (c + d·exp(e·γ) + f·cos²γ + g·M(...)+ h·cos^9(γ/2))
// 태양 근처(γ≈0)에서 코로나 항 h·cos^9(γ/2)가 일출 주황 광환 표현
```

사전 계산된 계수 테이블 크기: 약 2KB (RGB × 9계수 × 10개 천정각 × 10개 혼탁도 슬롯).

**장점**:
- Preetham 대비 일출/일몰 정확도 크게 향상
- 계산 비용 여전히 낮음 (셰이더 1개 함수 호출)
- 원 논문 제공 테이블 + MIT 라이선스 구현 다수 존재

**단점**:
- 여전히 elevation < 0 미지원 → 박명·야간 별도 처리
- 테이블 보간 정확도가 edge case(매우 낮은 태양)에서 낮아짐
- 혼탁도 입력 범위 제한 (1.0 ~ 10.0)

**현재 프로젝트 적합성**: **낮 하늘 + 일출/일몰** 메인 모델로 적합.  
elevation > -2° 구간을 커버하고, 그 이하는 별도 박명·야간 레이어로 페이드.

---

### 3-3. 사전 계산 LUT (Bruneton-Neyret 2008 / 변형)

**방식**: 투과율 테이블(`T`), 단일 산란 테이블(`S`), 다중 산란 테이블(`J`)을 오프라인 계산해  
2D/3D GPU 텍스처에 저장. 런타임은 텍스처 샘플링만.

테이블 구성:
```
T(h, μ)        — 고도 h, 천정 코사인 μ의 투과율 [256×64 R16F]
S(h, μ, μ_s)   — 단일 산란 (고도, 광선 방향, 태양 방향) [256×128×32 RGB16F]
J(h, μ, μ_s)   — 다중 산란 누적 [256×128×32 RGB16F]
```

**장점**:
- 박명(elevation < 0)까지 물리적으로 정확
- 다중 산란 포함 → 맑은 날 하늘 색이 Preetham보다 훨씬 정확
- 런타임 비용 낮음 (텍스처 샘플 3회)

**단점**:
- 사전 계산 구현 복잡 (CPU 또는 오프라인 Compute Shader 필요)
- 텍스처 메모리: 약 20–40MB (S, J 테이블 3D)
- 박명 영역도 잘 나오지만 검증된 GDScript 구현이 없음
- 모바일에서 3D 텍스처 샘플링 비용 검토 필요

**현재 프로젝트 적합성**: 품질 최상이지만 **구현 복잡도와 메모리 비용이 가장 높다.**  
Phase 5(배포 품질 향상) 시점에 고려할 옵션. Phase 3 이전 권장하지 않음.

---

### 3-4. 모델 비교표

| 항목 | Preetham | Hosek-Wilkie | Bruneton LUT |
|------|---------|-------------|-------------|
| 낮 하늘 품질 | 좋음 | 매우 좋음 | 최상 |
| 일출/일몰 품질 | 보통 | 좋음 | 최상 |
| 박명(elev < 0) | 미지원 | 미지원 | 지원 |
| 야간 | 미지원 | 미지원 | 미지원 |
| 런타임 비용 | 매우 낮음 | 낮음 | 낮음 (텍스처) |
| 구현 복잡도 | 낮음 | 중간 | 높음 |
| VRAM 사용 | 없음 | ~2KB 테이블 | ~20–40MB |
| 모바일 적합성 | 최적 | 좋음 | 검토 필요 |
| Godot 참조 구현 | 있음 | 있음 (C++ 변환) | 없음 (직접 작성) |

---

## 4. Godot 구현 방법 검토

### 4-1. ProceduralSkyMaterial 유지 (현재)

현재 Sky.gd는 `ProceduralSkyMaterial`의 `sky_top_color`·`sky_horizon_color`를 매 프레임 업데이트한다.

**한계** (앞 절에서 확인):
- 두 색 값만 조절 가능 (천정과 지평선) → 실제 하늘은 방향에 따라 연속 변화
- `tonemap_exposure` 스케일을 받지 않음 → brt 보정 불가
- 태양 글로우(`sun_angle_max`, `sun_curve`)는 물리 기반이 아닌 텍스처 근사
- 물리 모델 통합 불가

**유지 시나리오**: 현행 수동 테이블을 Hosek-Wilkie **출력값으로 교체**한다.  
즉, Hosek-Wilkie를 쓰지만 결과를 여전히 `sky_top_color`·`sky_horizon_color` 두 값으로  
줄여 넣는 방식. 이 경우 하늘 방향별 연속 변화는 없지만 색 자동 계산이 가능해진다.  
구현 리스크가 가장 낮다.

### 4-2. ShaderMaterial 커스텀 스카이 셰이더 (권장)

Godot 4의 `Sky` 리소스는 `ShaderMaterial`을 지원한다:

```gdscript
var sky := Sky.new()
var mat  := ShaderMaterial.new()
mat.shader = preload("res://sky_scatter.gdshader")
sky.sky_material = mat
env.sky = sky
```

`sky_scatter.gdshader` 내에서:
- 픽셀마다 방향 벡터 `EYEDIR`을 받아 Hosek-Wilkie 분석 함수 실행
- `uniform float sun_elevation`, `uniform float turbidity` 등 입력
- 출력은 sRGB 색 (tonemapping 이전의 linear HDR)

**중요 Godot 4 특성**:  
커스텀 스카이 셰이더는 `tonemap_exposure`의 영향을 받지 않는다는 점은 ProceduralSkyMaterial과 동일.  
그러나 **자체 HDR 출력**이 가능하므로 태양 방향에서 매우 밝은 값(10.0+)을 출력해  
Filmic 톤매퍼가 "타오르는" 태양 표현을 자동으로 처리하게 만들 수 있다.

```glsl
// sky_scatter.gdshader 핵심 구조 (의사 코드)
shader_type sky;

uniform float sun_elevation : hint_range(-90.0, 90.0) = 45.0;
uniform float sun_azimuth   : hint_range(0.0, 360.0) = 180.0;
uniform float turbidity     : hint_range(1.0, 10.0) = 2.0;
uniform vec3  sun_color : source_color = vec3(1.0, 1.0, 1.0);
// 야간 보정 파라미터
uniform vec3  night_zenith_color : source_color = vec3(0.03, 0.035, 0.057);
uniform vec3  night_horiz_color  : source_color = vec3(0.013, 0.014, 0.022);
uniform float night_blend : hint_range(0.0, 1.0) = 0.0;
// 스코토픽 파라미터
uniform float scotopic_boost : hint_range(1.0, 6.0) = 1.0;

void sky() {
    vec3 dir = EYEDIR;
    float cos_theta   = clamp(dir.y, 0.0, 1.0);
    float cos_gamma   = dot(dir, sun_dir);
    
    vec3 scatter = hosek_wilkie(cos_theta, cos_gamma, sun_zenith_angle, turbidity);
    
    // 박명·야간: scatter를 night color로 페이드
    scatter = mix(scatter, night_color(dir, night_zenith_color, night_horiz_color), night_blend);
    
    // 스코토픽 보정 (사람눈 모드)
    scatter *= scotopic_factor(scotopic_boost);
    
    COLOR = scatter;
}
```

**장점**:
- 방향별 연속 하늘 색 (두 값 제한 없음)
- 태양 디스크 주변 실제 대기 산란 표현
- `uniform`으로 모든 파라미터 외부에서 제어 → Sky.gd와 깔끔히 연동
- 박명·야간 블렌딩을 셰이더 내에서 처리

**단점**:
- 새 `.gdshader` 파일 작성 필요
- Hosek-Wilkie 9계수 테이블을 셰이더 상수 배열로 인코딩 필요 (약 50줄 데이터)
- 테스트 없이 현재 하늘 색과 1:1 일치를 보장하기 어려움  
  → **사람 눈 검수 필수**

### 4-3. LOD 전략

| LOD | 방식 | 대상 |
|-----|------|------|
| LOD 0 (웹/저사양) | ProceduralSkyMaterial + Hosek-Wilkie로 계산한 2색 자동 입력 | 현재와 동일 렌더 품질, 색 자동화만 |
| LOD 1 (앱/중사양) | 커스텀 스카이 셰이더 + Hosek-Wilkie 분석 | 방향별 연속 그라데이션 |
| LOD 2 (PC/고사양) | LOD 1 + 대기 내 산란 글로우 + 박명 광선 연동 | 최고 품질 |

---

## 5. 권장 방향: 2레이어 분리 모델

### 5-1. 전체 구조

물리 기반 재설계의 핵심은 **"낮/박명"과 "야간"을 별도 레이어로 분리**하고,  
각 레이어가 독립적으로 계산된 뒤 블렌딩되는 것이다.

```
입력: sun_elevation, sun_azimuth (검증 완료 — 건드리지 않음)
      moon_illum, moon_alt, turbidity, cloud_tau

Layer A — Hosek-Wilkie 대기 산란 (elevation ≥ −6°)
  입력: sun_zenith_angle, turbidity
  출력: sky_color(dir) [linear HDR, per pixel]
  유효 범위: sun elevation −6° ~ +90°
  (−6° 이하에서는 이미 신뢰할 수 없는 값이 나오므로 Layer B로 페이드)

Layer B — 야간 하늘 (elevation < −6°)
  입력: moon_illum, moon_alt, scotopic_boost
  출력: night_zenith_color, night_horizon_color
  유효 범위: 항상 존재; elevation > −6°에서는 거의 투명

혼합:
  blend = smoothstep(−2.0, −6.0, elevation)   # 0=낮, 1=완전 야간
  final_color = mix(Layer_A, Layer_B, blend)

Layer C — 스코토픽 보정 (사람눈 모드 전용)
  입력: _eye_view 플래그, Layer_A 또는 Layer_B 색
  출력: 색각 조정 (R 감쇠, B 증폭)
  → 물리 모델 외부에서 후처리 레이어로 적용
```

### 5-2. Layer A 상세 — Hosek-Wilkie

**입력 변수 (Sky.gd → 셰이더 uniform)**:

| 변수 | 의미 | 현재 대응 |
|------|------|---------|
| `sun_elevation` | 태양 고도각 (°) | `elevation` 그대로 |
| `sun_azimuth` | 태양 방위각 (°) | `azimuth` 그대로 |
| `turbidity` | 대기 혼탁도 1.0–10.0 | 새 파라미터. 기본 2.0 (서울 맑은 날). 구름→높음으로 자동 연동 |
| `cloud_turbidity_add` | 구름 흐림 → turbidity 가산 | `cloud_tau`에서 계산 |

**turbidity 연동 제안**:
```gdscript
# Sky.gd 내에서
var base_turbidity: float = 2.0   # 맑은 날 기본값
var cloud_turbidity: float = cloud_props["tau"] * 0.5  # 구름 → 혼탁도 증가
var turbidity: float = clampf(base_turbidity + cloud_turbidity, 1.5, 8.0)
```

이렇게 하면 구름이 끼면 하늘이 자동으로 흰/회색으로 변한다.  
현재의 `overcast_grey.lerp` 블렌딩을 물리적으로 대체.

### 5-3. Layer B 상세 — 야간 하늘

야간 하늘 색은 대기 산란 모델로 계산하기 어렵다.  
(별빛·달빛이 광원; 산란 자체가 너무 약해 측정값 기반이 맞다.)

현재 코드를 유지하되 **파라미터만 명시적으로 분리**:

```gdscript
# 현재 879–886번 줄 구조 유지, 파라미터 이름만 명확화
var night_zenith := Color(
    0.00190 * moon_sky_factor * scotopic_r,
    0.00218 * moon_sky_factor * scotopic_g,
    0.00358 * moon_sky_factor * scotopic_b) * 16.0

var night_horizon := Color(
    0.00080 * moon_sky_factor * scotopic_r,
    0.00085 * moon_sky_factor * scotopic_g,
    0.00140 * moon_sky_factor * scotopic_b) * 16.0
```

야간 색은 물리 측정값(천문 관측 기반)에 가깝기 때문에 이 값 자체는 괜찮다.  
문제는 이 값이 Hosek-Wilkie 결과와 얼마나 자연스럽게 이어지느냐이다.  
혼합 구간을 −2°~−6°로 잡으면 박명 전환이 자연스럽게 이어진다.

### 5-4. Layer C — 스코토픽 보정

현재는 night 색 계산 내부에 scotopic_r/g/b가 섞여 있다.  
Layer B에서 분리하여 **후처리 파라미터**로 독립시킨다:

```gdscript
# Sky.gd 밖(또는 명확히 분리된 함수)에서
func _scotopic_factor() -> Color:
    if not _eye_view:
        return Color(1.0, 1.0, 1.0)
    var boost: float = 4.0
    return Color(boost * 0.80, boost * 0.90, boost * 1.15)

# 야간 색에 곱하기 (현재와 동일하나 명시적으로 분리)
var sc: Color = _scotopic_factor()
night_zenith  = Color(night_base_zenith.r  * sc.r, night_base_zenith.g  * sc.g, night_base_zenith.b  * sc.b)
night_horizon = Color(night_base_horizon.r * sc.r, night_base_horizon.g * sc.g, night_base_horizon.b * sc.b)
```

---

## 6. 기존 코드: 무엇이 대체되고 무엇이 남는가

### 대체 대상 (물리 모델로 교체)

| 현재 코드 | 교체 이유 | 교체 대상 |
|----------|---------|---------|
| 색 테이블 8개 (day_top, sunset_top, civil_top, naut_top, day_horizon, sunset_horizon, civil_hor, naut_hor) | 수동 하드코딩 → 회귀 원인 | Hosek-Wilkie 분석 함수 출력 |
| `warm` 블렌드 인자 (1 - elev/28) | 임의 기울기, 물리 무관 | Hosek-Wilkie에 흡수 |
| `civil_t`, `naut_t`, `astro_t` 순차 lerp | 단계별 하드코딩 | Layer A↔B 혼합 하나로 |
| `overcast_grey.lerp` | turbidity 증가로 자동 처리 | `cloud_tau → turbidity_add` |
| `sky_night_blend` (구름 blending용) | turbidity 연동으로 불필요 | 삭제 |

### 유지 대상 (변경 없음)

| 현재 코드 | 유지 이유 |
|----------|---------|
| 천문 위치 계산 전체 (`sun_altaz`, `moon_state`, 행성, 세차) | 검증 완료, 건드리지 않음 |
| `_exposure_for_lux` → `_current_exposure` → `tonemap_exposure` | 씬 지오메트리 노출, 별도 레이어 |
| `sky_brightness_safe` → 달 셰이더 uniform | 달 메쉬는 지오메트리, 노출 보정 유효 |
| `night_top`, `night_horizon` (야간 색 수치) | 측정 기반, 괜찮음 |
| `moon_sky_factor`, `scotopic_boost` 계산 방식 | 유지하되 Layer B/C로 명시 분리 |
| `adjustment_saturation` (채도 조절) | 물리 모델과 독립, 유지 |
| `sun_light.light_energy`, `moon_light.light_energy` | 지오메트리 조명, 노출 연동, 유지 |
| 번개 플래시 색 보정 (964–968번 줄) | 유지 |

---

## 7. 마이그레이션 경로 (점진적 교체)

전체 교체는 시각 회귀 리스크가 높다.  
단계별 교체로 각 단계마다 사람 눈 검수를 받는다.

### Step 1 — Hosek-Wilkie 출력을 ProceduralSkyMaterial 2색으로 주입 (리스크: 낮음)

현재 `_update_sky_and_lights`에서 8개 색 테이블 대신  
Hosek-Wilkie 함수를 GDScript로 구현해 천정/지평선 방향의 색만 계산한다.  
ProceduralSkyMaterial은 그대로 사용.

결과 검증: 맑은 날/일출/일몰이 현재와 비슷하게 나오는지 확인.

> 사람 눈 검수 필요.

### Step 2 — 커스텀 스카이 셰이더로 전환 (리스크: 중간)

`sky_scatter.gdshader` 작성,  
ProceduralSkyMaterial을 `ShaderMaterial`로 교체.  
이 단계에서 방향별 연속 그라데이션이 적용된다.

> 사람 눈 검수 필요. 기존 태양/달 디스크 메쉬와 ZBuffer 상호작용 확인.

### Step 3 — 야간 혼합 + 스코토픽 분리 (리스크: 낮음)

Layer B(야간)·Layer C(스코토픽)를 셰이더 uniform으로 분리,  
GDScript에서는 파라미터만 계산해 전달.  
8개 색 테이블 코드 삭제.

> 사람 눈 검수 필요. 특히 박명 전환 구간(−2°~−6°)의 색 연속성 확인.

### Step 4 — 구름 turbidity 연동 (리스크: 낮음)

`cloud_tau → turbidity_add` 연산 추가,  
`overcast_grey.lerp` 코드 제거.

> 사람 눈 검수 필요. 흐린 날 하늘이 회색으로 자연스럽게 변하는지 확인.

---

## 8. 알려진 리스크 및 사람 확인 필요 항목

| 항목 | 리스크 | 확인 방법 |
|------|--------|---------|
| Hosek-Wilkie가 현재 하늘 색(수동 튜닝 결과)과 다를 수 있음 | 시각 차이; "더 정확하지만 다름" 가능 | 나란히 A/B 비교 스크린샷 |
| 커스텀 스카이 셰이더의 tonemap_exposure 비적용 여부 확인 | Step 2에서 동일 문제 재현 가능 | `tonemap_exposure` 변경하며 하늘 반응 테스트 |
| Hosek-Wilkie elevation < −2° 처리 | 원 모델 경계 밖 → 아티팩트 가능 | clamp + 야간 블렌딩으로 덮기 |
| 기존 달 메쉬·태양 메쉬와 새 스카이의 ZBuffer 충돌 | 달/태양이 하늘 위 또는 아래에 잘못 그려질 수 있음 | `depth_draw_never` render_mode 유지 확인 |
| 모바일에서 셰이더 함수 호출 비용 | Hosek-Wilkie 함수는 exp, pow 다수 → 모바일 GPU 부담 가능 | 실기기 프로파일링 |
| GDScript Hosek-Wilkie 구현 검증 | 계수 테이블 인코딩 오류 → 색 왜곡 | 기준 이미지(원 논문 그림)와 비교 |

---

## 9. 참고 자료

- Hosek, L., Wilkie, A. (2012). "An Analytic Model for Full Spectral Sky-Dome Radiance." SIGGRAPH 2012.  
  → 원 논문 PDF + C 참조 구현 (BSD 라이선스): https://cgg.mff.cuni.cz/projects/SkylightModelling/
- Preetham, A.J. et al. (1999). "A Practical Analytic Model for Daylight." SIGGRAPH 1999.
- Bruneton, E., Neyret, F. (2008). "Precomputed Atmospheric Scattering." EGSR 2008.
- Godot 4 docs: [ShaderMaterial as Sky](https://docs.godotengine.org/en/stable/classes/class_sky.html)  
  — `shader_type sky;` 지원 확인

---

*생성: Claude Code (2026-06-29)*  
*코드 없음 — 설계 문서 전용*  
*사람 확인 필요: 모든 Step의 시각 검수, 모델 선택 최종 결정*
