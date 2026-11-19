"""Timbre grouping and per-group onset detection.

Implements the proposal's middle section:

  1. standardised descriptors  ->  diagonal GMM soft grouping
  2. short centred Gaussian  ->  smoothed group probabilities q_g(t)
  3. o_g(t) = q_g(t) * SF(t) with SF the positive spectral flux
  4. per-group normalisation, adaptive peak picking, minimum onset spacing

Everything is unsupervised and deterministic for a given seed; no model is
downloaded and no training set is required.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import ndimage, signal

EPS = 1e-9


@dataclass
class GroupModel:
    weights: np.ndarray        # (K,)
    means: np.ndarray          # (K, D)
    variances: np.ndarray      # (K, D)
    responsibilities: np.ndarray   # (T, K) soft assignment q_g(t)
    log_likelihood: float
    iterations: int

    @property
    def count(self) -> int:
        return int(self.weights.size)

    def labels(self) -> np.ndarray:
        return np.argmax(self.responsibilities, axis=1)

    def confidence(self) -> np.ndarray:
        return self.responsibilities.max(axis=1)


def _kmeans_pp(x: np.ndarray, k: int, rng: np.random.Generator) -> np.ndarray:
    """k-means++ seeding; returns initial centres."""
    count = x.shape[0]
    centres = np.empty((k, x.shape[1]), dtype=x.dtype)
    centres[0] = x[rng.integers(count)]
    closest = np.sum((x - centres[0]) ** 2, axis=1)
    for index in range(1, k):
        total = float(closest.sum())
        if total <= EPS:
            centres[index] = x[rng.integers(count)]
        else:
            probabilities = closest / total
            centres[index] = x[rng.choice(count, p=probabilities)]
        distance = np.sum((x - centres[index]) ** 2, axis=1)
        closest = np.minimum(closest, distance)
    return centres


def _kmeans(x: np.ndarray, k: int, rng: np.random.Generator, iterations: int = 40):
    centres = _kmeans_pp(x, k, rng)
    labels = np.zeros(x.shape[0], dtype=int)
    for _ in range(iterations):
        distance = ((x[:, None, :] - centres[None, :, :]) ** 2).sum(axis=2)
        new_labels = np.argmin(distance, axis=1)
        if np.array_equal(new_labels, labels):
            break
        labels = new_labels
        for index in range(k):
            members = x[labels == index]
            if members.size:
                centres[index] = members.mean(axis=0)
    return centres, labels


def _log_gaussian(x: np.ndarray, means: np.ndarray, variances: np.ndarray) -> np.ndarray:
    """log N(x | mu, sigma^2) for a diagonal covariance, shape (T, K)."""
    var = np.maximum(variances, 1e-3)
    diff = x[:, None, :] - means[None, :, :]
    return -0.5 * (
        np.log(2.0 * np.pi * var)[None, :, :] + (diff ** 2) / var[None, :, :]
    ).sum(axis=2)


def _log_sum_exp(values: np.ndarray) -> np.ndarray:
    peak = values.max(axis=1, keepdims=True)
    return (peak + np.log(np.exp(values - peak).sum(axis=1, keepdims=True))).squeeze(1)


def fit_groups(x: np.ndarray, groups: int = 3, seed: int = 0,
               max_iter: int = 150, tolerance: float = 1e-5,
               restarts: int = 3) -> GroupModel:
    """Fit a diagonal-covariance GMM with EM; best of ``restarts`` seeds."""
    if groups < 2:
        raise ValueError("groups must be at least 2")
    if x.shape[0] < groups * 2:
        raise ValueError("not enough frames for the requested number of groups")

    best: GroupModel | None = None
    for restart in range(restarts):
        rng = np.random.default_rng(seed + restart)
        centres, labels = _kmeans(x, groups, rng)

        means = centres.copy()
        variances = np.empty_like(means)
        weights = np.empty(groups)
        for index in range(groups):
            members = x[labels == index]
            if members.shape[0] < 2:
                members = x
            variances[index] = members.var(axis=0) + 1e-3
            weights[index] = max(float((labels == index).mean()), 1e-3)
        weights /= weights.sum()

        previous = -np.inf
        log_likelihood = -np.inf
        iteration = 0
        for iteration in range(1, max_iter + 1):
            log_joint = np.log(np.maximum(weights, EPS))[None, :] + _log_gaussian(x, means, variances)
            normaliser = _log_sum_exp(log_joint)
            log_likelihood = float(normaliser.mean())
            responsibilities = np.exp(log_joint - normaliser[:, None])

            mass = responsibilities.sum(axis=0) + EPS
            weights = mass / x.shape[0]
            means = (responsibilities.T @ x) / mass[:, None]
            deviations = (x[:, None, :] - means[None, :, :]) ** 2
            weighted = np.einsum("tk,tkd->kd", responsibilities, deviations)
            variances = np.maximum(weighted / mass[:, None], 1e-3)

            if abs(log_likelihood - previous) < tolerance:
                break
            previous = log_likelihood

        model = GroupModel(
            weights=weights,
            means=means,
            variances=variances,
            responsibilities=responsibilities,
            log_likelihood=log_likelihood,
            iterations=iteration,
        )
        if best is None or model.log_likelihood > best.log_likelihood:
            best = model

    assert best is not None
    return best


def smoothed_probabilities(model: GroupModel, sigma: float) -> np.ndarray:
    """Short centred Gaussian over time; the proposal's q_g(t)."""
    if sigma <= 0.0:
        return model.responsibilities.copy()
    smoothed = np.empty_like(model.responsibilities)
    for index in range(model.count):
        smoothed[:, index] = ndimage.gaussian_filter1d(
            model.responsibilities[:, index], sigma=max(sigma, 0.0)
        )
    return smoothed


