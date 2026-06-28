# 볼류메트릭 구름 설계 (Volumetric Cloud Design)

설계 기준: 2026-06-29  
대상 단계: Phase 3 (Phase 2 지형 격자 완성 후)  
현재 구조: `Sky.gd` 단일 레이어 스크롤 UV 셰이더 (`_cloud_mesh`)

---

## 1. 동기 및 목표

현재 구름은 60×60 평면 메쉬에 스크롤 UV 셰이더를 얹은 "2D 벽지" 방식이다.  
이 방식의 한계:
- 카메라가 위를 보면 구름이 평면임이 드러남
- 구름 형태가 날씨 유형(CIRRUS·CUMULUS·OVERCAST)마다 동일
- 구름 내부 진입, 구름 그림자, 달·별 가림 등 물리적 상호작용 불가
- 볼륨 산란(노을 속 황금빛 구름 가장자리 등) 없음

목표:
1. 날씨 유형별로 시각적으로 다른 구름 형태
2. 물리적 조명 (달·별 가림, 그림자, 내부 산란)
3. 모든 플랫폼에서 수용 가능한 성능 (모바일 LOD 필수)
4. 기존 날씨 파라미터(`cloud_opacity`, 날씨 유형)와 자연 연동

---

## 2. 레이마칭 볼류메트릭 접근법

### 2-1. 기본 원리

레이마칭(Ray-marching)은 카메라에서 각 픽셀로 향하는 광선을 따라  
일정 간격마다 밀도 함수를 샘플링해 투과율·색을 누적하는 방식이다.

```
for each pixel P:
  ray = Ray(camera_pos, normalize(P - camera_pos))
  transmittance = 1.0
  light_sum     = 0.0
  for step in [cloud_bottom..cloud_top] along ray:
    density = sample_density(step.pos)
    if density > 0:
      shadow = shadow_march(step.pos, sun_dir)   // 태양 방향 짧은 마치
      scatter = henyey_greenstein(cos_theta) * shadow
      light_sum     += scatter * density * step_size * transmittance
      transmittance *= exp(-density * extinction * step_size)
    if transmittance < 0.01: break
  pixel_color = sky_color * transmittance + light_sum
```

### 2-2. 밀도 함수 (Density Field)

구름 형태는 **Worley + Perlin FBM 혼합**으로 생성한다.  
- 기저 형태(Base Shape): 저주파 Perlin FBM (3–4 옥타브)
- 세부 침식(Detail Erosion): 고주파 Worley noise로 솜뭉치 가장자리 표현
- 높이 감쇠(Height Gradient): 구름 층 상단/하단 부드러운 페이드

```glsl
// 의사 코드 (GLSL)
float density_at(vec3 p) {
    float base  = fbm_perlin(p * 0.0008, 4);        // 큰 덩어리
    float erode = worley(p * 0.004, 3) * 0.4;       // 솜털 침식
    float shape = max(0.0, base - erode);
    // 높이 감쇠: cloud_bottom~cloud_top 사이에서만 밀도 있음
    float ht = smoothstep(cloud_bottom, cloud_bottom + 500.0, p.y)
             * smoothstep(cloud_top,    cloud_top    - 200.0, p.y);
    return shape * ht * cloud_density_scale;
}
```

날씨 유형별 파라미터:

| 날씨 | cloud_bottom (m) | cloud_top (m) | density_scale | base_freq | 형태 특성 |
|------|-----------------|--------------|---------------|-----------|----------|
| CIRRUS | 6000 | 12000 | 0.05 | 0.0002 | 얇은 섬유·실 형태; 에로전 강함 |
| CUMULUS | 600 | 2500 | 0.6 | 0.0008 | 뭉게 덩어리; 하단 평탄 |
| OVERCAST (층운) | 400 | 1200 | 0.9 | 0.0005 | 균일한 레이어; 형태 뭉개짐 |
| CUMULONIMBUS | 500 | 10000 | 1.2 | 0.0008 | 상단 anvil 모양; Phase 3 |
| CLEAR / RAIN | 별도 처리 | — | — | — | RAIN: 낮은 OVERCAST + 더 짙은 밀도 |

### 2-3. 조명 계산

#### 태양 산란 (Beer-Lambert + Henyey-Greenstein)
```
transmittance_sun = exp(-sum_density_along_sun_ray * sigma_ext)
scatter_coeff     = henyey_greenstein(cos_theta, g=0.8)   // 앞 산란 강한 구름
```

