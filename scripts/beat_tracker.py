"""Global beat tracking: spectral flux -> tempo -> dynamic programming.

The proposal specifies beat timestamps coming from a DP pass rather than a
fixed grid search. This module follows Ellis (2007): an autocorrelation tempo
estimate sets the target period, and dynamic programming then chooses the
beat sequence that maximises onset strength minus a tightness penalty for
deviating from that period.

A grid search can only ever snap a rigid lattice; the DP is allowed to follow
local tempo drift, which is what keeps late-song beats aligned with the audio.
"""
from __future__ import annotations

import numpy as np
from scipy import signal

EPS = 1e-9


def estimate_tempo(onset: np.ndarray, hop: float, bpm_min: float, bpm_max: float,
                   prior_bpm: float = 120.0, prior_width: float = 35.0) -> float:
    """Autocorrelation tempo with a Gaussian prior around ``prior_bpm``."""
    centred = onset - onset.mean()
    autocorr = signal.correlate(centred, centred, mode="full", method="fft")[centred.size - 1:]
    if autocorr.size < 3 or float(autocorr[0]) <= EPS:
        return prior_bpm

    lag_min = max(1, int(round(60.0 / bpm_max / hop)))
    lag_max = min(autocorr.size - 1, int(round(60.0 / bpm_min / hop)))
    if lag_max <= lag_min:
        return prior_bpm

    lags = np.arange(lag_min, lag_max + 1)
    bpms = 60.0 / (lags * hop)
    prior = np.exp(-0.5 * ((bpms - prior_bpm) / prior_width) ** 2)
    best = int(np.argmax(autocorr[lags] * prior))
    return float(bpms[best])


def track_beats(onset: np.ndarray, hop: float, bpm_min: float, bpm_max: float,
                tightness: float = 100.0, prior_bpm: float = 120.0) -> tuple[float, np.ndarray]:
    """Return (bpm, beat frame indices) from the DP beat tracker."""
    count = onset.size
    if count < 8:
        return prior_bpm, np.zeros(0, dtype=int)

    bpm = estimate_tempo(onset, hop, bpm_min, bpm_max, prior_bpm=prior_bpm)
    period = 60.0 / bpm / hop                      # frames per beat
    if not np.isfinite(period) or period < 2.0:
        return bpm, np.zeros(0, dtype=int)

    # Search one half to two beat periods on either side of the target.
    lag_min = max(1, int(round(period * 0.5)))
    lag_max = max(lag_min + 1, int(round(period * 2.0)))
    lag_max = min(lag_max, count - 1)
    if lag_max <= lag_min:
        return bpm, np.zeros(0, dtype=int)

    lags = np.arange(lag_min, lag_max + 1)
    penalty = tightness * (np.log2(lags / period) ** 2)

    cumulative = np.zeros(count, dtype=np.float64)
    backlink = np.full(count, -1, dtype=int)
    for frame in range(count):
        candidates = frame - lags
        valid = candidates >= 0
        if not np.any(valid):
            cumulative[frame] = onset[frame]
            continue
        scores = cumulative[candidates[valid]] - penalty[valid]
        best = int(np.argmax(scores))
        cumulative[frame] = onset[frame] + scores[best]
        backlink[frame] = int(candidates[valid][best])

    # Start from the best cumulative score in the final beat period.
    tail_start = max(0, count - int(round(period)) - 1)
    frame = tail_start + int(np.argmax(cumulative[tail_start:]))

    beats: list[int] = []
    while frame >= 0:
        beats.append(frame)
        frame = backlink[frame]
    beats.reverse()

    return bpm, np.asarray(beats, dtype=int)


def find_downbeats(beats: np.ndarray, low_band: np.ndarray,
                   onset: np.ndarray, times: np.ndarray) -> np.ndarray:
    """Pick the bar phase whose beats carry the most low-band weight."""
    if beats.size < 4:
        return beats.copy()

    low = np.interp(times[beats], times, low_band)
    novelty = np.interp(times[beats], times, onset)

    best_phase, best_score = 0, -1.0
    for phase in range(4):
        chosen = np.arange(phase, beats.size, 4)
        if chosen.size == 0:
            continue
        score = float(low[chosen].sum() + 0.5 * novelty[chosen].sum())
        if score > best_score:
            best_phase, best_score = phase, score

    return beats[best_phase::4]


def beats_to_times(beats: np.ndarray, times: np.ndarray) -> np.ndarray:
    if beats.size == 0:
        return np.zeros(0)
    return times[np.clip(beats, 0, times.size - 1)]
