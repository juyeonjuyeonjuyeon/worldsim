"""
WS_forest_rain v015 사운드 합성 (물리 기반, bpy/Genesis 불필요).

원리: rain_geometry_export.py가 저장한 빗방울별 실제 물리량(직경, 종단속도,
낙하시간, 낙하 위치)을 그대로 재사용 — 시각 렌더링을 만든 것과 동일한
물리 데이터이므로 "보이는 비"와 "들리는 비"가 같은 강우강도/방울 분포에서
나온 것임.

두 가지 충돌음:
1. 웅덩이 충돌 -> 미네르트(Minnaert) 기포 공명: 물에 빠지는 물체가 가두는
   공기 기포가 단순조화진동자처럼 울리는 실제 물리(f0 = (1/2πr)√(3γP/ρ)).
   기포 반경은 방울 지름에 비례한다고 알려진 비율(~10%, 연구마다 다소
   차이가 있어 근사)을 사용. 큰 방울일수록 낮은 "퐁", 작은 방울일수록
   높은(거의 안 들리는) 음.
2. 마른 지면 충돌 -> 액체-기체 공명이 생기지 않으므로 톤 없는 광대역
   충격음(임펄스+빠른 감쇠), 운동에너지(0.5*m*v^2)에 비례한 크기.

방울이 웅덩이/마른땅 중 어디 떨어지는지는 시각 렌더와 동일한 웅덩이
중심/반경 데이터를 그대로 사용해 판정 — 임의로 비율을 정한 게 아니라
실제 웅덩이 배치와 일치시킴.
"""
import numpy as np
import wave
import struct

data = np.load(r"C:\Users\kkjjy\Documents\WorldSim\output\rain_sound_data.npz")
x0, y0 = data["x0"], data["y0"]
diam_mm, v_terminal = data["diam_mm"], data["v_terminal"]
fall_dur, drop_phase = data["fall_dur"], data["drop_phase"]
CYCLE_SEC, FPS = float(data["CYCLE_SEC"]), float(data["FPS"])
puddle_px, puddle_py, puddle_r = data["puddle_px"], data["puddle_py"], data["puddle_r"]

G = 9.81
SR = 44100
FIELD_HALF = 15.0
RHO_WATER = 1000.0

n_rain = len(x0)
v_impact = v_terminal * np.tanh(G * fall_dur / v_terminal)   # 실제 충돌 속도 (해석해)
impact_time = (fall_dur - drop_phase) % CYCLE_SEC             # 주기 내 충돌 시각

# 웅덩이 판정 (시각 렌더와 동일 위치/반경 데이터 사용)
if len(puddle_px) > 0:
    dists = np.sqrt((x0[:, None] - puddle_px[None, :]) ** 2 +
                     (y0[:, None] - puddle_py[None, :]) ** 2)
    is_puddle = (dists <= puddle_r[None, :]).any(axis=1)
else:
    is_puddle = np.zeros(n_rain, dtype=bool)

n_samples = int(round(CYCLE_SEC * SR))
buf_l = np.zeros(n_samples)
buf_r = np.zeros(n_samples)

rng = np.random.default_rng(7)

n_puddle_hits = int(is_puddle.sum())
print(f"방울 {n_rain}개 | 웅덩이 충돌 {n_puddle_hits}개 | 마른땅 충돌 {n_rain - n_puddle_hits}개")

for i in range(n_rain):
    D_m = diam_mm[i] / 1000.0
    v = v_impact[i]
    mass = (4.0 / 3.0) * np.pi * (D_m / 2.0) ** 3 * RHO_WATER
    KE = 0.5 * mass * v ** 2

    if is_puddle[i]:
        # 미네르트 기포 공명: f0[Hz] = 3.285 / r[m] (물속 공기 기포, 표준 근사)
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

peak = max(np.abs(buf_l).max(), np.abs(buf_r).max(), 1e-9)
target = 0.85
buf_l = buf_l / peak * target
buf_r = buf_r / peak * target

stereo = np.empty((n_samples, 2), dtype=np.float32)
stereo[:, 0] = buf_l
stereo[:, 1] = buf_r
pcm = (stereo * 32767.0).astype(np.int16)

out_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v015_sound.wav"
with wave.open(out_path, 'wb') as wf:
    wf.setnchannels(2)
    wf.setsampwidth(2)
    wf.setframerate(SR)
    wf.writeframes(pcm.tobytes())

print(f"저장 완료: {out_path} ({CYCLE_SEC:.2f}s, {SR}Hz, stereo)")
