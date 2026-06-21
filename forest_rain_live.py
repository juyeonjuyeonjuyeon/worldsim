"""
WS_forest_rain 실시간 관찰 도구 (forest_rain_live.py)

forest_rain.py(오프라인 Cycles 배치 렌더용)에 쓴 물리 코드를 그대로 재사용해,
Blender를 직접 열고 이 스크립트를 실행하면 EEVEE 실시간 뷰포트 + 오른쪽
사이드바("N"키) 슬라이더 패널로 날씨/시간대를 즉시 조절하며 관찰할 수 있음.

조절 가능: 날씨(맑음/시러스/큐뮬러스/흐림/비/눈), 강수강도(mm/hr), 바람
유무/속도(m/s), 위도/경도/UTC오프셋/연·월·일/시간대(0~24시, 실제 태양·달·
별 위치에 반영됨).
슬라이더를 옮기면 즉시 적용되고 뷰포트가 다시 그려짐 — 애니메이션을
재생하지 않아도 바로 반영됨.

한계(정직하게 밝힘):
- EEVEE는 실시간 래스터라이저라 Cycles 경로추적만큼 광원/볼륨 산란이
  정확하지 않음. 구름/안개 같은 볼륨은 보이지만 디테일이 Cycles보다 거칢.
- 최종 고품질 출력은 여전히 forest_rain.py(Cycles, 수십 분 소요)로 따로
  뽑아야 함 — 이 도구는 "보면서 값을 정하는" 용도.
- 실행 방법: Blender를 GUI로 직접 열고 (블렌더 파일은 새로 만들어도 됨),
  상단 'Scripting' 탭 → 이 파일을 열고 '▶ Run Script'(Alt+P) 클릭.
  3D 뷰포트에서 'N' 키를 누르면 오른쪽에 "WS Weather" 패널이 나타남.
"""
import bpy
import bmesh
import mathutils
import numpy as np
import math
import random
import sys
import os
import wave
import datetime

# ── 실제 천문 계산(skyfield: NASA JPL 천체력 de421.bsp + Hipparcos 별 목록) ──
# Blender 내장 Python의 site-packages는 Program Files 하위라 일반 권한으로 못
# 쓰므로, 같은 폴더의 _vendor/에 --target으로 설치해 sys.path에 추가만 함.
def _find_script_dir():
    # Blender Text Editor에서 "Run Script"(Alt+P)로 실행하면 __file__이
    # 실제 디스크 경로가 아니라 "//forest_rain_live.py" 같은 블렌더 내부
    # 상대경로(저장 안 된 새 .blend에서는 깨진 경로)로 잡히는 경우가 있어,
    # __file__만 믿지 않고 텍스트 블록 자체의 filepath를 먼저 확인함.
    for text in bpy.data.texts:
        if text.name == "forest_rain_live.py" and text.filepath:
            candidate = os.path.dirname(bpy.path.abspath(text.filepath))
            if os.path.isdir(os.path.join(candidate, "_vendor")):
                return candidate
    try:
        candidate = os.path.dirname(os.path.abspath(__file__))
        if os.path.isdir(os.path.join(candidate, "_vendor")):
            return candidate
    except NameError:
        pass
    return r"C:\Users\kkjjy\Documents\WorldSim"  # 마지막 수단: 알려진 기본 위치

_SCRIPT_DIR = _find_script_dir()
_VENDOR_DIR = os.path.join(_SCRIPT_DIR, "_vendor")
if _VENDOR_DIR not in sys.path:
    sys.path.append(_VENDOR_DIR)  # 끝에 추가 — Blender 내장 numpy를 가리지 않도록

from skyfield.api import Loader, wgs84, Star
from skyfield import almanac
from skyfield.data import hipparcos

_EPHEM_DIR = os.path.join(_SCRIPT_DIR, "_ephem_cache")
_sky_loader = Loader(_EPHEM_DIR)
_ts = _sky_loader.timescale()
_eph = _sky_loader('de421.bsp')
_EARTH, _SUN, _MOON = _eph['earth'], _eph['sun'], _eph['moon']

_star_catalog = {}  # 빌드 시 1회 로드 (ra_deg, dec_deg, mag 배열) — lazy

def _load_star_catalog(mag_limit=5.0):
    """맨눈 가시 등급(5등급)까지의 Hipparcos 별 ~1600개. 망원경급 전천 카탈로그는
    아니지만, 이 도구가 보여주려는 '맨눈으로 본 밤하늘'에는 그게 정답."""
    if _star_catalog:
        return _star_catalog
    with _sky_loader.open(hipparcos.URL) as f:
        df = hipparcos.load_dataframe(f)
    df = df[(df['magnitude'] <= mag_limit) & df['ra_degrees'].notna() & df['dec_degrees'].notna()]
    _star_catalog["stars"] = Star.from_dataframe(df)
    _star_catalog["mag"] = df['magnitude'].to_numpy(dtype=np.float64)
    return _star_catalog

def sim_time(w):
    if w.real_time_mode:
        # "프레임 1 = sim_year/month/day + time_of_day" 를 시작 시점으로 두고,
        # 애니메이션이 재생되는 실제 시간(day_length_sec당 24시간)만큼 그 시점
        # 이후로 흘려보냄 — 슬라이더를 직접 만지지 않아도 재생만 하면 하루가
        # 실제로(밤낮·일출일몰·달/별 위치까지) 연속적으로 지나감. 날짜 경계도
        # 자연스럽게 넘어감(다음날로 이어짐).
        scene = bpy.context.scene
        elapsed_sim_hours = ((scene.frame_current - 1) / FPS) / max(w.day_length_sec, 1e-3) * 24.0
        start = datetime.datetime(w.sim_year, w.sim_month, w.sim_day) + datetime.timedelta(hours=w.time_of_day)
        effective = start + datetime.timedelta(hours=elapsed_sim_hours)
        utc_dt = effective - datetime.timedelta(hours=w.utc_offset)
        return _ts.utc(utc_dt.year, utc_dt.month, utc_dt.day,
                        utc_dt.hour, utc_dt.minute, utc_dt.second + utc_dt.microsecond / 1e6)
    utc_hour = w.time_of_day - w.utc_offset
    return _ts.utc(w.sim_year, w.sim_month, w.sim_day, utc_hour, 0, 0)

def effective_local_time_str(w):
    """패널에 표시할 "지금 재생 중인 시점"의 사람이 읽는 표기."""
    t = sim_time(w)
    dt_utc = t.utc_datetime()
    local = dt_utc + datetime.timedelta(hours=w.utc_offset)
    return local.strftime("%Y-%m-%d %H:%M")

def observer_at(w):
    return _EARTH + wgs84.latlon(w.latitude, w.longitude)

def altaz_to_world_dir(alt_deg, az_deg):
    """고도/방위(북=0,동=90, 기상학 나침반 방위각) -> 이 씬의 월드 XYZ 방향.
    기존 sun.rotation_euler[0]=90-elev, [2]=az 조합이 만들어내는 실제 월드
    방향을 역산해서 맞춘 식 — 태양/달/별이 서로 같은 하늘에서 어긋나지 않게 함."""
    elev = np.radians(alt_deg)
    az = np.radians(az_deg)
    x = np.sin(az) * np.cos(elev)
    y = -np.cos(az) * np.cos(elev)
    z = np.sin(elev)
    return x, y, z

# ── 조도(lux) 모델 — 실제 자연계 밝기 기준점, 화면용으로 임의 보정하지 않음 ──
# 기준점(고도→조도): 맑은날 표준값 + 박명 단계(시민/항해/천문박명) 공인 근사치.
_SUN_ALT_ANCHORS = np.array([-18.0, -12.0, -6.0, 0.0, 10.0, 30.0, 60.0, 90.0])
_SUN_LUX_ANCHORS = np.array([0.0008, 0.008, 3.4, 400.0, 12000.0, 50000.0, 90000.0, 100000.0])
_SUN_LOG_LUX_ANCHORS = np.log10(_SUN_LUX_ANCHORS)
STARLIGHT_FLOOR_LUX = 0.0008   # 달 없는 맑은 밤(별빛+대기광) 바닥 조도

def sun_illuminance_lux(alt_deg):
    alt_deg = max(-18.0, min(90.0, alt_deg))
    log_lux = np.interp(alt_deg, _SUN_ALT_ANCHORS, _SUN_LOG_LUX_ANCHORS)
    return float(10.0 ** log_lux)

def moon_illuminance_lux(alt_deg, phase_fraction):
    # 보름달이 천정에 있을 때 ~0.27lx가 통용되는 근사치. 위상(phase_fraction)과
    # 고도(sin)에 비례해 줄어듦.
    if alt_deg <= 0.0:
        return 0.0
    return 0.27 * max(0.0, phase_fraction) * math.sin(math.radians(alt_deg))

# ── 조도(lux) -> Blender 단위, 그리고 "인간 눈" 인지적 노출 ──
# Blender Sun "Strength"는 단위상 W/m²지만, 이 씬의 노드/카메라 설정에서
# "맑은 정오"가 정상 노출로 보이려면 실측 발광효율(~120lm/W)이 아니라 이
# 보정상수가 필요함 — 이건 카메라 ISO/조리개를 고르는 것과 같은 "전체
# 캘리브레이션 하나"일 뿐, 시간대별 상대 밝기 비율(태양/달/박명 사이의
# 실제 조도 비율)은 lux 모델 그대로 유지되므로 "밝기를 임의로 바꾼" 게 아님.
LUX_TO_WATT = 0.4 / 100000.0
# 사람 눈은 명소시(낮)에는 거의 보정 없이 보고, 박명을 지나며 점점 더 크게
# 보정하다가(간상세포 전환), 칠흑 같은 무월광 야간에도 결국 한계에 부딪힘.
# 단일 지수가 아니라 실제 체감에 맞춘 구간별 기준점으로 직접 표현함 — 그래야
# "일몰~박명에서는 눈에 보이게 점점 어두워지다가, 그 이후로는 떨어지는 만큼
# 다 어두워지지 않고 보임"이라는 사람 시각의 실제 모양이 나옴.
REF_LUX = 100000.0          # 맑은 정오 수준 — sl(보조 스카이라이트)을 이 기준 비율로 스케일
# 0.0008~1lx(달빛 유무에 관계없이 "밤" 영역) 구간은 거의 평탄하게 강한 보정을
# 줌 — 그래야 보름달/그믐달처럼 둘 다 lux 자체가 매우 작은 영역에서, 고정
# night_sky_color 배경이 노출값 차이 때문에 거꾸로(달 없는 쪽이 더 밝아
# 보이는) 뒤집히지 않음. 달의 실제 밝기 차이는 moon_lamp 에너지가 이 같은
# 노출을 그대로 받아 표현 — 보름달 쪽만 추가로 밝아지는 식으로 나타남.
# 반면 3.4lx(시민박명) 이상은 Nishita 하늘 텍스처가 스스로 충분히 밝은 황혼
# 색을 내고 있는 구간이라 보정을 약하게 둬야 함 — 세게 주면 Nishita의 자연스러운
# 박명광까지 다시 한 번 곱해져 하늘 전체가 하얗게 날아감.
_EXP_LUX_ANCHORS = np.log10([STARLIGHT_FLOOR_LUX, 1.0, 3.4, 400.0, 12000.0, 100000.0])
_EXP_EV_ANCHORS = [19.5, 19.0, 7.0, 2.0, 0.0, 0.0]
MAX_EXPOSURE_BOOST = 19.5

def eye_adapted_exposure_ev(total_lux):
    """사람 눈의 암순응을 흉내냄 — 장면 자체의 물리적 밝기(total_lux)는 그대로
    두고, '카메라(눈) 노출'만 어두울수록 끌어올려서 인지적으로 보이게 함.
    이게 핵심: 빛 자체를 거짓으로 세게 만드는 게 아니라 보는 방식을 흉내냄."""
    log_lux = math.log10(max(total_lux, STARLIGHT_FLOOR_LUX))
    return float(min(MAX_EXPOSURE_BOOST, np.interp(log_lux, _EXP_LUX_ANCHORS, _EXP_EV_ANCHORS)))

def lux_to_watt(lux):
    return lux * LUX_TO_WATT

def scotopic_saturation(total_lux):
    """간상세포 야간시(흑백에 가까워짐, 퍼킨제 효과)의 근사. 채도만 낮추고
    밝기 자체는 위 노출 함수가 따로 처리."""
    lo, hi = math.log10(0.01), math.log10(400.0)
    t = (math.log10(max(total_lux, 1e-5)) - lo) / (hi - lo)
    t = max(0.0, min(1.0, t))
    return 0.15 + 0.85 * t