#### 다중 산란 근사
정확한 다중 산란은 레이마치 비용이 너무 높다.  
Guerrilla Games (Horizon) 기법을 참조:
- 단일 산란 결과에 `ms_factor = 0.5` 감쇠 계수를 누적해 가짜 다중 산란 표현
- 구름 내부(두꺼운 부분)가 완전히 검게 되지 않도록 환경광(ambient) 하한 추가

#### 달빛·별빛 조명
야간에는 `sun_lux → moon_lux`로 조명 세기 전환.  
달빛 색온도(4100K~5000K) 적용.

### 2-4. 하늘 배경과 합성

현재 `ProceduralSkyMaterial` 위에 구름 결과를 올려야 한다.  
Godot Forward+ 에서는 **SubViewport + Compositor Effect** 또는  
**WorldEnvironment의 custom sky shader**로 처리 가능하다.

권장 방식: **SubViewport 분리 렌더 → 알파 합성**
1. 구름 전용 SubViewport (해상도: 화면의 50–25%)
2. FullScreen Quad에서 sky_texture와 cloud_texture를 pre-multiplied alpha 합성
3. Sky.gd의 `ProceduralSkyMaterial` 색상은 구름 레이어 아래에 위치

> 사람 확인 필요: Godot 4.7 Forward+에서 SubViewport + Compositor 방식이  
> ProceduralSkyMaterial과 ZBuffer 충돌 없이 작동하는지 실제 테스트 필요.

---

## 3. 모바일 LOD 전략

ROADMAP 원칙: "모바일이 성능 기준선"  
구름 레이마칭은 모바일 GPU에서 무거울 수 있으므로 3단계 품질 LOD가 필수.

### LOD 0 — 웹 / 저사양 모바일

현재 방식 유지: 단일 평면 메쉬 스크롤 UV 셰이더.  
개선사항:
- 날씨 유형별 텍스처 스와이핑 (CIRRUS용 줄무늬, CUMULUS용 덩어리)
- 투명도 조절로 OVERCAST 표현

비용: 거의 없음 (현재와 동일)

### LOD 1 — 앱 / 중사양 모바일

**Impostor Billboard** 방식:
- 구름 덩어리를 Billboard 스프라이트 20–50개로 구성
- 각 Billboard에 미리 렌더한 구름 임포스터 텍스처 사용
- 태양 방향에 따라 음영이 달라지도록 노멀맵 텍스처 포함
- 비용: 버텍스 처리만, 픽셀 레이마치 없음

성능 기준: 스마트폰 중급 GPU에서 60fps 유지 가능해야 함

### LOD 2 — PC / 고사양

본격 레이마칭:
- 스크린 해상도의 50%에서 레이마치 → TAA / 업스케일로 풀해상도 복원
- 스텝 수: 최대 64 (반투명 영역에서는 얼리 탈출)
- 섀도 마치: 태양 방향 8–16 스텝만

성능 기준: RX 580 / GTX 1060 이상에서 60fps 유지

### LOD 선택 자동화

```gdscript
# Main.gd 또는 새 CloudManager.gd
func _pick_cloud_lod() -> int:
    var vram_mb: int = RenderingServer.get_video_adapter_api_version().to_int()
    if OS.get_name() in ["Web", "Android", "iOS"]:
        return 0 if _is_low_end_mobile() else 1
    return 2   # PC는 기본 LOD 2
```

---

## 4. 전환 경로 (기존 단일 레이어 → 볼류메트릭)

단계적 전환을 통해 언제든 "현재 상태"로 릴리스 가능하도록 유지한다.

### Step 1: 파라미터 인터페이스 통일 (Phase 1 또는 Phase 3 진입 직전)

새 클래스 `CloudParams`(리소스 또는 딕셔너리) 정의:
```gdscript
var cloud_bottom_m: float   # 구름 하단 고도 (m)
var cloud_top_m: float      # 구름 상단 고도 (m)
var cloud_opacity: float    # 0.0–1.0
var cloud_type: String      # "CIRRUS" | "CUMULUS" | "STRATUS" | "CB"
var wind_drift: Vector2     # UV 이동 속도 (현재 방식과 동일 인터페이스)
```
`Sky.gd`의 `_update_clouds()` 함수가 이 딕셔너리를 받도록 리팩토링.  
이 단계에서는 기존 단일 레이어가 그대로 작동하고, 인터페이스만 맞춤.

