"""Scrolling text in a screen recording, measured: where one line of text is
on every frame; for every scroll from rest to rest its distance, duration,
speeds and the cubic Bezier it fits on its own; the loop periods; and every
frame of each title against Music's model, a plain marquee (hold 3 s, then
30 pt/s) whose whole loop runs through ease-in-ease-out. How Music's timing
was found for MarqueeLine (CLAUDE.md, Open work item 10), and how to check
Ammy's row against it.

    python scripts/measure_marquee.py RECORDING.mp4 784 840

The two numbers are the first and last-plus-one pixel rows of the line, in
the recording's own pixels. --scale is pixels per point (2 on an SE, 3 on a
Pro Max); --columns is a stretch of the line clear of both fades (default:
the middle 40% of the frame). Uses each frame's own timestamp, never an
assumed frame rate, since screen recordings drop frames. Writes
RECORDING.positions.csv beside the recording. Needs ffmpeg on PATH and numpy.
"""
import argparse
import re
import subprocess
import sys

import numpy as np

HOLD, RATE = 3.0, 30.0  # Music's plain marquee under its eased loop (CLAUDE.md, item 10)
REST_PX = 0.05      # a frame that moves less than this is resting
REST_FRAMES = 30    # and half a second of those is a rest
CHANGE = 0.05       # a frame that matches the last this badly is new text

NAMED = {
    "linear": (0.0, 0.0, 1.0, 1.0),
    "easeIn": (0.42, 0.0, 1.0, 1.0),
    "easeOut": (0.0, 0.0, 0.58, 1.0),
    "easeInEaseOut": (0.42, 0.0, 0.58, 1.0),
    "CA default": (0.25, 0.1, 0.25, 1.0),
}


def decode(video, top, bottom):
    """Every frame's rows [top, bottom) in grey, and each frame's timestamp."""
    width = int(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width",
         "-of", "csv=p=0", video], capture_output=True, text=True, check=True).stdout.split()[0])
    rows = bottom - top
    run = subprocess.run(
        ["ffmpeg", "-v", "info", "-nostats", "-i", video, "-map", "0:v:0", "-fps_mode", "passthrough",
         "-vf", f"crop={width}:{rows}:0:{top},format=gray,showinfo", "-f", "rawvideo", "-"],
        capture_output=True, check=True)
    times = np.array([float(t) for t in re.findall(rb"pts_time:([0-9.]+)", run.stderr)])
    frames = np.frombuffer(run.stdout, np.uint8).reshape(-1, rows, width)
    if len(times) != len(frames):
        sys.exit(f"{len(frames)} frames but {len(times)} timestamps")
    return times, frames


def track(frames, x0, x1):
    """How far the line moved left since the frame before, to 0.01 px, and how
    badly the best match still fits (large when the text itself changed)."""
    # Text stands out from what's behind it, light on dark or dark on light.
    profile = np.concatenate([
        np.abs(chunk - np.median(chunk, axis=2, keepdims=True)).sum(axis=1)
        for chunk in (frames[k:k + 500].astype(np.float32) for k in range(0, len(frames), 500))])
    width = profile.shape[1]
    xs = np.arange(x0, x1, dtype=np.float64)
    fine = np.arange(-1.0, 1.0001, 0.01)
    moved, misfit = [0.0], [0.0]
    for i in range(1, len(profile)):
        before, now = profile[i - 1].astype(np.float64), profile[i, x0:x1].astype(np.float64)
        coarse = min(range(-12, 13), key=lambda s: ((now - before[x0 + s:x1 + s]) ** 2).sum())
        grid = xs[None, :] + (coarse + fine)[:, None]
        errors = ((np.interp(grid.ravel(), np.arange(width), before).reshape(grid.shape) - now) ** 2).sum(axis=1)
        k = int(errors.argmin())
        moved.append(coarse + fine[k])
        misfit.append(errors[k] / ((now ** 2).sum() + 1e-9))
    return np.array(moved), np.array(misfit)


def bezier(u, p1, p2):
    return 3 * (1 - u) ** 2 * u * p1 + 3 * (1 - u) * u ** 2 * p2 + u ** 3