G = 9.81
FPS = 24.0
n_rain = 5000
FIELD_HALF = 15.0
START_HEIGHT = 9.0
GRID_N = 48
N_SIDES = 8
SPLASH_MAX = 300
STREAK_LEN = 0.40
SPLASH_WINDOW = 0.15
PUDDLE_GROWTH = 0.15
PUDDLE_DECAY = 0.004
RIPPLE_BOOST = 2.5
WETNESS_GROWTH_PER_SEC = 1.0 / 60.0    # 계속 비 오면 ~60초에 완전히 젖음
WETNESS_DECAY_PER_SEC  = 1.0           # 비 체크 끄면 ~1초 안에 마름(관찰용 즉시 전환)
PUDDLE_DECAY_OFF        = 0.08          # 비 없을 때 웅덩이가 빠르게(~0.5초) 사라짐
WIND_DIR_DEG = 30.0   # 바람 방향(고정, 세기/유무만 조절 대상)
WIND_DX = math.cos(math.radians(WIND_DIR_DEG))
WIND_DY = math.sin(math.radians(WIND_DIR_DEG))
CLOUD_DRIFT_AMP = 4.0

# ── 빗방울 크기/속도 분포 (forest_rain.py와 동일한 마샬-팔머/건-킨저 경험식) ──
def fall_distance(t, vt):
    return (vt ** 2 / G) * np.log(np.cosh(G * t / vt))

def fall_velocity(t, vt):
    return vt * np.tanh(G * t / vt)

def fall_duration(h, vt):
    A = np.exp(np.clip(h * G / vt ** 2, 0, 80))
    return (vt / G) * np.log(A + np.sqrt(np.maximum(A ** 2 - 1, 0)))

def lateral_drift(t, vt, wind_speed):
    tau = vt / G
    return wind_speed * (t - tau * (1.0 - np.exp(-t / tau)))

# =====================================================================
# 전역 상태 (PropertyGroup 콜백이 갱신, update_scene이 매 프레임/매 변경 읽음)
# =====================================================================
diam_mm = v_terminal = fall_dur = drop_phase = None
rain_size_scale = rain_active_mask = None
CYCLE_SEC = 7.0
x0 = y0 = ground_z = None
_height_grid = None
_gx = _gy = None
_activation_order = None  # 강수량에 따라 "몇 개를 보이게 할지" 고를 때 쓰는 고정 셔플 순서
ground_wetness_level = 0.0
ground_snow_level = 0.0

# ── 눈 — 강수 모양만 다른 동일 비/스플래시 오브젝트를 재사용(재질·베벨만 교체) ──
SNOW_FALL_SPEED = 0.9     # m/s, 항력이 커서 종단속도가 작고 입자간 편차도 작음
SNOW_SWIRL_AMP = 0.55
snow_fall_dur = snow_drop_phase = snow_flutter_phase = snow_flutter_freq = None
snow_size_scale = None
SNOW_CYCLE_SEC = 9.0
SNOW_GROWTH_PER_SEC = 1.0 / 90.0
SNOW_DECAY_PER_SEC = 0.25

def regenerate_snow_distribution(snow_rate=20.0):
    """강수강도(rain_rate 슬라이더를 적설 강도로 재사용)가 바뀔 때도 호출 —
    건-마샬(Gunn-Marshall 1958) 눈송이 크기분포로 송이 크기를 다시 계산.
    Λ(mm⁻¹) = 2.55·S^-0.48 (S=mm/hr 수당량) — 강한 눈일수록 작은 결정 대신
    뭉친 큰 송이(aggregate) 비중이 늘어나 평균 크기가 커짐(실제 기상학적
    경향). 양(보이는 송이 개수)은 update_scene의 frac_active가 따로 처리."""
    global snow_fall_dur, snow_drop_phase, snow_flutter_phase, snow_flutter_freq
    global SNOW_CYCLE_SEC, snow_size_scale
    snow_rate = max(snow_rate, 0.5)
    drop_height = START_HEIGHT - ground_z
    snow_fall_dur = drop_height / SNOW_FALL_SPEED
    SNOW_CYCLE_SEC = float(snow_fall_dur.max()) * 1.15
    np.random.seed(77)
    snow_drop_phase = np.random.uniform(0, SNOW_CYCLE_SEC, n_rain)
    snow_flutter_phase = np.random.uniform(0, 2 * np.pi, n_rain)
    snow_flutter_freq = np.random.uniform(0.3, 0.8, n_rain)
    LAMBDA_SNOW = 2.55 * snow_rate ** -0.48
    np.random.seed(58)
    _U = np.random.uniform(1e-6, 1.0, n_rain)
    snow_diam_mm = np.clip(-np.log(_U) / LAMBDA_SNOW, 0.5, 10.0)
    snow_size_scale = np.clip(snow_diam_mm / snow_diam_mm.mean(), 0.4, 2.5)

def ground_height_vec(xs, ys):
    ix = np.clip(np.searchsorted(_gx, xs), 0, GRID_N - 1)
    iy = np.clip(np.searchsorted(_gy, ys), 0, GRID_N - 1)
    return _height_grid[ix, iy]

def regenerate_rain_distribution(rain_rate):
    """강우강도가 바뀔 때만 호출 — 방울 크기/속도/낙하시간/주기를 다시 계산.
    착지 위치(x0,y0)는 강우강도와 무관(격자 배치)이라 그대로 둠.
    크기뿐 아니라 "양"(화면에 보이는 빗줄기 개수)도 강우강도에 따라 바뀜:
    마샬-팔머 분포의 총 입자 농도 N_total=N0/Λ ∝ Λ^-1 ∝ R^0.21 (Λ가 이미
    R^-0.21을 따르므로) — 강한 비일수록 더 굵은 방울뿐 아니라 단위면적당
    방울 수 자체도 늘어남(실제로도 그러함)."""
    global diam_mm, v_terminal, fall_dur, drop_phase, CYCLE_SEC
    global rain_size_scale, rain_active_mask
    rain_rate = max(rain_rate, 0.5)
    LAMBDA = 4.1 * rain_rate ** -0.21
    np.random.seed(42)
    _U = np.random.uniform(1e-6, 1.0, n_rain)
    diam_mm = np.clip(-np.log(_U) / LAMBDA, 0.4, 6.0)
    v_terminal = 9.65 - 10.3 * np.exp(-0.6 * diam_mm)
    drop_height = START_HEIGHT - ground_z
    fall_dur = fall_duration(drop_height, v_terminal)
    CYCLE_SEC = float(fall_dur.max()) * 1.15
    np.random.seed(99)
    drop_phase = np.random.uniform(0, CYCLE_SEC, n_rain)

    rain_size_scale = np.clip(diam_mm / diam_mm.mean(), 0.4, 2.2)
    R_REF = 50.0  # 이 강우강도(mm/hr, 호우 수준)에서 5000개 슬롯이 전부 보임
    frac_active = float(np.clip((rain_rate / R_REF) ** 0.21, 0.15, 1.0))
    n_active = max(1, int(round(n_rain * frac_active)))
    mask = np.zeros(n_rain, dtype=bool)
    mask[_activation_order[:n_active]] = True
    rain_active_mask = mask

    _regenerate_rain_sound()

# =====================================================================
# 사운드 — rain_sound.py와 동일한 물리(미네르트 기포 공명 + 마른땅 충격음)로
# 직접 합성(외부 오디오 라이브러리 불필요), Blender VSE 사운드 스트립으로
# 실시간 재생. "보이는 비"와 "들리는 비"가 같은 방울 분포에서 나옴.
# =====================================================================
SR = 44100
_SOUND_DIR = os.path.join(_SCRIPT_DIR, "_sound_cache")
os.makedirs(_SOUND_DIR, exist_ok=True)
_thunder_rng = np.random.default_rng()  # 천둥 타이밍용 — 빗방울 시드와 분리(매번 다르게)

def _write_wav_stereo(path, buf_lr):
    peak = max(float(np.abs(buf_lr).max()), 1e-9)
    pcm = (np.clip(buf_lr / peak * 0.85, -1.0, 1.0) * 32767.0).astype(np.int16)
    with wave.open(path, 'wb') as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())

def _synthesize_rain_cycle_buffer():
    """현재 diam_mm/v_terminal/fall_dur/drop_phase/CYCLE_SEC(=현재 강우강도)
    그대로 가져와 한 주기 분량을 합성 — rain_sound.py 22~109행과 동일 로직."""
    n_samples = int(round(CYCLE_SEC * SR))
    buf_l = np.zeros(n_samples)
    buf_r = np.zeros(n_samples)
    v_impact = v_terminal * np.tanh(G * fall_dur / v_terminal)
    impact_time = (fall_dur - drop_phase) % CYCLE_SEC
    pc = _state.get("puddle_centers", np.zeros((0, 2)))
    pmr = _state.get("puddle_max_r", np.zeros(0))
    if len(pc) > 0:
        dists = np.sqrt((x0[:, None] - pc[:, 0][None, :]) ** 2 + (y0[:, None] - pc[:, 1][None, :]) ** 2)
        is_puddle = (dists <= pmr[None, :]).any(axis=1)
    else:
        is_puddle = np.zeros(n_rain, dtype=bool)
    rng = np.random.default_rng(7)
    RHO_WATER = 1000.0
    for i in range(n_rain):
        if not rain_active_mask[i]:
            continue  # 약한 비에서 화면에 안 보이는 방울은 충돌음도 안 냄(양 일치)
        D_m = diam_mm[i] / 1000.0
        v = v_impact[i]
        mass = (4.0 / 3.0) * np.pi * (D_m / 2.0) ** 3 * RHO_WATER
        KE = 0.5 * mass * v ** 2
        if is_puddle[i]:
            r_bubble = 0.10 * D_m
            f0 = np.clip(3.285 / max(r_bubble, 1e-6), 200.0, 18000.0)
            Q = 14.0
            tau = Q / (np.pi * f0)
            dur = min(tau * 6.0, 0.05)
            n_s = max(int(dur * SR), 8)
            t = np.arange(n_s) / SR
            seg = np.exp(-t / tau) * np.sin(2 * np.pi * f0 * t)
            n_click = min(int(0.002 * SR), n_s)
            click_env = np.exp(-np.arange(n_click) / (n_click * 0.3 + 1e-9))
            seg[:n_click] += rng.uniform(-1, 1, n_click) * click_env * 0.5
            amp = (KE ** 0.28) * 1.0
        else:
            dur = np.clip(0.02 / max(diam_mm[i], 0.1), 0.003, 0.02)
            n_s = max(int(dur * SR), 4)
            t = np.arange(n_s) / SR
            env = np.exp(-t / (dur * 0.3))
            seg = rng.uniform(-1, 1, n_s) * env
            amp = (KE ** 0.28) * 0.6
        seg = seg * amp
        pan = np.clip((x0[i] + FIELD_HALF) / (2 * FIELD_HALF), 0.0, 1.0)
        gl, gr = np.sqrt(1.0 - pan), np.sqrt(pan)
        start = int(round(impact_time[i] * SR))
        n_s = len(seg)
        end = start + n_s
        if end <= n_samples:
            buf_l[start:end] += seg * gl
            buf_r[start:end] += seg * gr
        else:
            wrap = end - n_samples
            first = n_s - wrap
            buf_l[start:n_samples] += seg[:first] * gl
            buf_r[start:n_samples] += seg[:first] * gr
            buf_l[0:wrap] += seg[first:] * gl
            buf_r[0:wrap] += seg[first:] * gr
    return buf_l, buf_r

def _regenerate_rain_sound(tile_seconds=20.0):
    """강우강도가 바뀔 때마다 다시 호출 — 새 방울 분포로 루프 오디오를 다시
    합성. 한 주기(CYCLE_SEC)가 이미 매끄럽게 반복되므로 그대로 여러 번
    이어붙여(tile) 한 스트립이 더 오래 가도록 함(스트립 개수 절약)."""
    if "puddle_centers" not in _state or x0 is None:
        return  # 씬 빌드 전에는 아직 호출할 수 없음
    buf_l, buf_r = _synthesize_rain_cycle_buffer()
    n_tile = max(1, int(round(tile_seconds / CYCLE_SEC)))
    buf_l = np.tile(buf_l, n_tile)
    buf_r = np.tile(buf_r, n_tile)
    path = os.path.join(_SOUND_DIR, "rain_loop.wav")
    _write_wav_stereo(path, np.stack([buf_l, buf_r], axis=1))
    _state["rain_loop_path"] = path
    _state["rain_loop_frames"] = int(round(n_tile * CYCLE_SEC * FPS))
    _state["rain_sound_until"] = 0  # 다음 update_scene에서 바로 새 패턴으로 교체

def _synthesize_wind_loop(path, duration=12.0):
    """바람 소리 — 백색잡음을 여러 단 이동평균으로 갈색잡음에 가깝게 만들고
    (고역 깎임 = 나뭇잎 사이를 지나는 바람의 부드러운 질감), 두 개의 느린
    사인파를 곱해 실제 바람 특유의 gust(세졌다 약해졌다) 변화를 흉내냄."""
    n = int(duration * SR)
    rng = np.random.default_rng(11)
    white = rng.normal(0.0, 1.0, n)
    k = max(1, SR // 400)
    kernel = np.ones(k) / k
    sig = white
    for _ in range(3):
        sig = np.convolve(sig, kernel, mode='same')
    t = np.arange(n) / SR
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.07 * t) * np.sin(2 * np.pi * 0.013 * t + 1.3)
    sig = sig * gust
    _write_wav_stereo(path, np.stack([sig, sig * 0.97], axis=1))

