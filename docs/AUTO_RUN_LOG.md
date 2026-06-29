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

## 남은 작업

| 항목 | 우선순위 | 난이도 | 상태 |
|------|---------|--------|------|
| **D항: gm_h 방향 수정** | **최우선** | **중** | **커스텀 Sky 셰이더로 처리 예정** |
| 일식/월식 | 3순위 | 상 | 동결영역 — 아침 수동 작업 |
| 이슬 (Dew) | 4순위 | 중 | Phase 3 (지면 텍스처) |
| 먼지 회오리 | 4순위 | 중 | Phase 3 (파티클) |