def ease(progress, x1, y1, x2, y2):
    """A CSS / Core Animation timing curve: progress in time to progress in distance."""
    progress = np.clip(progress, 0.0, 1.0)
    lo, hi = np.zeros_like(progress), np.ones_like(progress)
    for _ in range(48):
        mid = (lo + hi) / 2
        early = bezier(mid, x1, x2) < progress
        lo, hi = np.where(early, mid, lo), np.where(early, hi, mid)
    return bezier((lo + hi) / 2, y1, y2)


def minimise(f, start, step, rounds=5000):
    """Nelder-Mead, so nothing beyond numpy is needed."""
    points = [np.array(start, float)] + [np.array(start, float) + np.eye(len(start))[i] * step[i]
                                         for i in range(len(start))]
    values = [f(p) for p in points]
    for _ in range(rounds):
        order = np.argsort(values)
        points, values = [points[i] for i in order], [values[i] for i in order]
        if values[-1] - values[0] <= 1e-9 * values[0] or np.ptp(points, axis=0).max() < 1e-7:
            break
        centre = np.mean(points[:-1], axis=0)
        reflected = centre + (centre - points[-1])
        fr = f(reflected)
        if fr < values[0]:
            expanded = centre + 2 * (centre - points[-1])
            fe = f(expanded)
            points[-1], values[-1] = (expanded, fe) if fe < fr else (reflected, fr)
        elif fr < values[-2]:
            points[-1], values[-1] = reflected, fr
        else:
            contracted = centre + (points[-1] - centre) / 2
            fc = f(contracted)
            if fc < values[-1]:
                points[-1], values[-1] = contracted, fc
            else:
                points = [points[0]] + [points[0] + (p - points[0]) / 2 for p in points[1:]]
                values = [values[0]] + [f(p) for p in points[1:]]
    best = int(np.argmin(values))
    return points[best], values[best]


def fit(t, x, distance, start_guess, duration_guess):
    """The free Bezier, start and duration that best put the line where it was,
    and how far each named curve misses with its own best start and duration."""
    def miss(p, curve):
        if p[1] <= 0.1:
            return 1e12
        return float(((distance * ease((t - p[0]) / p[1], *curve) - x) ** 2).mean())

    def free(p):
        if not (0 <= p[2] <= 1 and 0 <= p[4] <= 1):
            return 1e12
        return miss(p[:2], p[2:])

    best = min((minimise(free, [start_guess, duration_guess, *s], [0.2, 0.5, 0.05, 0.05, 0.05, 0.05])
                for s in [(0.3, 0.3, 0.56, 1.0), (0.25, 0.1, 0.25, 1.0), (0.0, 0.0, 0.58, 1.0)]),
               key=lambda r: r[1])
    named = {name: np.sqrt(minimise(lambda p: miss(p, c), [start_guess, duration_guess], [0.2, 0.5])[1])
             for name, c in NAMED.items()}
    return best[0], np.sqrt(best[1]), named