def _synthesize_snow_loop(path, duration=14.0):
    """눈 — 빗방울처럼 또렷한 충돌음이 나지 않으므로(눈은 충돌해도 거의
    무음) 바람과 같은 잡음 기반이지만, 저역을 깎지 않고 고역 위주로 남겨
    "서걱거리는" 결정질 질감으로 바람과 구분함. 절대적인 크기는 합성
    단계가 아니라 재생 음량(volume)에서 비보다 훨씬 작게 줘서 표현."""
    n = int(duration * SR)
    rng = np.random.default_rng(23)
    white = rng.normal(0.0, 1.0, n)
    k = max(1, SR // 2000)  # 바람보다 훨씬 약한 평활화 -> 고역 더 많이 남음
    kernel = np.ones(k) / k
    hiss = np.convolve(white, kernel, mode='same')
    t = np.arange(n) / SR
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t) * np.sin(2 * np.pi * 0.021 * t + 0.7)
    sig = hiss * gust
    _write_wav_stereo(path, np.stack([sig, sig * 0.96], axis=1))

def _synthesize_thunder(path, seed, distance_factor):
    """천둥 — 저역 룸블(필터링한 잡음 + 느린 지수감쇠) + 가까울수록 비중이
    커지는 날카로운 초기 크랙(고역 임펄스). distance_factor(0=매우 가까움,
    1=멀리)로 룸블 길이/저역 정도/크랙 비중을 바꿔, "멀리서 우르릉"과
    "머리 위에서 쾅"의 실제 음향적 차이(고주파가 멀리서 먼저 흡수/산란되어
    사라지는 현상)를 근사함."""
    rng = np.random.default_rng(seed)
    dur = 2.5 + 4.0 * distance_factor
    n = int(dur * SR)
    t = np.arange(n) / SR
    white = rng.normal(0.0, 1.0, n)
    k = max(1, int(SR * (0.01 + 0.05 * distance_factor)))
    kernel = np.ones(k) / k
    rumble = white
    for _ in range(3):
        rumble = np.convolve(rumble, kernel, mode='same')
    decay = np.exp(-t / (0.6 + 1.8 * distance_factor))
    onset = 1.0 - np.exp(-t / 0.03)
    rumble = rumble * decay * onset
    crack_amp = max(0.0, 1.0 - distance_factor * 1.3)
    if crack_amp > 0:
        n_crack = int(0.05 * SR)
        crack = rng.uniform(-1, 1, n_crack) * np.exp(-np.arange(n_crack) / (n_crack * 0.25 + 1e-9))
        rumble[:n_crack] += crack * crack_amp
    _write_wav_stereo(path, np.stack([rumble, rumble], axis=1))
    return dur

# =====================================================================
# 재질 헬퍼
# =====================================================================
def make_mat(name, color, roughness=0.9, metallic=0.0, transmission=0.0, ior=1.45):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Transmission Weight"].default_value = transmission
    b.inputs["IOR"].default_value = ior
    return mat

# =====================================================================
# 씬 빌드 (한 번만 실행)
# =====================================================================
_tree_mats = []
_tree_sway = []

def make_tree(x, y, scale, seed):
    random.seed(seed)
    trunk_h = 2.8 * scale
    trunk_color = (0.18, 0.11, 0.04, 1)
    trunk_mat = make_mat(f"Trunk_{seed}", trunk_color)
    _tree_mats.append((trunk_mat, 0.9, False, trunk_color))
    for i in range(5):
        seg_h = trunk_h / 5
        r = 0.13 * scale * (1 - i * 0.14)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=r, depth=seg_h,
            location=(x, y, i * seg_h + seg_h / 2))
        bpy.context.active_object.data.materials.append(trunk_mat)

    sway_pivot = bpy.data.objects.new(f"TreeSway_{seed}", None)
    sway_pivot.location = (x, y, trunk_h * 0.40)
    bpy.context.collection.objects.link(sway_pivot)

    branch_color = (0.16, 0.09, 0.03, 1)
    branch_mat = make_mat(f"Branch_{seed}", branch_color)
    _tree_mats.append((branch_mat, 0.9, False, branch_color))
    for _ in range(random.randint(4, 6)):
        bz = trunk_h * random.uniform(0.35, 0.80)
        ba = random.uniform(35, 65)
        bd = random.uniform(0, 360)
        bl = scale * random.uniform(0.9, 1.6)
        ra, rd = math.radians(ba), math.radians(bd)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=6, radius=0.04 * scale, depth=bl,
            location=(x + math.sin(ra) * math.cos(rd) * bl * 0.5,
                      y + math.sin(ra) * math.sin(rd) * bl * 0.5,
                      bz + math.cos(ra) * bl * 0.5))
        b = bpy.context.active_object
        b.rotation_euler[1] = ra
        b.rotation_euler[2] = rd
        b.data.materials.append(branch_mat)
        b.parent = sway_pivot
        b.matrix_parent_inverse = sway_pivot.matrix_world.inverted()

    crown_base = trunk_h * 0.40
    for _ in range(random.randint(10, 16)):
        t = random.uniform(0, 1)
        sp = (1 - t * 0.45) * scale * 1.1
        ag = random.uniform(0, 360)
        cx = x + sp * math.cos(math.radians(ag)) * random.uniform(0.2, 1.0)
        cy = y + sp * math.sin(math.radians(ag)) * random.uniform(0.2, 1.0)
        cz = crown_base + t * trunk_h * 0.75 + random.uniform(-0.15, 0.15) * scale
        cr = scale * random.uniform(0.28, 0.52)
        g = random.uniform(0.18, 0.30)
        leaf_color = (0.04, g, 0.04, 1)
        lmat = make_mat(f"Leaf_{seed}_{_}", leaf_color)
        _tree_mats.append((lmat, 0.9, True, leaf_color))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=cr, location=(cx, cy, cz))
        cl = bpy.context.active_object
        cl.scale.z = random.uniform(0.65, 1.25)
        bpy.ops.object.transform_apply(scale=True)
        cl.data.materials.append(lmat)
        cl.parent = sway_pivot
        cl.matrix_parent_inverse = sway_pivot.matrix_world.inverted()

    n_cycles = random.randint(3, 7)
    amp = math.radians(5.0) / max(scale, 0.5)
    phase = random.uniform(0, 2 * math.pi)
    _tree_sway.append((sway_pivot, n_cycles, amp, phase))

def build_puddle_blob(px, py, search_r, water_depth=0.06):
    i_lo = max(0, np.searchsorted(_gx, px - search_r) - 1)
    i_hi = min(GRID_N, np.searchsorted(_gx, px + search_r) + 1)
    j_lo = max(0, np.searchsorted(_gy, py - search_r) - 1)
    j_hi = min(GRID_N, np.searchsorted(_gy, py + search_r) + 1)
    local = _height_grid[i_lo:i_hi, j_lo:j_hi]
    if local.size < 4:
        return None, 0.0
    water_level = float(np.percentile(local, 25)) + water_depth
    cell_w = _gx[1] - _gx[0]
    cell_h = _gy[1] - _gy[0]
    bm = bmesh.new()
    for i in range(i_lo, i_hi):
        for j in range(j_lo, j_hi):
            gxv, gyv = _gx[i], _gy[j]
            if (gxv - px) ** 2 + (gyv - py) ** 2 > search_r ** 2:
                continue
            if _height_grid[i, j] >= water_level:
                continue
            cx, cy = gxv - px, gyv - py
            v1 = bm.verts.new((cx - cell_w / 2, cy - cell_h / 2, 0.0))
            v2 = bm.verts.new((cx + cell_w / 2, cy - cell_h / 2, 0.0))
            v3 = bm.verts.new((cx + cell_w / 2, cy + cell_h / 2, 0.0))
            v4 = bm.verts.new((cx - cell_w / 2, cy + cell_h / 2, 0.0))
            bm.faces.new((v1, v2, v3, v4))
    if len(bm.faces) == 0:
        bm.free()
        return None, water_level
    mesh = bpy.data.meshes.new("WS_PuddleBlob")
    bm.to_mesh(mesh)
    bm.free()
    return mesh, water_level

_state = {}

