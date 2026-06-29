# 무인 자동 작업 로그

작업 일시: 2026-06-29  
작업자: Claude Code (무인)  
체크포인트 커밋: b7f86e0

---

## 진행 순서

1. [x] 체크포인트 커밋 (b7f86e0)
2. [x] 1순위: 하늘 색 대기 산란 Step 1 (Preetham → ProceduralSkyMaterial)
3. [x] 2순위: rainbow_force 스텁 → 실제 무지개 강제 표시
4. [ ] 3순위: 일식 구현 (동결영역 — 아침 수동 작업)
5. [x] 4순위: 원인 존재 미구현 현상들
6. [x] 5순위 일부: 암순응 lux 연동, 달 대기 적화
7. [ ] 5순위 나머지: 궤적 표시, 별자리 미화, 오로라, UI 정리

---

## 로그

### [START] 2026-06-29 무인 작업 시작
- CLAUDE.md 규칙 확인 완료
- 체크포인트 커밋 b7f86e0 생성
- Sky.gd 색 파이프라인 분석 시작

### [1순위 완료] Preetham 대기 산란 Step 1

**변경 내용 (Sky.gd):**
- 8개 수동 하드코딩 색 (`day_top` 등) 삭제
- `_preetham_sky_colors(elevation, 3.0)` 함수 호출로 대체 (6줄)
- Preetham(1999) 분석 모델: Perez 분포 함수 + CIE xyY → 선형 sRGB
- T=3.0 혼탁도 기본값, SCALE=0.05 (θ_s=45°에서 청색≈0.95 기준)
- Layer A(≥−2°): Preetham 출력, Layer B(<−6°): 기존 야간 색 유지, 혼합구간: lerp

**커밋:** feat: Preetham 대기 산란 모델 (이전 세션)

### [2순위 완료] rainbow_force 실제 구현

- `_rainbow_force` 변수 추가, `force_rainbow(enabled)` 함수 추가
- `_update_rainbow()` 시그니처에 `moon: Dictionary` 추가 (달무지개 지원)
- Main.gd: rainbow_force 버튼 토글 연결

**커밋:** feat: rainbow_force 실제 무지개 강제 (이전 세션)

### [4순위 완료] 원인 존재 미구현 현상들

#### 녹색 섬광 (Green Flash)
- `_prev_sun_elev` / `_green_flash_t` 변수 추가
- 태양 지평선 횡단 감지 (고도 ±0.15°, 느린 속도, 맑은 하늘)
- 태양 셰이더에 `green_flash` uniform 추가
- ALBEDO에 green_flash 가중 mix 적용

#### 과잉호 (Supernumerary Rainbow)
- 무지개 셰이더에 `supernumerary_str` uniform 추가
- 40.6°-36.5° 구간 파동 간섭 패턴: cos((ang-36.5)/1.5 × 6.28)
- 작은 물방울(안개비)일수록 강하게, 굵은 물방울일수록 약하게

#### 달무지개 (Moonbow)
- 동일 Descartes 각도(40.6°~42.5°), moon_dir 기준
- 최대 강도 0.04 (태양무지개의 4%)
- 반달 이상 + 태양 -5° 이하 + 비 이력 조건

#### 안개무지개 (Fogbow)
- 안개 밀도 > 0.003 + 비 없음 + 태양 가시 조건
- 34°~43° 넓은 흰색 호 (각도가 더 넓고 색이 없음)
- 별도 fogbow 셰이더 (색 없이 흰색)

#### 황도광 (Zodiacal Light)
- 태양 방위각 ±35° 원뿔 방향
- 태양 -1° ~ -25° 구간 박명 조건
- 구름 Beer-Lambert 억제

#### 대기광 (Airglow)
- 태양 -18° 이하 깊은 밤 조건
- OI 557.7nm (녹색), OH 밴드 — night_horizon/night_top에 직접 합산
- `Color(0.003, 0.012, 0.005)` × airglow_t

#### 은하수 (Milky Way)
- PrimitiveSphere r=399, mw_shader (is_shader_type spatial, blend_add)
- 은하 북극(J2000 RA=192.859°, Dec=27.129°) + 은하 중심(RA=266.405°, Dec=-28.936°)
- 세차 보정 + AltAz 변환 → gal_pole/gal_center 셰이더 파라미터
- 태양 -10° 이하 + clear_sky 조건으로 intensity 0.20 fade in