def group_envelopes(features, model: GroupModel, sigma: float = 1.5) -> np.ndarray:
    """o_g(t) = q_g(t) * SF(t), shape (T, K)."""
    probabilities = smoothed_probabilities(model, sigma)
    return probabilities * features.flux[:, None]


def _peaks(envelope: np.ndarray, delta: float, min_distance: int,
           prominence: float) -> np.ndarray:
    if envelope.size == 0:
        return np.zeros(0, dtype=int)
    threshold = ndimage.median_filter(envelope, size=31) + delta
    found, _ = signal.find_peaks(
        envelope,
        height=threshold,
        distance=max(1, int(min_distance)),
        prominence=prominence,
    )
    return found


def detect_grouped(features, model: GroupModel, sigma: float = 1.5,
                   delta: float = 0.03, min_spacing: float = 0.06,
                   prominence: float = 0.02) -> list[dict]:
    """Independent onset detection inside every group envelope."""
    hop = float(features.times[1] - features.times[0]) if features.times.size > 1 else 0.01
    distance = max(1, int(round(min_spacing / hop)))
    envelopes = group_envelopes(features, model, sigma)

    candidates: list[dict] = []
    for group in range(model.count):
        raw = envelopes[:, group]
        scale = float(np.percentile(raw, 95)) if raw.size else 0.0
        if scale <= EPS:
            continue
        normalised = np.clip(raw / scale, 0.0, 1.0)
        peaks = _peaks(normalised, delta=delta, min_distance=distance, prominence=prominence)
        for frame in peaks:
            value = float(normalised[frame])
            if value < 0.10:
                continue
            candidates.append({
                "time": float(features.times[frame]),
                "frame": int(frame),
                "group": int(group),
                "strength": value,
                "source": "grouped",
            })
    return candidates