def build_scene():
    global x0, y0, ground_z, _height_grid, _gx, _gy, _activation_order

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes): bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials): bpy.data.materials.remove(mat)
    for crv in list(bpy.data.curves): bpy.data.curves.remove(crv)
    _tree_mats.clear()
    _tree_sway.clear()

    # ── 빗방울 착지 격자 (지터드 그리드, 강우강도와 무관) ──
    grid_n = int(np.ceil(np.sqrt(n_rain)))
    cell = (2 * FIELD_HALF) / grid_n
    gi, gj = np.meshgrid(np.arange(grid_n), np.arange(grid_n), indexing='ij')
    gi = gi.ravel()[:n_rain]
    gj = gj.ravel()[:n_rain]
    np.random.seed(43)
    x0 = -FIELD_HALF + (gi + np.random.uniform(0.1, 0.9, n_rain)) * cell
    y0 = -FIELD_HALF + (gj + np.random.uniform(0.1, 0.9, n_rain)) * cell
    # 강우/적설 강도로 "몇 개를 보이게 할지" 고를 때 쓰는 고정 셔플 순서 —
    # 항상 같은 순서라 강도를 올리면 이전에 보이던 것들이 그대로 유지된 채
    # 새 것만 추가되는 식으로 늘어남(매번 무작위로 다시 뽑으면 깜빡거림).
    _activation_order = np.random.RandomState(321).permutation(n_rain)

    # ── 지형 ──
    # 이전엔 Terrain(50m, 굴곡 ±0.8m)이 끝나는 지점에서 HorizonGround(800m,
    # 완전히 평평 + z를 0.05m 낮춤)로 바로 이어붙여서, 그 경계에서 높이가
    # 갑자기 꺾이고 재질 색도 달라져 "땅에 그려진 경계선"처럼 보였음.
    # 수정: Displace 강도를 가장자리에서 0으로 줄이는 정점 그룹(falloff)을 줘서
    # Terrain 가장자리 자체를 평평하게 만들고, HorizonGround도 같은 z·같은
    # 재질(WetGround, 아래서 생성)을 쓰게 해 이음새를 없앰.
    bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, 0))
    terrain = bpy.context.active_object
    terrain.name = "Terrain"
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.subdivide(number_cuts=30)
    bpy.ops.object.mode_set(mode='OBJECT')

    falloff_vg = terrain.vertex_groups.new(name="EdgeFalloff")
    FALLOFF_INNER, FALLOFF_OUTER = 16.0, 24.0  # 50m 평면(반폭 25m) 가장자리 직전부터 0으로
    for v in terrain.data.vertices:
        r = math.hypot(v.co.x, v.co.y)
        wgt = 1.0 - float(np.clip((r - FALLOFF_INNER) / (FALLOFF_OUTER - FALLOFF_INNER), 0.0, 1.0))
        falloff_vg.add([v.index], wgt, 'REPLACE')

    displace = terrain.modifiers.new("Displace", 'DISPLACE')
    noise_tex = bpy.data.textures.new("TerrainNoise", type='CLOUDS')
    noise_tex.noise_scale = 3.0
    displace.texture = noise_tex
    displace.strength = 0.8
    displace.vertex_group = "EdgeFalloff"
    bpy.ops.object.modifier_apply(modifier="Displace")

    bpy.ops.mesh.primitive_plane_add(size=800, location=(0, 0, -0.01))
    horizon_ground = bpy.context.active_object
    horizon_ground.name = "HorizonGround"  # 재질은 ground_mat 완성 후 아래서 붙임(WetGround와 통일)

    # ── 지형 높이 그리드 (raycast) ──
    depsgraph = bpy.context.evaluated_depsgraph_get()
    _gx = np.linspace(-16, 16, GRID_N)
    _gy = np.linspace(-12, 12, GRID_N)
    _height_grid = np.zeros((GRID_N, GRID_N))
    for i, gxv in enumerate(_gx):
        for j, gyv in enumerate(_gy):
            origin = mathutils.Vector((gxv, gyv, 50.0))
            direction = mathutils.Vector((0.0, 0.0, -1.0))
            ok, loc, nrm, idx, obj, mat = bpy.context.scene.ray_cast(depsgraph, origin, direction)
            _height_grid[i, j] = loc.z if ok else 0.0
    ground_z = ground_height_vec(x0, y0)

    # ── 밀집도 그리드(웅덩이/습윤 마스크 위치 산출용, 강우강도와 무관) ──
    DENS_BINS = 24
    density_grid, dxe, dye = np.histogram2d(
        x0, y0, bins=DENS_BINS, range=[[-16, 16], [-12, 12]])
    dxc = 0.5 * (dxe[:-1] + dxe[1:])
    dyc = 0.5 * (dye[:-1] + dye[1:])

    def density_at(x, y):
        i = int(np.clip(np.searchsorted(dxc, x), 0, DENS_BINS - 1))
        j = int(np.clip(np.searchsorted(dyc, y), 0, DENS_BINS - 1))
        return density_grid[i, j] / max(density_grid.max(), 1.0)

    wet_attr = terrain.data.color_attributes.new(name="WetnessMask", type='FLOAT_COLOR', domain='POINT')
    for v in terrain.data.vertices:
        w = density_at(v.co.x, v.co.y)
        wet_attr.data[v.index].color = (w, w, w, 1.0)

    dry_color = (0.16, 0.24, 0.08, 1.0)
    wet_color = (0.05, 0.13, 0.03, 1.0)
    ground_mat = bpy.data.materials.new("WetGround")
    ground_mat.use_nodes = True
    gnt = ground_mat.node_tree
    gnodes, glinks = gnt.nodes, gnt.links
    gbsdf = gnodes["Principled BSDF"]
    gbsdf.inputs["Metallic"].default_value = 0.0
    vcol = gnodes.new("ShaderNodeVertexColor")
    vcol.layer_name = "WetnessMask"
    sep = gnodes.new("ShaderNodeSeparateColor")
    glinks.new(vcol.outputs["Color"], sep.inputs["Color"])
    densitymap = gnodes.new("ShaderNodeMapRange")
    densitymap.inputs["From Min"].default_value = 0.0
    densitymap.inputs["From Max"].default_value = 1.0
    densitymap.inputs["To Min"].default_value = 0.5
    densitymap.inputs["To Max"].default_value = 1.0
    glinks.new(sep.outputs["Red"], densitymap.inputs["Value"])
    ground_wetness_value = gnodes.new("ShaderNodeValue")
    ground_wetness_value.outputs[0].default_value = 0.0
    ground_wetness_value.label = "GlobalWetnessRamp"
    wmul = gnodes.new("ShaderNodeMath")
    wmul.operation = 'MULTIPLY'
    glinks.new(densitymap.outputs["Result"], wmul.inputs[0])
    glinks.new(ground_wetness_value.outputs[0], wmul.inputs[1])
    mixcol = gnodes.new("ShaderNodeMixRGB")
    mixcol.inputs["Color1"].default_value = dry_color
    mixcol.inputs["Color2"].default_value = wet_color
    glinks.new(wmul.outputs[0], mixcol.inputs["Fac"])
    # 눈 덮임 — 젖음 색 위에 흰색을 한 번 더 덮어씌움(SNOW 날씨일 때만 0보다 커짐)
    ground_snow_value = gnodes.new("ShaderNodeValue")
    ground_snow_value.outputs[0].default_value = 0.0
    ground_snow_value.label = "GlobalSnowRamp"
    snowcol = gnodes.new("ShaderNodeMixRGB")
    snowcol.inputs["Color2"].default_value = (0.92, 0.94, 0.97, 1.0)
    glinks.new(mixcol.outputs["Color"], snowcol.inputs["Color1"])
    glinks.new(ground_snow_value.outputs[0], snowcol.inputs["Fac"])
    glinks.new(snowcol.outputs["Color"], gbsdf.inputs["Base Color"])
    roughmap = gnodes.new("ShaderNodeMapRange")
    roughmap.inputs["From Min"].default_value = 0.0
    roughmap.inputs["From Max"].default_value = 1.0
    roughmap.inputs["To Min"].default_value = 0.85
    roughmap.inputs["To Max"].default_value = 0.40
    glinks.new(wmul.outputs[0], roughmap.inputs["Value"])
    glinks.new(roughmap.outputs["Result"], gbsdf.inputs["Roughness"])
    terrain.data.materials.append(ground_mat)
    horizon_ground.data.materials.append(ground_mat)  # Terrain과 같은 재질 -> 경계에서 색 안 끊김

    # ── 웅덩이 후보 (밀집도 기반, 강우강도와 무관 — 위치는 고정) ──
    puddle_mat = make_mat("Puddle", (0.03, 0.06, 0.08, 1), roughness=0.18, ior=1.333)
    pn = puddle_mat.node_tree.nodes.new("ShaderNodeTexNoise")
    pn.inputs["Scale"].default_value = 18.0
    pn.inputs["Detail"].default_value = 3.0
    pbump = puddle_mat.node_tree.nodes.new("ShaderNodeBump")
    pbump.inputs["Strength"].default_value = 0.25
    pbsdf = puddle_mat.node_tree.nodes["Principled BSDF"]
    puddle_mat.node_tree.links.new(pn.outputs["Fac"], pbump.inputs["Height"])
    puddle_mat.node_tree.links.new(pbump.outputs["Normal"], pbsdf.inputs["Normal"])

    n_puddles = 8
    order = np.argsort(density_grid.ravel())[::-1]
    min_sep = 3.0
    centers = []
    for flat in order:
        i, j = np.unravel_index(flat, density_grid.shape)
        if density_grid[i, j] <= 0:
            break
        cx, cy = dxc[i], dyc[j]
        if all((cx - px) ** 2 + (cy - py) ** 2 > min_sep ** 2 for px, py, _ in centers):
            centers.append((cx, cy, density_grid[i, j]))
        if len(centers) >= n_puddles:
            break
    max_density = max((c[2] for c in centers), default=1.0)

    puddle_objs, puddle_max_r, puddle_centers_list = [], [], []
    for px, py, density in centers:
        r_max = 1.2 + 1.8 * (density / max_density)
        blob_mesh, water_level = build_puddle_blob(px, py, r_max * 1.3)
        if blob_mesh is None:
            continue
        p = bpy.data.objects.new("WS_Puddle", blob_mesh)
        p.location = (px, py, water_level)
        p.scale = (0.001, 0.001, 1.0)
        bpy.context.collection.objects.link(p)
        p.data.materials.append(puddle_mat)
        puddle_objs.append(p)
        puddle_max_r.append(r_max)
        puddle_centers_list.append((px, py))
    puddle_max_r = np.array(puddle_max_r) if puddle_max_r else np.zeros(0)
    puddle_centers_arr = np.array(puddle_centers_list) if puddle_centers_list else np.zeros((0, 2))
    puddle_wetness = np.zeros(len(puddle_objs))

    # ── 나무 ──
    random.seed(7)
    for _ in range(22):
        x = random.uniform(-19, 19)
        y = random.uniform(-19, 19)
        if abs(x) < 5 and abs(y) < 5:
            continue
        make_tree(x, y, random.uniform(0.7, 1.8), random.randint(0, 9999))

    # ── 비/스플래시 ──
    rain_curve = bpy.data.curves.new("WS_RainCurve", type='CURVE')
    rain_curve.dimensions = '3D'
    rain_curve.bevel_depth = 0.004
    rain_curve.bevel_resolution = 1
    rain_curve.use_fill_caps = True
    for i in range(n_rain):
        sp = rain_curve.splines.new('POLY')
        sp.points.add(1)
        sp.points[0].co = (x0[i], y0[i], START_HEIGHT, 1.0)
        sp.points[1].co = (x0[i], y0[i], START_HEIGHT + STREAK_LEN, 1.0)
    rain_obj = bpy.data.objects.new("WS_Rain", rain_curve)
    bpy.context.collection.objects.link(rain_obj)
    rain_mat = bpy.data.materials.new("WaterStreak")
    rain_mat.use_nodes = True
    b = rain_mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.78, 0.87, 1.0, 1.0)
    b.inputs["Roughness"].default_value = 0.05
    b.inputs["Transmission Weight"].default_value = 0.85
    b.inputs["IOR"].default_value = 1.333
    b.inputs["Emission Color"].default_value = (0.78, 0.87, 1.0, 1.0)
    b.inputs["Emission Strength"].default_value = 0.15
    rain_obj.data.materials.append(rain_mat)

    # 눈은 같은 커브 오브젝트를 재사용(베벨 반경/재질만 SNOW일 때 교체) — 작고
    # 둥근 플레이크처럼 보이게 베벨을 키우고 두 끝점을 거의 붙여 점에 가깝게 함.
    snow_mat = bpy.data.materials.new("SnowFlake")
    snow_mat.use_nodes = True
    bsn = snow_mat.node_tree.nodes["Principled BSDF"]
    bsn.inputs["Base Color"].default_value = (0.95, 0.96, 0.98, 1.0)
    bsn.inputs["Roughness"].default_value = 0.6
    bsn.inputs["Emission Color"].default_value = (0.95, 0.96, 0.98, 1.0)
    bsn.inputs["Emission Strength"].default_value = 0.25

    splash_mesh = bpy.data.meshes.new("WS_SplashMesh")
    splash_verts, splash_faces = [], []
    for s in range(SPLASH_MAX):
        base_idx = len(splash_verts)
        for k in range(N_SIDES):
            ang = 2 * math.pi * k / N_SIDES
            splash_verts.append((math.cos(ang) * 0.001, math.sin(ang) * 0.001, -100.0))
        splash_faces.append(list(range(base_idx, base_idx + N_SIDES)))
    splash_mesh.from_pydata(splash_verts, [], splash_faces)
    splash_mesh.update()
    splash_obj = bpy.data.objects.new("WS_Splash", splash_mesh)
    bpy.context.collection.objects.link(splash_obj)
    splash_mat = bpy.data.materials.new("SplashRing")
    splash_mat.use_nodes = True
    bs = splash_mat.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (0.40, 0.52, 0.62, 1.0)
    bs.inputs["Roughness"].default_value = 0.6
    bs.inputs["Emission Color"].default_value = (0.40, 0.52, 0.62, 1.0)
    bs.inputs["Emission Strength"].default_value = 0.04
    splash_obj.data.materials.append(splash_mat)

    # ── 하늘/월드 ──
    world = bpy.data.worlds["World"]
    world.use_nodes = True
    wn, wl = world.node_tree.nodes, world.node_tree.links
    for n in list(wn): wn.remove(n)
    sky = wn.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(18)
    sky.sun_rotation = math.radians(100)
    sky.air_density = 1.0
    sky.aerosol_density = 5.5
    sky.ozone_density = 1.0
    # Nishita 하늘 모델은 해가 지평선 한참 아래로 내려가면 색이 그냥
    # (0,0,0) 검정을 출력함(물리적으로는 맞지만 — 빛 산란시킬 직사광이
    # 없으니까). 그 검정에 아무리 Strength를 곱해도 여전히 검정이라 "밤은
    # 무조건 새까매짐" 문제의 진짜 원인이었음. 고정된 야간 하늘색을 Mix로
    # 섞어서 밤에도 옅은 색이 남게 함 (apply_time_of_day가 Fac을 갱신).
    night_sky_color = wn.new("ShaderNodeRGB")
    # 옛 시스템(노출 보정 없음)에서 보이게 하려고 0.10~0.24로 키웠던 값 —
    # 이제는 인간 눈 노출 보정(eye_adapted_exposure_ev)이 따로 밤을 밝혀주므로
    # 여기는 실제 밤하늘 수준의 어두운 값을 둠(노출이 두 번 겹쳐 밤하늘이
    # 하얗게 날아가는 걸 막음).
    night_sky_color.outputs[0].default_value = (0.0000009, 0.0000013, 0.0000023, 1.0)
    sky_mix = wn.new("ShaderNodeMix")
    sky_mix.data_type = 'RGBA'
    wl.new(sky.outputs["Color"], sky_mix.inputs[6])     # A (Fac=0일 때)
    wl.new(night_sky_color.outputs[0], sky_mix.inputs[7])  # B (Fac=1일 때)
    bg = wn.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.45
    out_w = wn.new("ShaderNodeOutputWorld")
    wl.new(sky_mix.outputs[2], bg.inputs["Color"])
    wl.new(bg.outputs["Background"], out_w.inputs["Surface"])

    # ── 조명 ──
    bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
    sun = bpy.context.active_object
    sun.data.energy = 0.4
    sun.data.angle = math.radians(20)
    sun.rotation_euler[0] = math.radians(70)
    sun.rotation_euler[2] = math.radians(100)

    bpy.ops.object.light_add(type='AREA', location=(0, 0, 15))
    sl = bpy.context.active_object
    sl.data.energy = 90
    sl.data.size = 20
    sl.data.color = (0.60, 0.72, 1.0)

    # ── 달 (실제 위치/위상) ──
    bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
    moon_lamp = bpy.context.active_object
    moon_lamp.name = "MoonLamp"
    moon_lamp.data.energy = 0.0
    moon_lamp.data.angle = math.radians(0.5)
    moon_lamp.data.color = (0.80, 0.86, 1.0)

    MOON_DIST = 300.0
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.4, location=(0, 0, MOON_DIST))
    moon_disc = bpy.context.active_object
    moon_disc.name = "MoonDisc"
    moon_mat = bpy.data.materials.new("MoonSurface")
    moon_mat.use_nodes = True
    mnn, mnl = moon_mat.node_tree.nodes, moon_mat.node_tree.links
    for n in list(mnn): mnn.remove(n)
    m_geo = mnn.new("ShaderNodeNewGeometry")
    m_sundir = mnn.new("ShaderNodeCombineXYZ")  # 매 갱신 시 실제 태양 방향으로 채움
    m_dot = mnn.new("ShaderNodeVectorMath")
    m_dot.operation = 'DOT_PRODUCT'
    mnl.new(m_geo.outputs["Normal"], m_dot.inputs[0])
    mnl.new(m_sundir.outputs["Vector"], m_dot.inputs[1])
    m_terminator = mnn.new("ShaderNodeMapRange")  # 태양 방향 내적 -> 명/암 경계(자전 그림자선)
    m_terminator.inputs["From Min"].default_value = -0.05
    m_terminator.inputs["From Max"].default_value = 0.05
    m_terminator.clamp = True
    mnl.new(m_dot.outputs["Value"], m_terminator.inputs["Value"])
    m_mix = mnn.new("ShaderNodeMixRGB")
    m_mix.inputs["Color1"].default_value = (0.04, 0.045, 0.06, 1.0)   # 어두운 면(지구반사광 정도)
    m_mix.inputs["Color2"].default_value = (1.0, 0.98, 0.92, 1.0)     # 태양 비치는 면
    mnl.new(m_terminator.outputs["Result"], m_mix.inputs["Fac"])
    m_emit = mnn.new("ShaderNodeEmission")
    m_emit.inputs["Strength"].default_value = 3.0
    mnl.new(m_mix.outputs["Color"], m_emit.inputs["Color"])
    m_out = mnn.new("ShaderNodeOutputMaterial")
    mnl.new(m_emit.outputs["Emission"], m_out.inputs["Surface"])
    moon_disc.data.materials.append(moon_mat)
    # 달/별은 "카메라로 직접 보일 때만" 밝아야 함 — 실제 달빛/별빛에 의한 장면
    # 조명은 이미 moon_lamp(물리 조도 기반)가 따로 맡고 있는데, 이 발광 메시들을
    # Cycles의 디퓨즈/글로시 GI 광원으로도 그대로 두면 "작은 점이지만 Strength가
    # 커서" 장면 전체가 비정상적으로 밝아짐(실제로 별빛 GI는 무시할 수준).
    for vis in ("visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter", "visible_shadow"):
        setattr(moon_disc, vis, False)

    # ── 별 (Hipparcos 실제 별자리, mag<5 ~1600개) ──
    # 매 프레임 재계산 대신, 시간/위치가 바뀔 때만(update_scene 호출 시) skyfield로
    # 전체 별의 alt/az를 한 번에 벡터화 계산 -> 메쉬 정점 좌표만 갱신.
    star_mesh = bpy.data.meshes.new("WS_StarMesh")
    star_obj = bpy.data.objects.new("WS_Stars", star_mesh)
    bpy.context.collection.objects.link(star_obj)
    for vis in ("visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter", "visible_shadow"):
        setattr(star_obj, vis, False)

    star_mat = bpy.data.materials.new("StarEmission")
    star_mat.use_nodes = True
    snn, snl = star_mat.node_tree.nodes, star_mat.node_tree.links
    for n in list(snn): snn.remove(n)
    s_emit = snn.new("ShaderNodeEmission")
    s_emit.inputs["Color"].default_value = (0.92, 0.95, 1.0, 1.0)
    star_visibility = snn.new("ShaderNodeValue")  # night_blend(황혼 페이드)로 매 갱신
    star_visibility.label = "StarVisibility"
    star_visibility.outputs[0].default_value = 0.0
    s_mul = snn.new("ShaderNodeMath")
    s_mul.operation = 'MULTIPLY'
    s_mul.inputs[1].default_value = 25.0
    snl.new(star_visibility.outputs[0], s_mul.inputs[0])
    snl.new(s_mul.outputs["Value"], s_emit.inputs["Strength"])
    s_out = snn.new("ShaderNodeOutputMaterial")
    snl.new(s_emit.outputs["Emission"], s_out.inputs["Surface"])

    star_ng = bpy.data.node_groups.new("WS_StarPoints", 'GeometryNodeTree')
    star_ng.interface.new_socket(name="Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
    star_ng.interface.new_socket(name="Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')
    gnn, gnl = star_ng.nodes, star_ng.links
    g_in = gnn.new('NodeGroupInput')
    g_out = gnn.new('NodeGroupOutput')
    g_m2p = gnn.new('GeometryNodeMeshToPoints')
    g_attr = gnn.new('GeometryNodeInputNamedAttribute')
    g_attr.data_type = 'FLOAT'
    g_attr.inputs[0].default_value = "mag"
    g_map = gnn.new('ShaderNodeMapRange')
    g_map.inputs["From Min"].default_value = -1.5   # 시리우스 수준 가장 밝은 별
    g_map.inputs["From Max"].default_value = 5.0
    g_map.inputs["To Min"].default_value = 1.0
    g_map.inputs["To Max"].default_value = 0.12
    g_map.clamp = True
    g_combine = gnn.new('ShaderNodeCombineXYZ')
    g_ico = gnn.new('GeometryNodeMeshIcoSphere')
    g_ico.inputs["Radius"].default_value = 1.3
    g_iop = gnn.new('GeometryNodeInstanceOnPoints')
    g_setmat = gnn.new('GeometryNodeSetMaterial')
    g_setmat.inputs["Material"].default_value = star_mat
    gnl.new(g_in.outputs["Geometry"], g_m2p.inputs["Mesh"])
    gnl.new(g_m2p.outputs["Points"], g_iop.inputs["Points"])
    gnl.new(g_attr.outputs["Attribute"], g_map.inputs["Value"])
    gnl.new(g_map.outputs["Result"], g_combine.inputs["X"])
    gnl.new(g_map.outputs["Result"], g_combine.inputs["Y"])
    gnl.new(g_map.outputs["Result"], g_combine.inputs["Z"])
    gnl.new(g_combine.outputs["Vector"], g_iop.inputs["Scale"])
    gnl.new(g_ico.outputs["Mesh"], g_iop.inputs["Instance"])
    gnl.new(g_iop.outputs["Instances"], g_setmat.inputs["Geometry"])
    gnl.new(g_setmat.outputs["Geometry"], g_out.inputs["Geometry"])
    star_gn_mod = star_obj.modifiers.new("StarPoints", 'NODES')
    star_gn_mod.node_group = star_ng

    # ── 컴포지터: 어두울수록 채도를 낮춤(간상세포 야간시/퍼킨제 효과 근사) ──
    comp_ng = bpy.data.node_groups.new("WS_Compositor", 'CompositorNodeTree')
    bpy.context.scene.compositing_node_group = comp_ng
    comp_ng.interface.new_socket(name="Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    cpn, cpl = comp_ng.nodes, comp_ng.links
    c_rl = cpn.new('CompositorNodeRLayers')
    c_huesat = cpn.new('CompositorNodeHueSat')
    c_out = cpn.new('NodeGroupOutput')
    cpl.new(c_rl.outputs["Image"], c_huesat.inputs["Image"])
    cpl.new(c_huesat.outputs["Image"], c_out.inputs["Image"])

    # ── 구름(흐름) ──
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 20))
    cloud_obj = bpy.context.active_object
    cloud_obj.name = "CloudLayer"
    cloud_obj.scale = (140, 140, 16)
    bpy.ops.object.transform_apply(scale=True)
    cloud_mat = bpy.data.materials.new("CloudVolume")
    cloud_mat.use_nodes = True
    cnodes, clinks = cloud_mat.node_tree.nodes, cloud_mat.node_tree.links
    for n in list(cnodes): cnodes.remove(n)
    ctexcoord = cnodes.new("ShaderNodeTexCoord")
    cloud_mapping = cnodes.new("ShaderNodeMapping")
    clinks.new(ctexcoord.outputs["Object"], cloud_mapping.inputs["Vector"])
    ctex = cnodes.new("ShaderNodeTexNoise")
    ctex.inputs["Scale"].default_value = 2.5
    ctex.inputs["Detail"].default_value = 4.0
    clinks.new(cloud_mapping.outputs["Vector"], ctex.inputs["Vector"])
    cmap = cnodes.new("ShaderNodeMapRange")
    cmap.inputs["From Min"].default_value = 0.35
    cmap.inputs["From Max"].default_value = 0.65
    cmap.inputs["To Min"].default_value = 0.0
    cmap.inputs["To Max"].default_value = 1.0
    cmap.clamp = True
    cvol = cnodes.new("ShaderNodeVolumePrincipled")
    cvol.inputs["Color"].default_value = (0.75, 0.76, 0.78, 1.0)
    cmul = cnodes.new("ShaderNodeMath")
    cmul.operation = 'MULTIPLY'
    cmul.inputs[1].default_value = 0.10
    cout = cnodes.new("ShaderNodeOutputMaterial")
    clinks.new(ctex.outputs["Fac"], cmap.inputs["Value"])
    clinks.new(cmap.outputs["Result"], cmul.inputs[0])
    clinks.new(cmul.outputs["Value"], cvol.inputs["Density"])
    clinks.new(cvol.outputs["Volume"], cout.inputs["Volume"])
    cloud_obj.data.materials.append(cloud_mat)

    # ── 지면 실안개 ──
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.25))
    mist_obj = bpy.context.active_object
    mist_obj.name = "GroundMist"
    mist_obj.scale = (200, 200, 2.5)
    bpy.ops.object.transform_apply(scale=True)
    mist_mat = bpy.data.materials.new("GroundMistVolume")
    mist_mat.use_nodes = True
    mnodes, mlinks = mist_mat.node_tree.nodes, mist_mat.node_tree.links
    for n in list(mnodes): mnodes.remove(n)
    mvol = mnodes.new("ShaderNodeVolumePrincipled")
    mvol.inputs["Color"].default_value = (0.82, 0.85, 0.86, 1.0)
    mvol.inputs["Density"].default_value = 0.012
    mout = mnodes.new("ShaderNodeOutputMaterial")
    mlinks.new(mvol.outputs["Volume"], mout.inputs["Volume"])
    mist_obj.data.materials.append(mist_mat)

    # ── 카메라 ──
    bpy.ops.object.camera_add(location=(8, -16, 6.5))
    cam = bpy.context.active_object
    cam.rotation_euler[0] = math.radians(84)
    cam.rotation_euler[2] = math.radians(38)
    cam.data.lens = 35
    bpy.context.scene.camera = cam

    # ── 사운드(VSE 시퀀스 스트립으로 실시간 재생) ──
    scene_ = bpy.context.scene
    scene_.use_audio = True
    seq_ed = scene_.sequence_editor_create()
    wind_loop_path = os.path.join(_SOUND_DIR, "wind_loop.wav")
    _synthesize_wind_loop(wind_loop_path)
    snow_loop_path = os.path.join(_SOUND_DIR, "snow_loop.wav")
    _synthesize_snow_loop(snow_loop_path)

    _state.update(dict(
        rain_obj=rain_obj, splash_obj=splash_obj, rain_mat=rain_mat, snow_mat=snow_mat,
        puddle_objs=puddle_objs, puddle_max_r=puddle_max_r,
        puddle_centers=puddle_centers_arr, puddle_wetness=puddle_wetness,
        ground_wetness_value=ground_wetness_value, ground_snow_value=ground_snow_value,
        sky=sky, bg=bg, sun=sun, sl=sl, cloud_mapping=cloud_mapping,
        cloud_noise=ctex, cloud_cov=cmap, cloud_density_mul=cmul,
        cloud_obj=cloud_obj, mist_obj=mist_obj, sky_mix=sky_mix,
        moon_lamp=moon_lamp, moon_disc=moon_disc, moon_sundir_node=m_sundir,
        night_sky_color_node=night_sky_color,
        star_obj=star_obj, star_mesh=star_mesh, star_visibility=star_visibility,
        comp_huesat=c_huesat,
        seq_editor=seq_ed, wind_loop_path=wind_loop_path, wind_loop_frames=int(round(12.0 * FPS)),
        snow_loop_path=snow_loop_path, snow_loop_frames=int(round(14.0 * FPS)),
        rain_sound_until=0, wind_sound_until=0, snow_sound_until=0,
        rain_strip_active=None, wind_strip_active=None, snow_strip_active=None,
        lightning_flash_remaining=0, pending_thunder=None,
    ))

