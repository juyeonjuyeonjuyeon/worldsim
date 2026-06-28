# 무인 야간 작업 보고서 (Overnight Report)

작업 일시: 2026-06-29 (자동 진행)  
기반 작업: ROADMAP.md 8번 항목  
작업자: Claude Code (무인)

---

## 1. 완료한 작업

### A. `docs/PHENOMENA_AUDIT.md` ✅

- **감사 범위**: `Astronomy.gd`, `Sky.gd`, `Environment.gd`, `Weather.gd`, `Main.gd`, `Sound.gd`
- **구현된 현상**: 35개 항목 — 천문 19개 + 기상/대기 16개 (사운드 4종 포함)
- **미구현 현상**: 55개 항목 — 6개 카테고리로 분류
  - 천문: 14개 (일식·월식·오로라·녹색섬광·황도광·은하수·토성고리 등)
  - 광학: 17개 (햇무리·신기루·박명광선·광환·브로켄 스펙터 등)
  - 강수/수문: 11개 (우박·진눈깨비·이슬비·언비 등)
  - 기상역학: 7개 (기온역전·토네이도·해륙풍 등)
  - 지표: 4개 (생물발광·용암 야광 등)
  - 사운드: 6개 (절차적 빗소리·바람 등)
- 각 미구현 항목에 **필요 입력값 / 난이도 / 의존 Phase** 기재

### B. `docs/CLOUD_DESIGN.md` ✅

- 레이마칭 볼류메트릭 구름 접근법 전체 설계
- 날씨 유형별 밀도 파라미터 표 (CIRRUS→CB까지 고도·density_scale·freq)
- **3단계 LOD 전략**: LOD 0 (기존 UV 셰이더 유지), LOD 1 (Billboard Impostor), LOD 2 (레이마치)
- **4단계 전환 경로**: 파라미터 인터페이스 통일 → LOD 1 추가 → LOD 2 추가 → LOD 0 개선
- **5가지 오브젝트 상호작용 설계**: 지면 그림자·내부 안개·달별 가림·대류 조건·강수 발생원
- 알려진 리스크 및 사람 확인 필요 항목 명시

### C. `docs/AUDIO_DESIGN.md` ✅

- 현재 WAV 루프 방식의 한계 분석
- 재질별 빗소리 4채널 모델 (지면·잎·수면·공중 히스)
- 연속 바람 소리 레이어 구조 + Perlin gust 변동
- 천둥 소리 물리 모델 (크랙 + 럼블, 거리·기온 파라미터)
- 공간 잔향 (`AudioEffectReverb`) 버스 설계
- Godot 구현 가능/어려운 것 분류표
- **5단계 도입 계획**: 인터페이스→잔향버스→연속믹싱→재질레이어→합성전환

### D. 특수현상 UI 스텁 ✅

**변경 파일**: `godot_app/UI.gd`, `godot_app/Main.gd`  
**컴파일 확인**: `Godot --headless --quit` 오류 없음 (리크 경고는 정상 종료 시 예상 동작)

변경 내용:
- `UI.gd`: 테스트 탭에 `special_row` 행 추가 (투명도 0.55로 미구현 표시)
  - 버튼: 일식 / 월식 / 오로라 / 무지개↑
  - 각 버튼이 `test_event_requested` 신호로 `"solar_eclipse"` / `"lunar_eclipse"` / `"aurora"` / `"rainbow_force"` emit
- `Main.gd`: `_on_test_event` match에 4개 TODO 스텁 추가 (`push_warning` 출력, 렌더 효과 없음)

> 기존 렌더 경로 무영향 확인: 새 match 브랜치는 `push_warning`만 호출.  
> 기존 브랜치(`lightning`·`meteor`·`shower`·`comet`) 변경 없음.

---

## 2. 남긴 TODO

### 즉시 가능 (Phase 1, 현 구조 유지)
- `solar_eclipse`: 달이 태양 디스크를 가리는 셰이더 → 사람 눈 검수 필요
- `lunar_eclipse`: 달 적화(붉은달) 셰이더 + 밝기 감쇠 → 사람 눈 검수 필요
- `aurora`: 오로라 볼류메트릭 레이어 → 사람 눈 검수 필요
- `rainbow_force`: 무지개 표시 강제 켜기 (하늘 맑아도 보임) → 사람 눈 검수 필요
- 은하수 배경 텍스처 추가
- 녹색 섬광 이벤트 구현
- 달무지개 (무지개 셰이더 달 방위 기준 버전)
- 과잉호 (주무지개 내측 간섭 줄무늬)
- 토성 고리 렌더

### Phase 3 이후 (볼류메트릭 구름 필요)
- 햇무리·환일·광환·채운 (빙정 조건 연동)
- 박명광선·신기루 (지형 셰이더 필요)

### Phase 2+ (지형 격자 필요)
- 기후 격자 연동 자동 날씨
- 지형 기반 재질 사운드
- 생물발광·화산·해안 안개

---

## 3. 사람 확인 필요 항목

| 항목 | 위치 | 이유 |
|------|------|------|
| Sky.gd brt-노출 버그 수정 | Phase 0 잔여 | 야간 암막·박명 갈색 — 무인 금지, 아침에 스크린샷 보며 검수 |
| CLOUD_DESIGN.md: SubViewport + ProceduralSky 충돌 | docs/ | 실제 프로토타입 없이 확인 불가 |
| CLOUD_DESIGN.md: Billboard Impostor 시각 품질 | docs/ | 단일 레이어 대비 충분히 나은지 귀납 확인 필요 |
| AUDIO_DESIGN.md: GDScript PCM CPU 비용 | docs/ | 실기기 프로파일링 필요 |
| AUDIO_DESIGN.md: 잔향 버스 추가 후 빗소리 | docs/ | 귀 검수 필요 |
| 특수현상 버튼 투명도 0.55 | UI.gd:special_row | 미구현 느낌이 적절한지 시각 확인 |

---

## 4. 절대 건드리지 않은 것

모두 ROADMAP 무인 절대 규칙 준수:
- 셰이더 코드 (Sky.gd·Environment.gd 내부 shader string) → 변경 없음
- 노출/톤매핑 로직 → 변경 없음
- 박명 색상 테이블 → 변경 없음
- 천체 렌더 코드 → 변경 없음
- 사운드 파일/믹싱 → 변경 없음
- 밤 암막·박명 갈색 버그 → 변경 없음 (아침 사람 검수 대기)

---

## 5. 파일 목록

```
신규 생성:
  docs/PHENOMENA_AUDIT.md    — 현상 감사표
  docs/CLOUD_DESIGN.md       — 볼류메트릭 구름 설계
  docs/AUDIO_DESIGN.md       — 절차적 사운드 설계
  docs/OVERNIGHT_REPORT.md   — 본 보고서

수정:
  godot_app/UI.gd            — 특수현상 버튼 행 추가 (11줄)
  godot_app/Main.gd          — TODO 스텁 match 브랜치 4개 추가 (4줄)
```

---

*생성: Claude Code 무인 야간 (2026-06-29)*