def detect_pooled(features, model: GroupModel, min_spacing: float = 0.06,
                  delta: float = 0.03, prominence: float = 0.02) -> list[dict]:
    """Ablation baseline: one pooled onset stream, each peak labelled by argmax q."""
    hop = float(features.times[1] - features.times[0]) if features.times.size > 1 else 0.01
    peaks = _peaks(features.flux, delta=delta,
                   min_distance=max(1, int(round(min_spacing / hop))),
                   prominence=prominence)
    labels = model.labels()
    candidates: list[dict] = []
    for frame in peaks:
        value = float(features.flux[frame])
        if value < 0.10:
            continue
        candidates.append({
            "time": float(features.times[frame]),
            "frame": int(frame),
            "group": int(labels[frame]),
            "strength": value,
            "source": "pooled",
        })
    return candidates


def group_character(features, model: GroupModel) -> list[dict]:
    """Describe each group so it can be mapped onto a gameplay lane.

    Uses band energies and timbre descriptors, weighted by the soft
    responsibilities, so the naming reflects what the group actually contains.
    """
    total = features.bands.sum(axis=1) + EPS
    ratios = features.bands / total[:, None]
    responsibilities = model.responsibilities
    mass = responsibilities.sum(axis=0) + EPS

    descriptions = []
    for index in range(model.count):
        weight = responsibilities[:, index]
        low, mid, high = (weight @ ratios) / mass[index]
        descriptions.append({
            "group": index,
            "weight": float(model.weights[index]),
            "low_ratio": float(low),
            "mid_ratio": float(mid),
            "high_ratio": float(high),
            "flatness": float((weight @ features.flatness) / mass[index]),
            "attack": float((weight @ features.attack) / mass[index]),
            "energy": float((weight @ features.log_rms) / mass[index]),
            "centroid": float((weight @ features.centroid) / mass[index]),
            "percussive": float((weight @ features.percussive) / mass[index]),
        })
    return descriptions


def _lane_scores(character: dict) -> tuple[float, float, float]:
    """Score a group for lane 0 (attack), 1 (defend) and 2 (jump).

    Low-and-percussive reads as a kick / bass impact (jump), bright-and-
    percussive as a snare / hat (attack), harmonic-and-sustained as a tonal
    layer (defend). Centroid is squashed so a single very bright group cannot
    dominate every slot.
    """
    brightness = character["centroid"] / (character["centroid"] + 900.0)
    percussive = character["percussive"]
    harmonic = 1.0 - percussive

    attack = percussive * brightness + 0.4 * character["flatness"]
    defend = harmonic * (1.0 - brightness) + harmonic * 0.3
    jump = percussive * (1.0 - brightness) + 0.5 * character["attack"]
    return attack, defend, jump


def assign_lanes(descriptions: list[dict]) -> dict[int, int]:
    """Best one-to-one mapping from groups to the three gameplay lanes.

    Lane order follows the chart contract: 0 attack, 1 defend, 2 jump.
    With fewer groups than lanes the strongest distinct groups win.
    """
    from itertools import permutations

    count = len(descriptions)
    scores = np.array([_lane_scores(item) for item in descriptions])
    lanes = min(count, 3)

    best_total, best_choice = -np.inf, None
    for chosen_lanes in permutations(range(3), lanes):
        for order in permutations(range(count), lanes):
            total = sum(scores[order[position], chosen_lanes[position]]
                        for position in range(lanes))
            if total > best_total:
                best_total, best_choice = total, dict(zip(order, chosen_lanes))

    return best_choice or {}


def sustain_envelope(features, character: dict, sigma: float = 1.5) -> np.ndarray:
    """Energy of the band this group lives in, used to judge hold length.

    The onset envelope o_g decays by construction (it is flux), so holds must
    be measured on sustained energy instead: a tonal pad keeps its band
    energy up, a drum hit does not.
    """
    ratios = [character["low_ratio"], character["mid_ratio"], character["high_ratio"]]
    band = int(np.argmax(ratios))
    envelope = features.bands[:, band].astype(np.float64)
    scale = float(np.percentile(envelope, 95)) if envelope.size else 0.0
    if scale <= EPS:
        return np.zeros_like(envelope)
    envelope = np.clip(envelope / scale, 0.0, 1.0)
    return ndimage.gaussian_filter1d(envelope, sigma=max(sigma, 0.0))
