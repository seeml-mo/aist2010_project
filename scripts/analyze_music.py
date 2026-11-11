"""Offline spectral-flux onset / autocorrelation beat baseline; no ML models."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT.parent
if not (SOURCE_ROOT / 'assets/Voxel Revolution.mp3').exists() and (SOURCE_ROOT / 'demo/assets/Voxel Revolution.mp3').exists():
    SOURCE_ROOT = SOURCE_ROOT / 'demo'
sys.path.insert(0, str(SOURCE_ROOT / '.deps'))
from scipy import signal, ndimage


def build(source, ffmpeg, start=28.0, duration=30.0):
    sr, hop = 22050, 220
    context = min(2.0, start)
    raw = subprocess.check_output([
        str(ffmpeg), '-v', 'error', '-ss', str(start-context), '-i', str(source),
        '-t', str(duration+context), '-ac', '1', '-ar', str(sr), '-f', 'f32le', '-'])
    audio = np.frombuffer(raw, np.float32)
    f, times, spectrum = signal.stft(audio, sr, nperseg=2048, noverlap=2048-hop)
    magnitude = abs(spectrum[(f >= 60) & (f <= 9000)])
    logmag = np.log1p(100 * magnitude)
    flux = np.maximum(np.diff(logmag, axis=1, prepend=logmag[:, :1]), 0).mean(axis=0)
    flux = ndimage.gaussian_filter1d(flux, 0.012 / (hop/sr))
    novelty = np.maximum(flux-ndimage.median_filter(flux, size=31), 0)
    novelty /= max(float(novelty.max()), 1e-9)
    dt = hop/sr
    peaks, _ = signal.find_peaks(novelty, distance=round(.16/dt), prominence=.035)
    onset_times = times[peaks]-context
    centered = novelty-novelty.mean()
    autocorr = signal.correlate(centered, centered, mode='full', method='fft')[len(centered)-1:]
    lags = np.arange(round(60/143/dt), round(60/105/dt)+1)
    period = int(lags[np.argmax(autocorr[lags])])*dt
    # Refine period as well as phase across the entire excerpt. Autocorrelation
    # alone can accumulate a small tempo error into a noticeable end-of-song drift.
    best_score, phase = -1.0, 0.0
    initial_period = period
    for candidate in np.arange(initial_period*.95, initial_period*1.05, dt/10):
        for p in np.arange(0, candidate, dt):
            score = np.interp(np.arange(p, times[-1], candidate), times, novelty).mean()
            if score > best_score:
                best_score, phase, period = score, float(p), float(candidate)
    beats = np.arange(phase-context, duration, period)
    beats = beats[beats >= 0]
    for i, b in enumerate(beats):
        near = np.where(abs(times-context-b) <= .035)[0]
        if len(near):
            beats[i] = times[near[np.argmax(novelty[near])]]-context
    onsets = [{'time': round(float(t), 5), 'strength': round(float(novelty[k]), 4)}
              for t, k in zip(onset_times, peaks) if 0 <= t < duration]
    jumps = [float(b) for i, b in enumerate(beats) if i % 4 == 0 and 2.0 < b < duration-1.5]
    attacks = []
    for i, b in enumerate(beats):
        if i % 4 != 2 or not 2 < b < duration-1:
            continue
        if any(abs(b-j) < .8 for j in jumps):
            continue
        candidates = [o for o in onsets if abs(o['time']-b) < .10 and o['strength'] >= .055]
        if candidates:
            onset = max(candidates, key=lambda o: o['strength'])
            attacks.append({'time': onset['time'], 'beat_time': round(float(b), 5),
                            'strength': onset['strength'], 'kind': 'attack'})
    speed, spawn_x, floor_row, width, height = 150, 224, 24, 320, 34
    data = [0] * (width*height)
    gaps = [(int((spawn_x+speed*(j+.08))//16), int(np.ceil((spawn_x+speed*(j+.43))/16))) for j in jumps]
    for x in range(width):
        if any(a <= x < b for a, b in gaps):
            continue
        for y in range(floor_row, height):
            data[y*width+x] = 1 if y == floor_row else 2
    m = {'orientation': 'orthogonal', 'infinite': False, 'width': width, 'height': height,
         'tilewidth': 16, 'tileheight': 16,
         'tilesets': [{'firstgid': 1, 'image': '../runner_tiles.png', 'tilewidth': 16,
                       'tileheight': 16, 'columns': 2, 'tilecount': 2}],
         'layers': [{'type': 'tilelayer', 'name': 'Music terrain', 'width': width, 'height': height,
                     'properties': [{'name': 'solid', 'value': True}], 'data': data},
                    {'type': 'objectgroup', 'objects': [{'name': 'spawn', 'x': spawn_x, 'y': floor_row*16-22}]}],
         'music': {'stream': 'res://assets/voxel_30s.ogg', 'title': 'Voxel Revolution',
                   'duration': duration, 'speed': speed, 'floor_y': floor_row*16,
                   'bpm': 60/period, 'beats': [round(float(b), 5) for b in beats],
                   'onsets': onsets, 'jumps': [{'time': round(j, 5), 'kind': 'jump'} for j in jumps],
                   'attacks': attacks, 'gaps': gaps,
                   'method': 'Positive log-spectral flux, local median subtraction, peak picking; '
                             'autocorrelation tempo (105-143 BPM prior), whole-excerpt tempo/phase refinement, local beat refinement. '
                             'Attacks select measured onsets within 100ms of eligible beats. '
                             'Sparse gameplay selection; not every onset becomes an obstacle.'}}
    (ROOT/'assets/maps/music_demo.json').write_text(json.dumps(m, indent=2)+'\n', encoding='utf-8')
    subprocess.run([str(ffmpeg), '-y', '-v', 'error', '-ss', str(start), '-i', str(source),
                    '-t', str(duration), '-af', 'afade=t=in:d=0.04,afade=t=out:st=29.7:d=0.3',
                    '-c:a', 'libvorbis', '-q:a', '5', str(ROOT/'assets/voxel_30s.ogg')], check=True)
    from PIL import Image, ImageDraw
    image = Image.new('RGBA', (32, 16), '#153537')
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 15, 2), fill='#6ce4c0')
    draw.rectangle((16, 0, 31, 15), fill='#10272e')
    image.save(ROOT/'assets/runner_tiles.png')
    print(f'{60/period:.2f} BPM, {len(onsets)} onsets, {len(jumps)} jumps, {len(attacks)} attacks')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--audio', type=Path, default=SOURCE_ROOT/'assets/Voxel Revolution.mp3')
    parser.add_argument('--ffmpeg', type=Path, default=SOURCE_ROOT/'tools/ffmpeg.exe')
    args = parser.parse_args()
    build(args.audio, args.ffmpeg)