# =====================================================================
# 위도/경도/날짜/시각 -> 실제 태양·달·별 위치 + 조명 (skyfield)
# =====================================================================
def _lerp3(a, b, f):
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)

MOON_DIST = 300.0

def update_star_field(w, t, obs):
    """야간시(night_blend>0)일 때만 — Hipparcos 별의 alt/az를 skyfield로 한 번에
    벡터화 계산(~1600개, 수ms)해 메쉬 정점 좌표만 갱신. 매 프레임 처리해도
    충분히 가볍지만, 빈도를 줄이고 싶으면 night_blend==0일 때는 건너뛰면 됨."""
    cat = _load_star_catalog()
    alt, az, _ = obs.at(t).observe(cat["stars"]).apparent().altaz()
    x, y, z = altaz_to_world_dir(alt.degrees, az.degrees)
    radius = 480.0
    coords = np.stack([x, y, z], axis=1) * radius
    mesh = _state["star_mesh"]
    if len(mesh.vertices) != len(coords):
        mesh.clear_geometry()
        mesh.from_pydata([tuple(c) for c in coords], [], [])
        mesh.update()
        attr = mesh.attributes.new(name="mag", type='FLOAT', domain='POINT')
        attr.data.foreach_set("value", cat["mag"])
    else:
        mesh.vertices.foreach_set("co", coords.ravel())
        mesh.update_tag()

