#!/usr/bin/env python3
# Lab only (keepalive-lab). Reads what lab/run-scenarios.sh and
# lab/receiver.py left in OUT and prints, per scenario, the facts the verdicts
# rest on. Times are seconds after the scenario's FAULT (or after it went to
# the background, when there is no fault).
#   python3 -I lab/analyze.py OUT
import json
import pathlib
import re
import sys

out = pathlib.Path(sys.argv[1])
pushes = []
pf = out / "pushes.jsonl"
if pf.exists():
    for line in pf.read_text(encoding="utf-8").splitlines():
        try:
            pushes.append(json.loads(line))
        except ValueError:
            pass

DIAG = ["engine_running", "node_playing", "running", "resumes", "resume_failures", "fail_stage", "fail_code",
        "fail_run", "fail_run_max", "holds", "hold_saves", "hold_expiries", "hold_refusals", "retries",
        "self_heals", "int_began", "int_ended", "int_on_resume", "down_s", "secs_since_fail", "last_error",
        "app_state", "bg_secs_left", "app_uptime_s", "pushfail", "media_resets", "config_changes"]


def kv(line):
    return dict(re.findall(r"(\w+)=(\S+)", line))


def fmt(x):
    return "-" if x is None else ("%+.1f" % x)


def scenario(d):
    marks = []
    for line in (d / "marks.txt").read_text().splitlines():
        t, _, what = line.partition(" ")
        marks.append((float(t), what))
    m = {}
    for t, what in marks:
        m.setdefault(what.split(" ")[0], t)
    probe = []
    pp = d / "probe.txt"
    if not pp.exists() and (d / "probe-documents.txt").exists():
        pp = d / "probe-documents.txt"
    if pp.exists():
        for line in pp.read_text(errors="replace").splitlines():
            t, _, rest = line.partition(" ")
            try:
                probe.append((float(t), rest))
            except ValueError:
                pass
    bg = m.get("background")
    fault = next((t for t, r in probe if r.startswith("FAULT stop") or r.startswith("FAULT fail from launch")), None)
    # A failure from launch is timed from going to the background, when the
    # hold's clock starts.
    from_launch = any(r.startswith("FAULT fail from launch") for t, r in probe)
    zero = bg if from_launch else (fault or bg)
    front = m.get("foreground") or m.get("terminate")
    end = m.get("end")
    rel = lambda t: None if t is None or zero is None else t - zero
    print("=" * 78)
    print(d.name)
    for t, what in marks:
        print("  mark %s  %s" % (fmt(rel(t)), what))
    if not probe:
        print("  NO PROBE FILE")
        return
    # Process continuity from the probe
    pids = sorted({kv(r).get("pid") for t, r in probe if "pid=" in r} - {None})
    print("  probe pids: %s" % pids)
    lp = (d / "pids.txt").read_text().split("\n") if (d / "pids.txt").exists() else []
    lpids = []
    for line in lp:
        parts = line.split()
        if len(parts) > 1 and parts[1] not in lpids:
            lpids.append(parts[1])
    print("  launchctl pids in order: %s" % lpids)
    ticks = [(t, r) for t, r in probe if bg and t >= bg and (front is None or t <= front)]
    gaps = [(ticks[i][0], ticks[i + 1][0] - ticks[i][0]) for i in range(len(ticks) - 1)
            if ticks[i + 1][0] - ticks[i][0] > 2.5]
    print("  background phase: %d probe lines from %s to %s; gaps > 2.5 s: %s" % (
        len(ticks), fmt(rel(ticks[0][0])) if ticks else "-", fmt(rel(ticks[-1][0])) if ticks else "-",
        ", ".join("%s for %.1f s" % (fmt(rel(t)), g) for t, g in gaps) or "none"))
    if ticks and front:
        last = ticks[-1][0]
        quiet = front - last
        print("  last line before going to the front/terminate: %s (%.1f s before it)%s" % (
            fmt(rel(last)), quiet, "  -> QUIET" if quiet > 10 else "  -> continuous"))
    for t, r in probe:
        if r.startswith(("FAULT", "LABFAIL", "BACKGROUND", "START")):
            print("  %s %s" % (fmt(rel(t)), r[:200]))
    after = [(t, r) for t, r in probe if fault and t > fault and "engine=" in r]
    first_play = next((t for t, r in after if kv(r).get("engine") == "1" and kv(r).get("node") == "1"), None)
    print("  first probe line with engine and node playing after the fault: %s" % fmt(rel(first_play)))
    bgl = [(t, kv(r).get("bgleft")) for t, r in after if kv(r).get("bgleft") not in (None, "-")]
    if bgl:
        print("  bgleft: first %s at %s, last %s at %s (%d readings)" % (bgl[0][1], fmt(rel(bgl[0][0])),
                                                                        bgl[-1][1], fmt(rel(bgl[-1][0])), len(bgl)))
    fd = next((r for t, r in probe if r.startswith("FAULTDONE")), None)
    if fd:
        print("  at the hold's opening (FAULTDONE): bgleft=%s" % kv(fd).get("bgleft"))
    if ticks:
        print("  last background line: %s" % ticks[-1][1])
    # Pushes
    lo, hi = m.get("launch"), end or 1e18
    mine = [p for p in pushes if lo and lo <= p["t"] <= hi]
    print("  pushes: %d" % len(mine))
    prev = None
    for p in mine:
        dg = p["body"].get("diag", {})
        gap = "" if prev is None else " (+%.1f)" % (p["t"] - prev)
        prev = p["t"]
        fields = " ".join("%s=%s" % (k, dg[k]) for k in DIAG if k in dg)
        print("   push %s%s %s" % (fmt(rel(p["t"])), gap, fields))
        if "prev_tail" in dg or "prev_alive" in dg:
            tail = dg.get("prev_tail") or []
            print("     prev_alive=%r" % dg.get("prev_alive"))
            for line in tail[-6:]:
                print("     prev_tail| %s" % line)
    if m.get("relaunch"):
        before = [(t, r) for t, r in probe if t < m["terminate"]]
        if before:
            print("  F: probe's last line before terminate: %s %s" % (fmt(rel(before[-1][0])), before[-1][1][:80]))
        first = next((p for p in mine if p["t"] > m["relaunch"]), None)
        if first:
            dg = first["body"].get("diag", {})
            print("  F: first push after relaunch at %s: prev_alive=%r, prev_tail last=%r" % (
                fmt(rel(first["t"])), dg.get("prev_alive"), (dg.get("prev_tail") or [None])[-1]))
    for j in sorted(d.glob("journal-*.log")):
        lines = j.read_text(errors="replace").splitlines()
        print("  %s (last 14 of %d lines):" % (j.name, len(lines)))
        for line in lines[-14:]:
            print("     | %s" % line)


for d in sorted(p for p in out.iterdir() if p.is_dir() and (p / "marks.txt").exists()):
    try:
        scenario(d)
    except Exception as e:  # keep going: one broken run must not hide the rest
        print("%s: analysis failed: %r" % (d.name, e))
crashes = [p for p in out.rglob("*.ips") if "Ammy" in p.name or "ammy" in p.read_text(errors="replace")[:4000]]
print("=" * 78)
print("Ammy crash reports: %s" % ([str(p.relative_to(out)) for p in crashes] or "none"))
for p in crashes:
    txt = p.read_text(errors="replace")
    print("  %s: %s" % (p.name, ", ".join(sorted(set(re.findall(r"0x8badf00d|EXC_\w+|SIG\w+|termination\w*", txt)))[:10])))
