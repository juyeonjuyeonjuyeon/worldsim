# 절차적 사운드 아키텍처 설계 (Procedural Audio Architecture)

설계 기준: 2026-06-29  
대상 단계: Phase 4  
현재 구조: `Sound.gd` — WAV 루프/원샷 파일 기반 재생

---

## 1. 현황 분석

### 현재 구현 (`Sound.gd`)

| 사운드 | 파일 | 방식 |
|--------|------|------|
| 비 (3단계) | `rain_light.wav`, `rain_medium.wav`, `rain_heavy.wav` | AudioStreamPlayer 루프 |
| 바람 | `wind_loop.wav` | AudioStreamPlayer 루프 |
| 눈 | `snow_loop.wav` | AudioStreamPlayer 루프 |
| 천둥 (3거리) | `thunder_close.wav`, `thunder_mid.wav`, `thunder_far.wav` | AudioStreamPlayer 원샷 |

한계:
- 표면 재질 무관 (지면·잎·웅덩이·금속 지붕 → 동일한 빗소리)
- 공간 잔향 없음 (숲 속·계곡·야외 평원 동일)
- 강수율이 연속값이지만 사운드는 3단계 이산 전환 (클릭 아티팩트)
- 바람: 식생·지형에 무관한 단일 루프
- 천둥: 거리가 3단계로만 표현 (연속 음색 변화 없음)

---

## 2. 절차적 사운드 목표

"녹음 파일 재생"이 아닌 **물리 상태에서 실시간으로 계산된 사운드**.  
구체 목표:
1. **재질 반응 (Material Response)**: 같은 비도 흙·잎·웅덩이·금속에서 다르게 들림
2. **공간 잔향 (Spatial Reverb)**: 지형 밀폐도에 따른 잔향 변화
3. **연속 강도 (Continuous Intensity)**: 강수율 0.0→1.0이 끊김 없이 음색에 반영
4. **합성 기반 (Synthesis-based)**: 최소한의 WAV 사용, 나머지는 가산·감산 합성

---

## 3. 아키텍처 구조

### 3-1. 핵심 컴포넌트

```
SoundEngine (Sound.gd 대체)
  ├── PrecipitationLayer
  │     ├── GroundImpact (재질별)
  │     ├── CanopyDrip (잎면)
  │     ├── PuddleRipple (수면)
  │     └── AmbientHiss (공중)
  ├── WindLayer
  │     ├── LeafRustle
  │     ├── TreeGroan
  │     └── AirStream
  ├── ThunderEngine
  │     └── CrackRumble (거리·기온 파라미터)
  ├── SnowLayer
  │     └── GroundCreak / Silence
  └── SpatialProcessor
        ├── ReverbZone (지형 밀폐도)
        └── LowPassFilter (거리 감쇠)
```

### 3-2. 재질별 빗소리 모델

빗방울이 닿는 표면은 4개 채널로 구분한다.

#### 채널 A: 지면 (Ground Impact)
- 빗방울 충돌 → 충격음 + 공기 방울 팝 소리
- 합성: 짧은 band-pass 필터 임펄스 (10–30ms)
- 파라미터:
  - `ground_wetness`: 건조 지면 = 탁한 충격음 / 습윤 지면 = 높은 피치 팝
  - `rain_rate`: 충돌 빈도 (poisson process로 타이밍 생성)
  - `soil_type`: 흙(저음)·잔디(중음)·콘크리트(고음) — Phase 2 지형 연동 전까지는 단일 값

#### 채널 B: 잎면 (Canopy Drip)
- 잎에 닿은 빗방울 → 얇은 "띡띡" 소리 + 잎 진동 저주파
- 합성: 고주파 클릭(600–2000Hz) + 느린 LFO 진폭 변조
- 파라미터:
  - `leaf_density` (Environment.gd의 나무 수 기반)
  - `wind_speed`: 잎 흔들림으로 타이밍 불규칙화

#### 채널 C: 수면 (Puddle Ripple)
- 웅덩이에 떨어지는 빗방울 → 물 팝 소리
- 합성: 저주파 임펄스(80–300Hz) + 짧은 잔향
- 파라미터:
  - `water_depth`, `puddle_count` (Environment.gd 웅덩이 개수 기반)

#### 채널 D: 공중 히스 (Ambient Hiss)
- 많은 빗방울이 공중에서 내는 화이트 노이즈 성분
- 합성: Band-pass 화이트 노이즈 (400–4000Hz), `rain_rate`로 진폭 변조
- 현재 `rain_medium.wav`가 이 역할을 하는 WAV임 → 이것을 합성으로 대체

#### 최종 믹스
```
output = A * mix_ground + B * mix_canopy + C * mix_puddle + D * mix_hiss
```
`mix_*` 계수는 각 환경 재질 비율에서 자동 계산.

### 3-3. 연속 바람 소리 모델