def apply_sky_state(w):
    sky, bg, sun, sl = _state["sky"], _state["bg"], _state["sun"], _state["sl"]
    t = sim_time(w)
    obs = observer_at(w)

    sun_alt, sun_az, _ = obs.at(t).observe(_SUN).apparent().altaz(
        temperature_C=10.0, pressure_mbar=1010.0)  # 대기굴절 포함 — 실제 보이는 일출/일몰 위치
    elevation_deg, azimuth_deg = sun_alt.degrees, sun_az.degrees

    sky.sun_rotation = math.radians(azimuth_deg)
    sky.sun_elevation = math.radians(max(-89.0, min(89.0, elevation_deg)))
    sun.rotation_euler[0] = math.radians(90.0 - elevation_deg)
    sun.rotation_euler[2] = math.radians(azimuth_deg)

    # daylight: 고도 -6°(시민박명 끝)~20° 사이를 선형으로 보간(일출/일몰 때
    # 색이 매끄럽게 바뀌게 함 — sin(elevation)을 바로 쓰면 고도가 0을 넘는
    # 순간 갑자기 튀는 문제가 있었음).
    daylight = max(0.0, min(1.0, (elevation_deg + 6.0) / 26.0))
    white, orange, moonlt = (1.0, 1.0, 1.0), (1.0, 0.60, 0.30), (0.65, 0.72, 0.95)
    warm = max(0.0, min(1.0, 1.0 - elevation_deg / 20.0))
    night_blend = max(0.0, min(1.0, -elevation_deg / 6.0))
    day_or_sunset_color = _lerp3(white, orange, warm)
    sun.data.color = _lerp3(day_or_sunset_color, moonlt, night_blend)
    sl.data.color = _lerp3((0.60, 0.72, 1.0), (0.55, 0.62, 0.85), night_blend)
    # 하늘 자체는 -6°(시민박명)~-18°(천문박명) 사이에서 고정 야간색으로 섞어줌.
    # 이보다 일찍(-6° 전) 섞기 시작하면 Nishita가 스스로 만드는, 아직 살아있는
    # 황혼 산란광(태양이 지평선 막 넘어가도 대기가 계속 빛을 산란시키는 실제
    # 현상)까지 덮어버려 박명이 비정상적으로 일찍 새까매짐 — 정작 Nishita가
    # 진짜 (0,0,0) 검정만 내는 더 깊은 구간에서만 대체하도록 늦춤.
    sky_night_blend = max(0.0, min(1.0, (-elevation_deg - 6.0) / 12.0))
    _state["sky_mix"].inputs[0].default_value = sky_night_blend

    # ── 달 — 실제 위치 + 실제 위상(skyfield) ──
    moon_alt, moon_az, _ = obs.at(t).observe(_MOON).apparent().altaz(
        temperature_C=10.0, pressure_mbar=1010.0)
    moon_alt_deg, moon_az_deg = moon_alt.degrees, moon_az.degrees
    phase_frac = almanac.fraction_illuminated(_eph, 'moon', t)
    moon_lamp, moon_disc = _state["moon_lamp"], _state["moon_disc"]
    moon_lamp.rotation_euler[0] = math.radians(90.0 - moon_alt_deg)
    moon_lamp.rotation_euler[2] = math.radians(moon_az_deg)
    mx, my, mz = altaz_to_world_dir(moon_alt_deg, moon_az_deg)
    moon_disc.location = (mx * MOON_DIST, my * MOON_DIST, mz * MOON_DIST)
    moon_disc.hide_viewport = moon_disc.hide_render = bool(moon_alt_deg < -2.0)
    # 달 표면 셰이더의 명/암 경계(자전축 그림자선)는 "태양이 비치는 실제 방향"의
    # 내적으로 결정 — 태양-지구 거리가 지구-달 거리의 ~400배라 태양광선이
    # 달에서도 거의 평행하다는(실제로 맞는) 근사로 달의 위상을 정확히 재현함.
    sx, sy, sz = altaz_to_world_dir(elevation_deg, azimuth_deg)
    sd = _state["moon_sundir_node"]
    sd.inputs[0].default_value, sd.inputs[1].default_value, sd.inputs[2].default_value = sx, sy, sz

    # ── 조도(lux) — 자연계 실제값. 화면에서 보이게 하려고 임의로 깎거나 부풀리지 않음 ──
    sun_lux = sun_illuminance_lux(elevation_deg)
    moon_lux = moon_illuminance_lux(moon_alt_deg, phase_frac)
    total_lux = sun_lux + moon_lux + STARLIGHT_FLOOR_LUX  # 별빛+대기광(에어글로우), 실재하는 양

    sun.data.energy = lux_to_watt(sun_lux)
    moon_lamp.data.energy = lux_to_watt(moon_lux)
    sl.data.energy = 90.0 * (total_lux / REF_LUX)
    # Background Strength는 Nishita 하늘 텍스처가 낮~황혼 동안 스스로 고도에
    # 따라 물리적 밝기를 내고 있는 출력의 배율이라 고정해 둠(여기서 total_lux로
    # 또 곱하면 이중 적용). 깊은 밤에 Nishita가 (0,0,0)이 되는 구간만 따로
    # night_sky_color 자체의 밝기를 total_lux에 맞춰 조절(아래)해 처리.
    bg_strength = 0.45
    if w.weather_type == 'OVERCAST':
        # 흐린 날: 구름이 직사광을 산란시켜 그림자 없는 균일한 디퓨즈광이 됨 —
        # Sun(직사) 비중을 깎고 Background(산란/디퓨즈)로 옮김.
        sun.data.energy *= 0.15
        bg_strength *= 3.0
    bg.inputs["Strength"].default_value = bg_strength
    # night_sky_color 자체는 고정값(build_scene에서 설정) — 달빛 유무 차이는
    # 여기서 또 만들지 않음. 이미 모자(moon_lamp.energy)가 달의 유무/위상에
    # 따라 다르고, 노출(exposure)도 total_lux를 따로 반영하므로, 여기서까지
    # total_lux로 다시 스케일하면 보정이 두 번 겹쳐 보름달 밤이 오히려 과다
    # 노출(하얗게 날아감)되는 문제가 있었음.

    # ── "인간 눈"의 인지적 노출/채도 — 위 물리값은 그대로 두고 보는 방식만 보정 ──
    bpy.context.scene.view_settings.exposure = eye_adapted_exposure_ev(total_lux)
    _state["comp_huesat"].inputs["Saturation"].default_value = scotopic_saturation(total_lux)

    # ── 별 — 황혼에 페이드인, 맑을수록/구름 없을수록 잘 보임 ──
    cloud_block = 0.6 if w.weather_type in ('OVERCAST', 'CUMULUS') else (0.25 if w.weather_type in ('RAIN', 'SNOW', 'CIRRUS') else 0.0)
    star_vis = max(0.0, night_blend - cloud_block)
    _state["star_visibility"].outputs[0].default_value = star_vis
    if star_vis > 0.001:
        update_star_field(w, t, obs)

    return night_blend

# =====================================================================
# 날씨 프리셋 — 구름 모양/고도/커버리지, 안개, 에어로졸
# =====================================================================
_CLOUD_PRESETS = {
    'CLEAR':    dict(visible=False, aerosol=1.2, mist=False),
    # z=34는 카메라 시야각(거의 수평) 밖이라 안 보였음 — 다른 프리셋과 같은
    # 시야 범위 안(z=22)으로 낮추고, 결대신 옅은 줄무늬 느낌은 noise scale/detail로 유지.
    # 그레이징 앵글(거의 수평) 카메라로 옅은 구름을 보면 광학적 경로가 길어져
    # 불투명도가 지수적으로 커짐 — density 0.15까지는 거의 안 보이다가 0.3
    # 근처에서 갑자기 보이는 임계치가 있었음(선형이 아님). 완전히 옅게는
    # 못 가져가고 0.3에서 "보이는 옅은 구름" 정도로 타협.
    'CIRRUS':   dict(visible=True, z=22.0, scale=2.2, detail=6.0, cov_lo=0.30, cov_hi=0.45, density=0.30, aerosol=1.6, mist=False),
    'CUMULUS':  dict(visible=True, z=18.0, scale=1.6, detail=3.0, cov_lo=0.40, cov_hi=0.58, density=0.16, aerosol=2.2, mist=False),
    'OVERCAST': dict(visible=True, z=14.0, scale=1.0, detail=2.0, cov_lo=0.10, cov_hi=0.95, density=0.35, aerosol=3.0, mist=True),
    'RAIN':     dict(visible=True, z=20.0, scale=2.5, detail=4.0, cov_lo=0.35, cov_hi=0.65, density=0.10, aerosol=5.5, mist=True),
    'SNOW':     dict(visible=True, z=20.0, scale=2.0, detail=3.5, cov_lo=0.30, cov_hi=0.70, density=0.14, aerosol=4.0, mist=True),
}

def apply_weather_preset(w):
    preset = _CLOUD_PRESETS[w.weather_type]
    cloud_obj = _state["cloud_obj"]
    cloud_obj.hide_viewport = cloud_obj.hide_render = not preset["visible"]
    if preset["visible"]:
        loc = cloud_obj.location
        cloud_obj.location = (loc.x, loc.y, preset["z"])
        _state["cloud_noise"].inputs["Scale"].default_value = preset["scale"]
        _state["cloud_noise"].inputs["Detail"].default_value = preset["detail"]
        _state["cloud_cov"].inputs["From Min"].default_value = preset["cov_lo"]
        _state["cloud_cov"].inputs["From Max"].default_value = preset["cov_hi"]
        _state["cloud_density_mul"].inputs[1].default_value = preset["density"]
    _state["sky"].aerosol_density = preset["aerosol"]
    mist_obj = _state["mist_obj"]
    mist_obj.hide_viewport = mist_obj.hide_render = not preset["mist"]

# =====================================================================
# 프레임/파라미터 갱신
# =====================================================================
# =====================================================================
# 사운드/뇌우 — 매 프레임 호출. 스트립을 미리 다 깔아두지 않고, 재생이
# 이미 깔아둔 구간 끝에 다다를 때마다 그때그때 다음 구간을 이어붙임
# (몇 시간짜리 재생도 스트립이 무한정 쌓이지 않음, 되감기/스크럽도 무난함).
# =====================================================================
def _update_ambient_sound(scene, w):
    se = _state["seq_editor"]
    frame = scene.frame_current

    if w.weather_type == 'RAIN' and _state.get("rain_loop_path"):
        if frame >= _state["rain_sound_until"]:
            # 버그였던 부분: 오디오 버퍼는 항상 "사이클 시간 0"부터 시작하도록
            # 합성되는데, 그걸 그냥 지금 프레임에 꽂으면 시각 쪽이 쓰는
            # 절대 시뮬레이션 시간(t) 기준 위상과 어긋남 — 빗방울이 화면에서
            # 땅에 닿기 전에 충돌음이 들리거나(또는 늦게 들리거나) 하는 원인.
            # 버퍼의 사이클 시간 0이 실제로 "현재 t를 CYCLE_SEC로 나눈 나머지가
            # 0이었던 과거 프레임"에 위치하도록 frame_start를 그만큼 과거로 밀어서
            # 꽂음 — 그래야 지금 프레임에서 버퍼가 재생 중인 위치가 시각 쪽의
            # local_t=(t+drop_phase)%CYCLE_SEC 와 정확히 같은 위상이 됨.
            t_now = (frame - 1) / FPS
            phase_frames = int(round((t_now % CYCLE_SEC) * FPS))
            frame_start = frame - phase_frames
            strip = se.strips.new_sound(f"WS_Rain_{frame}", _state["rain_loop_path"], 1, frame_start)
            _state["rain_strip_active"] = strip
            _state["rain_sound_until"] = frame_start + _state["rain_loop_frames"]
        active = _state.get("rain_strip_active")
        if active:
            active.volume = float(np.clip(w.rain_rate / 25.0, 0.2, 1.6))
    else:
        active = _state.get("rain_strip_active")
        if active:
            active.volume = 0.0  # 비가 아니면 즉시 무음(이미 깔린 구간은 그대로 두되 들리지 않게)

    wind_on = w.wind_enabled and w.wind_speed > 0.05
    if wind_on:
        if frame >= _state["wind_sound_until"]:
            strip = se.strips.new_sound(f"WS_Wind_{frame}", _state["wind_loop_path"], 2, frame)
            _state["wind_strip_active"] = strip
            _state["wind_sound_until"] = frame + _state["wind_loop_frames"]
        active = _state.get("wind_strip_active")
        if active:
            active.volume = float(np.clip(w.wind_speed / 5.0, 0.1, 1.2))
    else:
        active = _state.get("wind_strip_active")
        if active:
            active.volume = 0.0

    if w.weather_type == 'SNOW' and _state.get("snow_loop_path"):
        if frame >= _state["snow_sound_until"]:
            strip = se.strips.new_sound(f"WS_Snow_{frame}", _state["snow_loop_path"], 4, frame)
            _state["snow_strip_active"] = strip
            _state["snow_sound_until"] = frame + _state["snow_loop_frames"]
        active = _state.get("snow_strip_active")
        if active:
            # 눈은 실제로 비보다 훨씬 조용함 — 적설 강도(rain_rate 슬라이더 재사용)와
            # 바람(날리는 눈이 부딫는 소리가 커짐)에 따라 작게만 변함.
            density = np.clip(w.rain_rate / 30.0, 0.2, 1.0)
            wind_boost = 1.0 + np.clip(w.wind_speed / 8.0, 0.0, 1.0) if (w.wind_enabled) else 1.0
            active.volume = float(np.clip(0.10 * density * wind_boost, 0.03, 0.35))
    else:
        active = _state.get("snow_strip_active")
        if active:
            active.volume = 0.0