#### 행성 합/충 표시
- `planet_events: String` 공개 변수 추가
- 행성-행성 각거리 < 1.5° → "X·Y 합 (Z.Z°)"
- 태양 이각 > 170° → "X 충", < 3° → "X 합"
- Main.gd: planet_events가 있을 때 상태 표시줄에 추가

#### 토성 고리
- PlaneMesh flat disc, 고리 셰이더 (C ring 내부~A ring 외부, Cassini 간극 포함)
- 토성 자전 극 RA=40.589°, Dec=83.537° → 세차 보정 → 3D ring normal 정렬
- sat_scale 배율로 planet disc와 비율 맞춤

### [수동→물리 마이그레이션] Sky.gd [수동] 항목 2-3 완료

#### 암순응 scotopic → lux 연속 연동
- 이전: eye_view on/off → 4× 고정 부스트
- 이후: total_lux 기반 Purkinje 이동 연속 계산
- 0.001 lux → scotopic_w=1.0 (4× 부스트, B×1.15/G×0.90/R×0.80)
- 0.3 lux → scotopic_w=0.0 (1× 부스트)
- 채도 플로어도 scotopic_w 기반 연속 변화

#### 달 대기 적화 → Rayleigh 파장별 소광
- 이전: moon_warm = clamp(1-alt/18°) + 수동 색값
- 이후: air_mass = 1/sin(alt), τ: R=0.028, G=0.094, B=0.360
- lit_color = (1.0, 0.98×ray_g/rnorm, 0.92×ray_b/rnorm)
- DirectionalLight도 동일 모델

### [B·E 수정] 하늘 산란 입력 + 무지개 클리핑 버그 수정 (2026-06-29 추가 세션)

**진단 선행 결과:**
- A 정상, C 정상(광원 수동 보정 존재하나 충돌 아님), F 정상
- B 오류: maxf(elevation,0.0) → 박명 전 구간 ts=90° 고정 → 최대 circumsolar glow 잔류
- D 오류(미수정): gm_h=π/2−ts → 태양 방향 지평선만 샘플 → 360° 균일 적용 → 정오 붉음
- E 오류: horizon_fade +0.5 오프셋 → 지평선에서 50% 투명, 색띠 전환 폭 0.4° 너무 좁음

#### [커밋 0fcce8d] fix(B): 박명 구간 ts=90° 고정 수정
- Sky.gd:1263 `maxf(elevation, 0.0)` → `maxf(elevation, -6.0)`
- Sky.gd:2114 `gm_h` 하한 0 → `deg_to_rad(5.0)` (5°)
  - ts→90° 극단값에서 최대 circumsolar glow 방지
  - 수치 검증: 일몰 horizon R/G/B 1.693/0.847/0 → 1.439/0.723/0 (약 15% orange 감소)

#### [커밋 577e390] fix(E): 무지개 지평선 클리핑 + 색띠 부드러움 + 야간 강제 차단
- Sky.gd:750 `horizon_fade`: `clamp(y*12+0.5,0,1)` → `clamp(y*20,0,1)` — 지평선 하드 클리핑
- Sky.gd:761 band1 smoothstep 전환 폭 0.4° → 1.1° (색 경계 부드러움)
- Sky.gd:770 band2 smoothstep 전환 폭 동일 확대
- Sky.gd:991 `_rainbow_force` sun_elev < 1° 시 강제 차단 (야간 원형 무지개 방지)

**스크린샷 검수 (docs/screenshots/verify_noon_B수정후.png):**
- 정오(12:00) 맑음 — 천정: 파랑 정상, 지평선: 핑크/자주 잔류 (D항 미수정, 예상)
- 렌더 깨짐 없음, 컴파일 통과 → 1차 필터 통과
- **사람 최종 확인 대기** — 박명 조건(시간 19:58~20:20), 무지개 강제 조건 별도 확인 필요

---

### [2차 진단] 노을 범위 + 밤 밝기/깜빡임 (2026-06-27 추가 세션)

**실측 데이터:**
```
sky_curve = 0.15  (기본값, 코드에서 명시 설정 없음 — Sky.gd:297~300)

Preetham (elev=0°):  sky_top=(0.090, 0.086, 0.108) / sky_horizon=(1.439, 0.723, 0) / 비율 7.6×
Preetham (elev=45°): sky_top=(0.243, 0.367, 0.716) / sky_horizon=(0.897, 0.668, 0.668) / 비율 1.7×
```