def whole_loop(t, x, distance, loop_guess, hold=None, rate=None):
    """Music's model: a plain marquee, a hold and then a constant speed, whose
    whole loop runs through ease-in-ease-out. Finds where the loop starts, and
    the hold and speed unless given, comparing positions modulo the distance;
    returns them with the rms and largest miss in points."""
    def misses(p):
        h, r = (hold, rate) if hold is not None else (p[2], p[3])
        loop = h + distance / r
        eased = loop * ease(((t - p[0]) % loop) / loop, *NAMED["easeInEaseOut"])
        model = np.clip(eased - h, 0, None) * r
        return (model - x - p[1] + distance / 2) % distance - distance / 2

    start = [loop_guess, 0.0] + ([] if hold is not None else [3.0, 30.0])
    step = [0.3, 1.0] + ([] if hold is not None else [0.2, 1.0])
    p, _ = minimise(lambda p: float((misses(p) ** 2).mean()) if hold is not None or p[2] > 0 and p[3] > 1 else 1e12,
                    start, step)
    m = misses(p)
    return p, np.sqrt((m ** 2).mean()), np.abs(m).max()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("video")
    ap.add_argument("top", type=int)
    ap.add_argument("bottom", type=int)
    ap.add_argument("--scale", type=float, default=2.0, help="pixels per point")
    ap.add_argument("--columns", type=lambda s: tuple(int(v) for v in s.split(":")),
                    help="x0:x1, a stretch of the line clear of both fades")
    a = ap.parse_args()

    times, frames = decode(a.video, a.top, a.bottom)
    width = frames.shape[2]
    x0, x1 = a.columns or (int(width * 0.3), int(width * 0.7))
    moved, misfit = track(frames, x0, x1)
    print(f"{len(times)} frames, {times[0]:.3f}-{times[-1]:.3f} s, tracked on columns {x0}-{x1}")

    position = np.cumsum(np.where(misfit > CHANGE, 0.0, moved)) / a.scale
    with open(a.video.rsplit(".", 1)[0] + ".positions.csv", "w") as out:
        out.write("t,position_pt,moved_px,misfit\n")
        for row in zip(times, position, moved, misfit):
            out.write("%.6f,%.3f,%.3f,%.5f\n" % row)

    # Rests: half a second or more without movement. Text changes split titles.
    still = np.abs(moved) < REST_PX
    changes = set(np.where(misfit > CHANGE)[0])
    rests, i = [], 0
    while i < len(times):
        j = i
        while j < len(times) and still[j] and j not in changes:
            j += 1
        if j - i >= REST_FRAMES:
            rests.append((i, j - 1))
        i = max(j, i + 1)

    for (a0, a1), (b0, b1) in zip(rests, rests[1:]):
        if any(a1 < c <= b0 for c in changes):
            continue                            # a different title by the end
        distance = position[b0] - position[a1]
        if distance < 1:
            continue
        window = slice(max(a0, a1 - 30), min(b1, b0 + 30) + 1)
        t, x = times[window], position[window] - position[a1]
        guess_start, guess_end = times[a1], times[b0]
        params, rms, named = fit(t, x, distance, guess_start, guess_end - guess_start)
        start, duration, x1, y1, x2, y2 = params
        speed = np.diff(position[a1:b0 + 1]) / np.diff(times[a1:b0 + 1])
        peak = np.convolve(speed, np.ones(15) / 15, mode="valid").max()
        print(f"\nscroll from {start:.3f} s for {duration:.3f} s: {distance:.2f} pt, "
              f"mean {distance / duration:.2f} pt/s, peak {peak:.1f} pt/s ({peak * duration / distance:.2f}x the mean)")
        print(f"  this scroll alone: cubic-bezier({x1:.3f}, {y1:.3f}, {x2:.3f}, {y2:.3f}) within {rms:.3f} pt rms; "
              "named curves miss by " + ", ".join(f"{n} {v:.2f}" for n, v in named.items()) + " pt")
        # Every frame of this text, loops and rests together, against Music's model.
        first = max([c + 1 for c in changes if c <= a0] + [0])
        last = min([c for c in changes if c > b1] + [len(times)])
        ts, xs = times[first:last], position[first:last] - position[a1]
        guess = start - 0.3 * (HOLD + distance / RATE)
        p, rms, worst = whole_loop(ts, xs, distance, guess, HOLD, RATE)
        q, rms_free, _ = whole_loop(ts, xs, distance, p[0])
        print(f"  {ts[0]:.1f}-{ts[-1]:.1f} s against Music's model (hold {HOLD:g} s, then {RATE:g} pt/s, the whole loop "
              f"eased in and out): {rms:.2f} pt rms, {worst:.2f} at most; best hold {q[2]:.2f} s and "
              f"speed {q[3]:.1f} pt/s, {rms_free:.2f} pt rms")

    # Loops: from one scroll's first moving frame to the next one's, the same
    # text throughout. Needs only the starts, so a scroll cut off later counts.
    print()
    moving = [k for k, (r0, r1) in enumerate(rests) if r1 + 1 < len(times) and r1 + 1 not in changes]
    for k0, k1 in zip(moving, moving[1:]):
        (p0, p1), (q0, q1) = rests[k0], rests[k1]
        if any(p1 < c <= q1 for c in changes):
            continue
        print(f"loop {times[q1] - times[p1]:.3f} s from {times[p1]:.3f} s: moving for {times[q0] - times[p1]:.3f} s, "
              f"then still for {times[q1] - times[q0]:.3f} s (still: under {REST_PX} px a frame)")
    for c in sorted(changes):
        later = [k for k in moving if rests[k][0] > c and not any(c < d <= rests[k][0] for d in changes)]
        if later:
            print(f"text changed at {times[c]:.3f} s and first moved {times[rests[later[0]][1]] - times[c]:.3f} s later")


if __name__ == "__main__":
    main()