def _maybe_trigger_thunder(scene, w):
    """비가 올 때만 — 강우강도가 셀수록 평균 발생 간격이 짧아짐. 번개(빛)는
    치는 즉시 보이지만 천둥(소리)은 실제 음속(343m/s)에 맞춰 임의의 거리만큼
    지연시킴 — 거리가 멀수록 소리는 더 늦고, 더 작고, 고주파가 깎인 둔한
    소리(distance_factor)가 됨.

    버그였던 부분: 되감기/스크럽이나 애니메이션 루프(frame_end=9999에서
    frame_start=1로 복귀)로 frame이 거꾸로 가버리면, 이미 잡혀있던
    pending_thunder의 trigger_frame을 영원히 못 만나 그 천둥이 영구히 묵음
    처리되고 그 뒤로 새 천둥도 전혀 안 치는(pending이 안 비워지므로) 상태가
    됨 — 번개(빛)는 치는 즉시 보였지만 그 소리는 그렇게 누락된 것."""
    frame = scene.frame_current
    last_frame = _state.get("_thunder_last_frame", frame)
    looped_back = frame < last_frame - 5
    _state["_thunder_last_frame"] = frame

    if w.weather_type != 'RAIN':
        _state["pending_thunder"] = None
        return

    pending = _state.get("pending_thunder")
    if pending is not None:
        trigger_frame, clip_path, volume = pending
        if looped_back:
            _state["pending_thunder"] = None  # 묵음으로 영구 박힌 보류 해제 -> 다음 천둥 다시 가능
        elif frame >= trigger_frame:
            se = _state["seq_editor"]
            strip = se.strips.new_sound(f"WS_Thunder_{frame}", clip_path, 3, frame)
            strip.volume = volume
            _state["pending_thunder"] = None
            return
        else:
            return

    # 실제로 뇌우는 약한 이슬비에선 거의 안 치고 강수강도가 어느 수준(대략
    # 소나기~호우 수준) 이상일 때 활발해짐 — 강우강도에 선형이 아니라 약한
    # 비에서는 거의 0, 강해질수록 빠르게 늘어나는 문턱 곡선(제곱)을 씀.
    THUNDER_THRESHOLD = 12.0  # mm/hr 이하에서는 사실상 안 침
    if w.rain_rate <= THUNDER_THRESHOLD:
        return
    intensity = (w.rain_rate - THUNDER_THRESHOLD) / (60.0 - THUNDER_THRESHOLD)  # 0~1
    avg_interval_sec = max(4.0, 70.0 - 65.0 * (intensity ** 2))
    p_per_frame = (1.0 / FPS) / avg_interval_sec
    if _thunder_rng.random() >= p_per_frame:
        return
    # 거리 상한을 12km->6km로 줄임: 멀리 칠수록 지연이 35초까지 길어져
    # 실제로 들릴 때까지 기다리는 사용자가 거의 없었고(체감상 "천둥소리가
    # 없다"), frame_end(9999) 끝부분에서 걸리면 위 루프백 버그에 더 잘
    # 걸렸음. 6km(최대 ~17.5초 지연)면 여전히 "멀리서 우르릉"이 느껴지되
    # 실제로 기다려서 들을 수 있는 범위.
    distance_km = float(_thunder_rng.uniform(0.3, 6.0))
    distance_factor = float(np.clip(distance_km / 6.0, 0.0, 1.0))
    sound_delay_sec = distance_km * 1000.0 / 343.0
    trigger_frame = frame + int(round(sound_delay_sec * FPS))
    seed = int(_thunder_rng.integers(0, 1_000_000))
    clip_path = os.path.join(_SOUND_DIR, f"thunder_{seed}.wav")
    _synthesize_thunder(clip_path, seed, distance_factor)
    volume = float(np.clip(1.4 - distance_factor * 1.1, 0.15, 1.3))
    _state["pending_thunder"] = (trigger_frame, clip_path, volume)
    _state["lightning_flash_remaining"] = 2  # 번개는 지금 즉시(빛은 거의 즉시 도달)

LIGHTNING_FLASH_STRENGTH = 14.0  # 절대값으로 고정 — 현재 밝기에 곱하지 않음
                                  # (흐림 등으로 배경이 이미 밝아진 상태와 겹쳐
                                  # 곱해지면 과도하게 밝아질 수 있어 안전하게 고정값으로)

def _apply_lightning_flash():
    remaining = _state.get("lightning_flash_remaining", 0)
    if remaining <= 0:
        return
    # 0이하나 비정상적으로 큰 값이 들어와도(버그로 카운터가 안 줄어드는 등)
    # 화면이 계속 하얗게 멈춰있지 않도록 절대 상한을 둠.
    remaining = min(remaining, 2)
    bg = _state["bg"]
    bg.inputs["Strength"].default_value = LIGHTNING_FLASH_STRENGTH
    _state["lightning_flash_remaining"] = remaining - 1