**항목별 판정:**

| 항목 | 판정 | 근거 |
|------|------|------|
| A. 천정각 계산 | 정상 | ProceduralSky = world Y 기준, 카메라 독립 |
| B. 지평선 기준 | 정상 | v_world_dir_y와 ProceduralSky 모두 world Y=0 동일 |
| C. 감쇠 곡선 | **오류** | sky_curve=0.15(기본값) → 지수=6.67 → 고도 45°에서 sky_horizon 88% 적용 |
| D. 밤 밝기 | **의심** | tonemap_exposure의 sky 적용 여부 불확실 + `*16.0` 가정 |
| E-1. 깜빡임 | **오류** | -2°~-6° 구간 44:1 휘도차를 선형 lerp → 5.5 stops 급변 |
| E-2. 깜빡임 | **오류** | exposure 상한 -2°에서 이미 cap, sky_horizon은 무관하게 44× 급락 |

**C항 핵심 — sky_curve=0.15가 노을 범위 전체의 원인:**
```
blend = mix(sky_horizon, sky_top, pow(max(dir.y, 0.0), 1.0/0.15))
      = mix(sky_horizon, sky_top, pow(dir.y, 6.67))

고도 45° → pow(0.707, 6.67) = 0.117 → sky_horizon 88% 기여
고도 20° → pow(0.342, 6.67) ≈ 0.0005 → sky_horizon 100% 기여
```
일몰 sky_horizon=(1.44, 0.72, 0) 오렌지가 하늘 80% 이상에 꽉 참.

**수정안 (사용자 확인 후):**
- C항: `_sky_mat.sky_curve = 0.45` (지수=2.2 → 45°에서 horizon 55%)
- D항: tonemap_exposure 적용 여부 먼저 검증 후 `*16.0` 배율 조정
- E항: 선형 lerp → 지수 lerp + 전환 구간 -1°~-10° 확대

**상태: 사람 확인 후 수정 예정**

---

### [C·D·E 수정] 하늘 셰이더 3종 수정 (2026-06-29 추가 세션)

#### [커밋 0bc8f6c] fix(C): sky_curve 0.15 → 0.45

- `_build_sky_and_lights()` 에 `_sky_mat.sky_curve = 0.45` 추가
- 블렌딩 지수 6.67 → 2.22: 고도 45°에서 sky_horizon 기여 88% → 54%
- 스크린샷(19:45): 일몰 하늘 확인 — D항 이중노출과 혼재해 C항 단독 효과 판정 불가
- **사람 최종 확인 대기** (D·E 수정 후 일몰 재확인 필요)

#### [커밋 0d69f82] fix(D): night_top/horizon * 16.0 제거

- `night_top`, `night_horizon` 에서 `* 16.0` 제거
- 검증: ProceduralSkyMaterial은 Godot 4 HDR 버퍼에서 tonemap 패스를 거침 → 기존 * 16.0은 tonemap_exposure(최대 16×)와 이중 곱셈 → 256× 과밝음
- 스크린샷(22:00): 어두운 야간 하늘 + 달 원반·달빛 정상 확인
- **사람 최종 확인 대기** (20·22시·심야 직접 확인 필요)

#### [커밋 aa20149] fix(E): 박명~야간 전환 smoothstep + log 보간

- 혼합 구간 확대: -2°~-6° (4°) → -2°~-10° (8°)
- 가중치: 선형 → smoothstep (S커브)
- 색 보간: 선형 → log 공간 (지수 감쇠, eps=1e-5)
  - 이유: 560:1 선형 밝기비 → 지각상 급변·깜빡임. log 보간으로 인지 균등 전환.
- 스크린샷(20:18): 중간 단계 자연스러운 전환 확인
- **사람 최종 확인 대기** — 실시간 시뮬레이션에서 깜빡임 유무 확인 필요

---

## 남은 작업

| 항목 | 우선순위 | 난이도 | 상태 |
|------|---------|--------|------|
| **D항: gm_h 방향 수정** | **최우선** | **중** | **커스텀 Sky 셰이더로 처리 예정** |
| 일식/월식 | 3순위 | 상 | 동결영역 — 아침 수동 작업 |
| 이슬 (Dew) | 4순위 | 중 | Phase 3 (지면 텍스처) |
| 먼지 회오리 | 4순위 | 중 | Phase 3 (파티클) |