현재: 단일 루프 WAV  
목표: 풍속·방향·지형에 반응하는 합성 바람

레이어 구조:
1. **Air Stream**: 저주파 잡음 (20–200Hz) — 공기 흐름 기본
2. **Leaf Rustle**: 고주파 "쏴" (1000–5000Hz) — `leaf_density * wind_speed`
3. **Tree Groan**: 주기적 진동 (2–15Hz) — 큰 나무 줄기 흔들림; wind_speed > 6m/s 활성
4. **Whistle**: 좁은 공간 통과 시 공명음 — Phase 2 지형 이후

진폭 변조: 바람은 일정하지 않음. Perlin 노이즈로 풍속 변동(gusts) 표현:
```gdscript
var gust_factor = 1.0 + 0.3 * noise.get_noise_1d(Time.get_ticks_msec() * 0.001)
wind_volume = base_volume * gust_factor
```

### 3-4. 천둥 소리 물리 모델

현재: 3거리 WAV 원샷  
목표: 번개 거리·기온·습도를 받아 실시간 파형 생성

천둥 소리 구성:
- **크랙 (Crack)**: 번개 채널 가열·팽창 → 날카로운 충격음 (< 1ms)
- **럼블 (Rumble)**: 번개 경로 전체 길이에서 지연 도달 → 수초 지속 저주파 진동
- 거리 효과:
  - 가까울수록 크랙 선명 + 럼블 짧음
  - 멀수록 크랙 없음 + 럼블만 길게 (저주파 우세)
  - 공식: `rumble_duration = max(1.0, distance_km * 0.8)` 초

```gdscript
# 의사 코드
func generate_thunder(distance_km: float, temperature_c: float) -> AudioStream:
    var crack_intensity = exp(-distance_km * 0.4)    # 가까울수록 크랙 강함
    var rumble_freq     = 30.0 + temperature_c * 0.5 # 기온 → 음속 → 공명
    var rumble_dur      = max(1.0, distance_km * 0.8)
    # synthesize_crack() + synthesize_rumble() → 합산 반환
```

Godot에서 실현 방법:
- `AudioStreamGenerator` + `AudioStreamGeneratorPlayback` 로 실시간 PCM 생성
- GDScript에서 직접 PCM 버퍼에 쓰기 가능 (비용: CPU 1–2ms/프레임)

> 사람 확인 필요: GDScript PCM 생성의 CPU 비용이 모바일에서 수용 가능한지  
> 실기기 프로파일링 필요.

### 3-5. 공간 잔향 (Spatial Reverb)

Godot `AudioEffectReverb`를 **버스 기반**으로 구성:

```
AudioServer Bus: "Weather"
  ├── AudioEffectLowPassFilter (거리 고주파 감쇠)
  ├── AudioEffectReverb
  │     room       = _calculate_room_size()
  │     wet        = _calculate_wet_mix()
  │     predelay   = distance_km * 3.0   // ms
  └── AudioEffectAmplify

func _calculate_room_size() -> float:
    # 나무 밀도·지형 밀폐도 → 0.0(야외) ~ 1.0(동굴)
    var openness = 1.0 - (tree_count / MAX_TREES) * 0.4
    return 1.0 - openness   // 높을수록 큰 잔향
```

초기에는 "야외 + 숲" 두 프리셋으로 단순화하고,  
Phase 2 지형 이후 지형 개방도를 실제로 계산.

---

## 4. Godot 구현 가능 범위 (현실적 평가)

### 가능한 것 (GDScript + Godot 내장)

| 기능 | API | 비용 |
|------|-----|------|
| Poisson 타이밍 생성 | GDScript RNG | 낮음 |
| Band-pass 필터 | AudioEffectFilter | 낮음 |
| 실시간 PCM 합성 | AudioStreamGenerator | 중간 (CPU) |
| 잔향 버스 | AudioEffectReverb | 낮음 |
| LPF 거리 감쇠 | AudioEffectLowPassFilter | 낮음 |
| 진폭 변조 (LFO) | AudioEffectAmplify + 코드 | 낮음 |

### 어려운 것 (GDScript 한계)

| 기능 | 이유 | 대안 |
|------|------|------|
| 물리 기반 파형 합성 (Karplus-Strong, FM) | GDScript 실시간 DSP 느림 | C++ GDExtension 또는 WAV 사전 생성 |
| 진짜 물리적 천둥 합성 | 복잡한 DSP | 고품질 WAV 라이브러리 + 파라미터 믹싱 |
| 바이노럴/HRTF 공간음 | Godot 내장 없음 | 외부 라이브러리 (SteamAudio GDExtension) |
| 신호 처리 정밀도 | GDScript float 한계 | C++ Extension |

---

## 5. 단계적 도입 계획

### Phase 4-0: 인터페이스 준비 (Phase 3와 병행 가능)

Sound.gd를 **파라미터 기반 인터페이스**로 리팩토링.  
WAV는 그대로, 파라미터 받는 구조만 바꿈:

```gdscript
# 현재
func set_weather(rain: float, wind: float, snow: float): ...

# 목표
func set_weather(params: WeatherSoundParams): ...
# WeatherSoundParams:
#   rain_rate: float          # 0.0–1.0
#   rain_surface_mix: Dictionary  # { "ground": 0.6, "canopy": 0.3, "puddle": 0.1 }
#   wind_speed: float
#   leaf_density: float
#   reverb_openness: float    # 0.0(숲) ~ 1.0(야외)
#   thunder_distance_km: float
#   temperature_c: float
```

Main.gd가 이 파라미터를 채워서 전달.  
이 단계에서는 파라미터를 받아도 내부는 여전히 WAV 믹싱.

### Phase 4-1: 잔향 버스 추가

`AudioEffectReverb` 버스를 코드로 생성, `reverb_openness` 파라미터로 조절.  
사운드 파일 변경 없음; 잔향만 추가.

> 사람 확인 필요: 잔향 추가 후 기존 빗소리가 자연스럽게 들리는지 귀 검수.

### Phase 4-2: 연속 빗소리 믹싱

기존 3단계(light/medium/heavy) 대신 `rain_rate` 연속값으로:
- AudioStreamPlayer 3개를 크로스페이드 믹싱
- `rain_rate 0.0–0.33 → light`, `0.33–0.66 → light+medium 크로스페이드` 등
- 전환 시 클릭 아티팩트 제거

> 사람 확인 필요: 크로스페이드 속도·커브가 자연스러운지 귀 검수.

### Phase 4-3: 재질별 레이어 추가

채널 B(잎면)·C(수면) WAV 파일 추가 + 믹서 구현.  
`CanopyDripPlayer`, `PuddleRipplePlayer`를 별도 AudioStreamPlayer로:
- `leaf_density > 0.3` → 잎면 채널 활성
- `water_depth > 0` → 수면 채널 활성

### Phase 4-4: 합성 기반 전환

채널 D (공중 히스) 먼저 합성으로 대체:
- `AudioStreamGenerator`로 band-pass white noise 실시간 생성
- WAV rain_medium 파일과 A/B 비교 청취 후 교체 결정

이후 단계별로 채널 A·B·C도 합성으로 전환.

### Phase 4-5: 천둥 파라미터 믹싱

`thunder_distance_km` 연속 값 기반으로 기존 3개 WAV를 믹싱:
- `d < 1km → close×1.0`, `d < 5km → close×(5-d)/4 + mid×(d-1)/4`, 등
- 진짜 합성은 GDExtension 결정 후 교체

---

## 6. 전체 아키텍처 다이어그램

```
Main.gd
  │ WeatherSoundParams (rain_rate, surface_mix, wind_speed, reverb_openness, ...)
  ▼
SoundEngine.gd (Sound.gd 대체)
  ├── PrecipitationMixer
  │     ├── GroundChannel  ─── AudioStreamPlayer(loop)
  │     ├── CanopyChannel  ─── AudioStreamPlayer(loop)
  │     ├── PuddleChannel  ─── AudioStreamPlayer(loop)
  │     └── HissChannel    ─── AudioStreamGenerator(realtime)
  ├── WindMixer
  │     ├── AirStream      ─── AudioStreamPlayer(loop)
  │     ├── LeafRustle     ─── AudioStreamPlayer(loop)
  │     └── Gust LFO       ─── AudioEffectAmplify (코드로 조절)
  ├── ThunderEngine
  │     └── ThunderPlayer  ─── AudioStreamPlayer (WAV or Generator)
  └── SpatialProcessor (AudioServer Bus: "Weather")
        ├── AudioEffectLowPassFilter
        ├── AudioEffectReverb
        └── AudioEffectAmplify
```

---

## 7. 알려진 리스크 및 사람 확인 필요 항목

| 항목 | 리스크 | 확인 방법 |
|------|--------|---------|
| GDScript 실시간 PCM 합성 CPU 비용 | 모바일에서 오디오 버벅임 가능 | 실기기 프로파일링 |
| 잔향 버스 레이턴시 | AudioEffectReverb tail이 날씨 전환 시 잘림 가능 | 귀 검수 |
| 재질별 사운드 레이어 수 | 레이어 과다 → CPU 믹싱 비용 | 레이어당 비용 측정 |
| Phase 2 지형 연동 전 재질 단순화 | 흙·잔디·콘크리트 구분 불가 | 단일 기본값으로 시작 |
| 사운드 파일 라이선스 | 새 WAV 추가 시 CC0/라이선스 확인 필요 | 파일별 검토 |

---

*생성: Claude Code 무인 야간 설계 (2026-06-29)*  
*코드 없음 — 설계 문서 전용*  
*사람 확인 필요: 모든 귀 검수 항목, GDExtension 도입 여부 결정*