def update_scene(scene):
    global ground_wetness_level, ground_snow_level
    w = scene.ws_weather
    wind_speed = w.wind_speed if w.wind_enabled else 0.0
    weather = w.weather_type
    is_rain = weather == 'RAIN'
    is_snow = weather == 'SNOW'
    precip_on = is_rain or is_snow

    t = (scene.frame_current - 1) / FPS

    rain_obj, splash_obj = _state["rain_obj"], _state["splash_obj"]
    rain_obj.hide_viewport = rain_obj.hide_render = not precip_on
    splash_obj.hide_viewport = splash_obj.hide_render = not is_rain  # 눈은 스플래시 없음
    # 비/눈은 같은 커브 오브젝트를 재사용 — 재질과 베벨 반경(얇은 빗줄 vs
    # 둥근 눈송이)만 날씨에 맞게 교체.
    rain_obj.data.materials[0] = _state["snow_mat"] if is_snow else _state["rain_mat"]
    rain_obj.data.bevel_depth = 0.012 if is_snow else 0.004

    apply_weather_preset(w)

    hits_per_puddle = np.zeros(len(_state["puddle_objs"]))

    if is_rain:
        local_t = (t + drop_phase) % CYCLE_SEC
        falling = local_t < fall_dur
        t_eff = np.where(falling, local_t, fall_dur)
        fallen = fall_distance(t_eff, v_terminal)
        drift = lateral_drift(t_eff, v_terminal, wind_speed)
        z = np.where(falling, START_HEIGHT - fallen, ground_z)
        x = x0 + drift * WIND_DX
        y = y0 + drift * WIND_DY
        speed = np.where(falling, fall_velocity(t_eff, v_terminal), 0.0)
        tau = v_terminal / G
        wind_now = np.where(falling, wind_speed * (1.0 - np.exp(-t_eff / tau)), 0.0)
        vx, vy, vz = wind_now * WIND_DX, wind_now * WIND_DY, speed
        vmag = np.sqrt(vx ** 2 + vy ** 2 + vz ** 2)
        vmag_safe = np.where(vmag < 1e-6, 1.0, vmag)
        vis_len = np.clip(STREAK_LEN * (vmag / 4.0), STREAK_LEN * 0.3, STREAK_LEN * 2.0)
        tail_x = x - (vx / vmag_safe) * vis_len
        tail_y = y - (vy / vmag_safe) * vis_len
        tail_z = z + (vz / vmag_safe) * vis_len

        rain_splines = rain_obj.data.splines
        nr = min(n_rain, len(rain_splines))
        for i in range(nr):
            if falling[i] and rain_active_mask[i]:
                rain_splines[i].points[0].co = (x[i], y[i], z[i], 1.0)
                rain_splines[i].points[1].co = (tail_x[i], tail_y[i], tail_z[i], 1.0)
                rain_splines[i].points[0].radius = float(rain_size_scale[i])
                rain_splines[i].points[1].radius = float(rain_size_scale[i])
            else:
                rain_splines[i].points[0].co = (0, 0, -100.0, 1.0)
                rain_splines[i].points[1].co = (0, 0, -100.0, 1.0)
        rain_obj.data.update_tag()

        since_landing = local_t - fall_dur
        splashing = (since_landing >= 0) & (since_landing < SPLASH_WINDOW) & rain_active_mask
        near = np.stack([x[splashing], y[splashing], z[splashing]], axis=1)
        near_speed = v_terminal[splashing]
        if len(near) > SPLASH_MAX:
            sel = np.random.choice(len(near), SPLASH_MAX, replace=False)
            near, near_speed = near[sel], near_speed[sel]
        radii = np.clip(0.3 + near_speed * 0.12, 0.3, 1.3)
        gz = ground_height_vec(near[:, 0], near[:, 1]) if len(near) else np.zeros(0)

        n_pud = len(_state["puddle_objs"])
        pc, pmr = _state["puddle_centers"], _state["puddle_max_r"]
        if n_pud > 0 and len(near) > 0:
            dx = near[:, 0:1] - pc[:, 0][None, :]
            dy = near[:, 1:2] - pc[:, 1][None, :]
            dist2 = dx ** 2 + dy ** 2
            inside_catchment = dist2 < (pmr[None, :] ** 2)
            hits_per_puddle = inside_catchment.sum(axis=0)
            cur_r = pmr * _state["puddle_wetness"]
            inside_current = dist2 < (cur_r[None, :] ** 2)
            in_any_puddle = inside_current.any(axis=1)
            radii[in_any_puddle] *= RIPPLE_BOOST

        verts = splash_obj.data.vertices
        ns = min(SPLASH_MAX, len(verts) // N_SIDES)
        n_active = len(near)
        for i in range(ns):
            base = i * N_SIDES
            if i < n_active:
                px, py = near[i, 0], near[i, 1]
                r = radii[i]
                pz = gz[i] + 0.02
                for k in range(N_SIDES):
                    ang = 2 * math.pi * k / N_SIDES
                    verts[base + k].co = (px + math.cos(ang) * r, py + math.sin(ang) * r, pz)
            else:
                for k in range(N_SIDES):
                    verts[base + k].co = (0, 0, -100.0)
        splash_obj.data.update_tag()

        ground_wetness_level = min(1.0, ground_wetness_level + WETNESS_GROWTH_PER_SEC / FPS)
        ground_snow_level = max(0.0, ground_snow_level - SNOW_DECAY_PER_SEC / FPS)
    elif is_snow:
        local_t = (t + snow_drop_phase) % SNOW_CYCLE_SEC
        falling = local_t < snow_fall_dur
        t_eff = np.where(falling, local_t, snow_fall_dur)
        z = np.where(falling, START_HEIGHT - SNOW_FALL_SPEED * t_eff, ground_z)
        # 가볍고 항력이 큰 눈은 일정한 종단속도로 떨어지되, 좌우로 흔들리며
        # 내림(flutter) + 바람에 더 잘 밀림(질량 대비 항력이 커서) — 빗방울과
        # 다른, 실제 눈 특유의 낙하 방식.
        flutter_x = SNOW_SWIRL_AMP * np.sin(2 * np.pi * snow_flutter_freq * t_eff + snow_flutter_phase)
        flutter_y = SNOW_SWIRL_AMP * np.cos(2 * np.pi * snow_flutter_freq * t_eff * 0.7 + snow_flutter_phase)
        drift_amount = wind_speed * t_eff * 0.6
        x = np.where(falling, x0 + drift_amount * WIND_DX + flutter_x, x0)
        y = np.where(falling, y0 + drift_amount * WIND_DY + flutter_y, y0)

        frac_active = max(0.1, min(1.0, w.rain_rate / 30.0))
        n_active_snow = max(1, int(round(n_rain * frac_active)))
        # 이전엔 i < n_active_snow로 골랐는데, 인덱스 순서가 곧 격자상 x좌표
        # 순서라(build_scene의 ravel 순서) 강도를 낮추면 한쪽으로 쏠려 보이는
        # 공간 편향이 있었음 — 고정 셔플 순서(_activation_order)로 골라
        # 항상 화면 전체에 고르게 분포하도록 수정.
        snow_active_mask = np.zeros(n_rain, dtype=bool)
        snow_active_mask[_activation_order[:n_active_snow]] = True

        rain_splines = rain_obj.data.splines
        nr = min(n_rain, len(rain_splines))
        for i in range(nr):
            if falling[i] and snow_active_mask[i]:
                rain_splines[i].points[0].co = (x[i], y[i], z[i], 1.0)
                rain_splines[i].points[1].co = (x[i], y[i], z[i] - 0.04, 1.0)
                rain_splines[i].points[0].radius = float(snow_size_scale[i])
                rain_splines[i].points[1].radius = float(snow_size_scale[i])
            else:
                rain_splines[i].points[0].co = (0, 0, -100.0, 1.0)
                rain_splines[i].points[1].co = (0, 0, -100.0, 1.0)
        rain_obj.data.update_tag()

        ground_snow_level = min(1.0, ground_snow_level + SNOW_GROWTH_PER_SEC / FPS)
        ground_wetness_level = max(0.0, ground_wetness_level - WETNESS_DECAY_PER_SEC / FPS)
    else:
        ground_wetness_level = max(0.0, ground_wetness_level - WETNESS_DECAY_PER_SEC / FPS)
        ground_snow_level = max(0.0, ground_snow_level - SNOW_DECAY_PER_SEC / FPS)

    pw = _state["puddle_wetness"]
    decay_rate = PUDDLE_DECAY if is_rain else PUDDLE_DECAY_OFF
    for pi in range(len(_state["puddle_objs"])):
        if hits_per_puddle[pi] > 0:
            pw[pi] = min(1.0, pw[pi] + PUDDLE_GROWTH * hits_per_puddle[pi])
        else:
            pw[pi] = max(0.0, pw[pi] - decay_rate)
        s = max(0.001, pw[pi]) * _state["puddle_max_r"][pi]
        _state["puddle_objs"][pi].scale = (s, s, 1.0)

    _state["ground_wetness_value"].outputs[0].default_value = ground_wetness_level
    _state["ground_snow_value"].outputs[0].default_value = ground_snow_level
    snow_white = (0.85, 0.87, 0.90)
    for mat, dry_r, is_leaf, base_color in _tree_mats:
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = dry_r - ground_wetness_level * (dry_r - 0.25)
        if is_leaf:
            f = ground_snow_level
            bsdf.inputs["Base Color"].default_value = (
                base_color[0] * (1 - f) + snow_white[0] * f,
                base_color[1] * (1 - f) + snow_white[1] * f,
                base_color[2] * (1 - f) + snow_white[2] * f, 1.0)

    cloud_drift = CLOUD_DRIFT_AMP * math.sin(2 * math.pi * t / max(CYCLE_SEC, 1.0))
    _state["cloud_mapping"].inputs["Location"].default_value = (
        cloud_drift * WIND_DX, cloud_drift * WIND_DY, 0.0)

    for pivot, n_cycles, amp, phase in _tree_sway:
        wind_factor = min(1.0, wind_speed / 1.6)
        angle = amp * wind_factor * math.sin(2 * math.pi * n_cycles * t / max(CYCLE_SEC, 1.0) + phase)
        pivot.rotation_euler[0] = -angle * WIND_DY
        pivot.rotation_euler[1] = angle * WIND_DX

    # 사운드/뇌우 쪽에서 예외가 나도(스크럽/되감기 등 예기치 못한 상태 조합)
    # 조명 갱신(apply_sky_state)이 막혀서 화면이 그 순간 밝기로 멈춰버리는
    # 일이 없도록 분리 — 한쪽이 깨져도 조명은 항상 매 프레임 다시 계산됨.
    try:
        _update_ambient_sound(scene, w)
        _maybe_trigger_thunder(scene, w)
    except Exception as e:
        print("WS Weather: 사운드/뇌우 갱신 중 오류(무시하고 계속):", repr(e))

    try:
        apply_sky_state(w)
    except Exception as e:
        print("WS Weather: 하늘/조명 갱신 중 오류(이전 프레임 상태 유지):", repr(e))

    try:
        _apply_lightning_flash()
    except Exception as e:
        print("WS Weather: 번개 플래시 적용 중 오류(무시하고 계속):", repr(e))

def refresh(scene):
    update_scene(scene)
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                area.tag_redraw()

# =====================================================================
# UI: PropertyGroup + Panel
# =====================================================================
def _on_rain_rate_change(self, context):
    regenerate_rain_distribution(self.rain_rate)
    regenerate_snow_distribution(self.rain_rate)  # 같은 슬라이더를 적설 강도로도 재사용
    refresh(context.scene)

def _on_other_change(self, context):
    refresh(context.scene)

_WEATHER_ITEMS = [
    ('CLEAR', "맑음", "구름 없음"),
    ('CIRRUS', "시러스(높은 옅은 구름)", "고도 높은 옅은 구름, 일광 대부분 통과"),
    ('CUMULUS', "큐뮬러스(뭉친 구름)", "낮은 고도의 뭉친 구름, 부분 일광"),
    ('OVERCAST', "흐림", "전체 흐림, 직사광 대부분이 디퓨즈광으로 산란"),
    ('RAIN', "비", "비구름 + 비/스플래시/웅덩이"),
    ('SNOW', "눈", "눈구름 + 눈송이, 지면/나뭇잎이 점점 흰색으로"),
]

class WS_WeatherProps(bpy.types.PropertyGroup):
    weather_type: bpy.props.EnumProperty(
        name="날씨", items=_WEATHER_ITEMS, default='RAIN', update=_on_other_change)
    rain_rate: bpy.props.FloatProperty(
        name="강수강도 (mm/hr)", default=20.0, min=0.5, max=60.0, update=_on_rain_rate_change)
    wind_enabled: bpy.props.BoolProperty(name="바람", default=True, update=_on_other_change)
    wind_speed: bpy.props.FloatProperty(
        name="바람 속도 (m/s)", default=1.6, min=0.0, max=12.0, update=_on_other_change)
    time_of_day: bpy.props.FloatProperty(
        name="시간 (시, 현지시각)", default=12.0, min=0.0, max=24.0, update=_on_other_change)
    latitude: bpy.props.FloatProperty(
        name="위도", default=37.5665, min=-90.0, max=90.0, update=_on_other_change)
    longitude: bpy.props.FloatProperty(
        name="경도", default=126.9780, min=-180.0, max=180.0, update=_on_other_change)
    utc_offset: bpy.props.FloatProperty(
        name="UTC 오프셋 (시)", default=9.0, min=-12.0, max=14.0, update=_on_other_change,
        description="위도/경도로부터 자동 추론하지 않음 — 타임존에 맞게 직접 입력(서울=+9)")
    sim_year: bpy.props.IntProperty(name="연도", default=2026, min=1900, max=2100, update=_on_other_change)
    sim_month: bpy.props.IntProperty(name="월", default=6, min=1, max=12, update=_on_other_change)
    sim_day: bpy.props.IntProperty(name="일", default=21, min=1, max=31, update=_on_other_change)
    real_time_mode: bpy.props.BoolProperty(
        name="재생으로 시간 자동 진행", default=False, update=_on_other_change,
        description="켜면 위 시간 슬라이더는 '재생 시작 시각'이 되고, 애니메이션을 재생하는"
                    " 동안 day_length_sec당 24시간씩 실제로 흘러감(날짜 경계도 자연스럽게 넘어감)")
    day_length_sec: bpy.props.FloatProperty(
        name="하루 길이 (실제 재생 초)", default=120.0, min=5.0, max=3600.0, update=_on_other_change,
        description="실시간 자동 진행 모드에서, 24시간이 지나가는 데 걸리는 실제 재생 시간(초)")

class WS_OT_CleanFullscreen(bpy.types.Operator):
    """뷰포트를 화면 전체로 키우고 격자/기즈모/오버레이를 다 꺼서, 블렌더
    편집기 같은 느낌 없이 깔끔한 실시간 렌더 화면만 보이게 함(다시 누르면
    원래대로 — 같은 단축키: Ctrl+Space는 최대화만, 오버레이/기즈모는 별도)."""
    bl_idname = "ws.clean_fullscreen"
    bl_label = "깨끗한 전체화면으로 보기 (다시 누르면 복구)"

    def execute(self, context):
        space = context.space_data
        if space.type != 'VIEW_3D':
            self.report({'WARNING'}, "3D 뷰포트 안에서 눌러주세요")
            return {'CANCELLED'}
        going_clean = space.overlay.show_overlays  # 지금 켜져 있으면 -> 끄는 방향
        space.overlay.show_overlays = not going_clean
        space.show_gizmo = not going_clean
        space.shading.type = 'RENDERED'
        bpy.ops.screen.screen_full_area(use_hide_panels=True)  # 토글 — 다시 누르면 원래 레이아웃으로 복귀
        return {'FINISHED'}

class WS_OT_FlyCamera(bpy.types.Operator):
    """씬 카메라를 3D 뷰에 '잠가서'(Lock Camera to View) 블렌더 내장 걷기
    내비게이션(Walk Navigation)을 그대로 카메라에 입력함 — 직접 모달 입력을
    새로 구현하지 않고 블렌더가 이미 검증한 충돌 없는 WASD+마우스 컨트롤을
    재사용하는 방식.
    조작: W/A/S/D 이동, 마우스 시선, Space/Ctrl(또는 R/F) 위/아래,
    Shift 빠르게, 좌클릭/Enter 확정, 우클릭/Esc 취소(시작 위치로 복귀)."""
    bl_idname = "ws.fly_camera"
    bl_label = "플라이 카메라 시작 (WASD + 마우스)"

    def execute(self, context):
        scene = context.scene
        cam = scene.camera
        if cam is None:
            self.report({'WARNING'}, "씬에 카메라가 없습니다")
            return {'CANCELLED'}
        area = next((a for a in context.window.screen.areas if a.type == 'VIEW_3D'), None)
        if area is None:
            self.report({'WARNING'}, "3D 뷰포트를 찾을 수 없습니다")
            return {'CANCELLED'}
        region = next((r for r in area.regions if r.type == 'WINDOW'), None)
        if region is None:
            self.report({'WARNING'}, "3D 뷰포트의 WINDOW 영역을 찾을 수 없습니다")
            return {'CANCELLED'}
        space = next(s for s in area.spaces if s.type == 'VIEW_3D')
        space.region_3d.view_perspective = 'CAMERA'
        space.lock_camera = True  # 뷰를 움직이면 카메라 오브젝트 자체가 따라 움직임
        with context.temp_override(area=area, region=region):
            bpy.ops.view3d.walk('INVOKE_DEFAULT')
        return {'FINISHED'}

class WS_PT_WeatherPanel(bpy.types.Panel):
    bl_label = "WS Weather"
    bl_idname = "WS_PT_weather_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "WS Weather"

    def draw(self, context):
        w = context.scene.ws_weather
        col = self.layout.column()
        col.prop(w, "weather_type")
        col.prop(w, "rain_rate")
        col.separator()
        col.prop(w, "wind_enabled")
        col.prop(w, "wind_speed")
        col.separator()
        col.label(text="위치(위도/경도) · 날짜/시각")
        col.prop(w, "latitude")
        col.prop(w, "longitude")
        col.prop(w, "utc_offset")
        row = col.row(align=True)
        row.prop(w, "sim_year")
        row.prop(w, "sim_month")
        row.prop(w, "sim_day")
        col.prop(w, "time_of_day", text="시간(현지시각, 재생 시작점)" if w.real_time_mode else "시간(현지시각)")
        col.separator()
        col.prop(w, "real_time_mode")
        if w.real_time_mode:
            col.prop(w, "day_length_sec")
            col.label(text=f"재생 중 시점: {effective_local_time_str(w)}")
            col.label(text="스페이스바로 재생하면 하루가 실제로 흘러갑니다.")
        col.separator()
        col.operator("ws.clean_fullscreen", icon='FULLSCREEN_ENTER')
        col.operator("ws.fly_camera", icon='VIEW_CAMERA')
        col.label(text="이동 W/A/S/D · 시선 마우스 · 위/아래 Space/Ctrl")
        col.label(text="좌클릭/Enter 확정 · 우클릭/Esc 취소")

_classes = (WS_WeatherProps, WS_OT_CleanFullscreen, WS_OT_FlyCamera, WS_PT_WeatherPanel)

def register():
    for c in _classes:
        bpy.utils.register_class(c)
    bpy.types.Scene.ws_weather = bpy.props.PointerProperty(type=WS_WeatherProps)

def unregister():
    del bpy.types.Scene.ws_weather
    for c in reversed(_classes):
        bpy.utils.unregister_class(c)

# =====================================================================
# 실행
# =====================================================================
for c in _classes:
    try:
        bpy.utils.unregister_class(c)
    except Exception:
        pass
try:
    del bpy.types.Scene.ws_weather
except Exception:
    pass
register()

build_scene()
regenerate_rain_distribution(20.0)
regenerate_snow_distribution(20.0)

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 9999
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.use_raytracing = True
scene.view_settings.view_transform = 'AgX'

if bpy.context.screen:   # --background 모드(화면 없음)에서도 안전하게 동작
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.shading.type = 'RENDERED'

bpy.app.handlers.frame_change_post.clear()
bpy.app.handlers.frame_change_post.append(update_scene)
refresh(scene)

print("=" * 60)
print("WS Weather 실시간 도구 준비 완료.")
print("3D 뷰포트에서 'N' 키 -> 오른쪽 'WS Weather' 탭에서 조절.")
print("=" * 60)