### Step 2: LOD 1 (Billboard Impostor) 추가 (Phase 3 초기)

- `CloudManagerLOD1.gd` 신규 작성
- `Sky.gd`는 LOD 플래그에 따라 기존 메쉬를 숨기고 LOD1 매니저를 활성화
- 두 방식이 동시에 코드에 공존; 플래그로 전환

### Step 3: LOD 2 (레이마칭) 추가 (Phase 3 중후반)

- 커스텀 컴포지터 이펙트 또는 SubViewport 구현
- LOD 0/1/2 세 방식이 모두 플래그로 선택 가능

### Step 4: LOD 0 대체 (Phase 3 완료 후)

- 기존 단일 레이어 텍스처를 날씨 유형별 텍스처로 업그레이드
- LOD 0를 "개선된 2D" 버전으로 교체, 코드 정리

> 사람 확인 필요: Step 2의 Billboard impostor 방식이 모바일에서 실제로  
> 단일 레이어보다 시각적으로 충분히 나아 보이는지 확인 필요.

---

## 5. 오브젝트 상호작용 설계

### 5-1. 나무·지형 그림자 (Cloud Shadow on Ground)

- 구름 밀도 필드의 투과율을 별도 텍스처(shadow map)에 투영
- 지면 셰이더에 `cloud_shadow_tex` uniform 추가 → albedo 감쇠
- LOD 0: 없음 / LOD 1: 소프트 원형 그림자 / LOD 2: 실제 투영 맵

### 5-2. 구름 내부 안개 (In-cloud Fog)

카메라가 구름 고도에 들어가면 (해당 고도에 밀도 > 임계치):
- `WorldEnvironment.fog_density`를 즉시 높임
- 가시거리 급감 + 회색 안개 색 적용
- 현재 구름은 지상에서만 보이므로 Phase 3 이후 유효

### 5-3. 달·별 가림

레이마칭 결과의 transmittance 값을 Sky.gd에 전달:
```gdscript
# CloudManager → Sky.gd
sky._set_cloud_cover(transmittance_at_moon_dir, transmittance_at_star_layer)
```
- 달 셰이더의 알파에 `cloud_cover_moon` 곱
- 별 MultiMesh의 per-instance alpha에 `cloud_cover_stars` 곱
- LOD 0/1에서는 현재처럼 `cloud_opacity` 단일 값으로 근사

### 5-4. 대류 조건 (Convection Feedback)

Phase 3의 자동 날씨에서:
- 기온·습도가 높고 맑으면 → CUMULUS 성장 → 오후 뇌우 가능성
- 밀도 함수에 `instability_index` 파라미터를 추가해 CB(적란운) 형성 여부 결정
- 이 파라미터는 Weather.gd의 기상 시뮬과 연동

### 5-5. 강수 발생원 (Precipitation Source)

현재 강수는 날씨 유형에서 직접 파티클을 켠다.  
볼류메트릭 구름 도입 후:
- 구름 밀도 > 강수 임계치 → 해당 위치에서 강수 파티클 시작
- 구름 경계와 강수 파티클 위치가 일치해 자연스러운 강우 표현

---

## 6. 알려진 리스크 및 사람 확인 필요 항목

| 항목 | 리스크 | 확인 방법 |
|------|--------|---------|
| Godot 4.7 SubViewport + ProceduralSkyMaterial ZBuffer 충돌 | 하늘이 구름 위에 그려지거나 뎁스가 꼬일 수 있음 | 실제 프로토타입 |
| 모바일 레이마치 성능 | 저/중급 폰에서 10fps 미만 가능 | 실기기 프로파일링 필수 |
| TAA와 구름 반투명의 고스팅 | 움직이는 구름 경계에 흔들림 아티팩트 | 스크린샷 비교 |
| 구름 고도 하드코딩 vs 기압 연동 | 지형 기반 구름 높이가 달라야 할 경우 | Phase 2 지형 설계 후 결정 |
| Noise 텍스처 VRAM 사용량 | 3D Worley + Perlin 텍스처가 수십 MB 가능 | 모바일 VRAM 예산 검토 |

---

*생성: Claude Code 무인 야간 설계 (2026-06-29)*  
*코드 없음 — 설계 문서 전용*  
*사람 확인 필요: 기술 선택 타당성, 성능 수치, Godot API 버전 호환성*
