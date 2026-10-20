
# -*- coding: utf-8 -*-
"""P6 task-2: WAV analysis for the island audio set (numpy only, no scipy).

Usage (bundled python):
  python tools/analyze_audio6.py --phase before
  python tools/analyze_audio6.py --phase after
  python tools/analyze_audio6.py --phase compare

Outputs (default D:/休闲小岛幻境/开发产物/logs):
  audio6_before.json / audio6_analysis_before.txt
  audio6_after.json  / audio6_analysis_after.txt
  audio6_analysis.txt            <- combined before/after comparison report

Metrics: peak/peak-dBFS, RMS/RMS-dBFS, crest, DC, clipping, spectral band energy,
spectral centroid, >8k energy share, 2-6k "harsh" share, HF kurtosis, transients/sec,
narrowband tonal prominence (cricket/whistle detection), envelope modulation peak,
loop seam (first/last sample diff vs normal sample-diff distribution, edge RMS step).
"""
import argparse
import json
import math
import os
import sys
import wave

import numpy as np

PROJ = r"D:/休闲小岛幻境/游戏工程"
OUTDIR = r"D:/休闲小岛幻境/开发产物/logs"
DEFAULT_DIR = os.path.join(PROJ, "audio")
TARGET_FILES = [
    "ocean_loop.wav", "wind_loop.wav", "night_loop.wav", "fire_crackle.wav",
    "bird_1.wav", "bird_2.wav", "bird_3.wav",
    "door_open.wav", "door_close.wav", "ui_click.wav", "water_splash.wav",
]
FOCUS = ["fire_crackle.wav", "night_loop.wav"]


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        nch = w.getnchannels()
        sw = w.getsampwidth()
        n = w.getnframes()
        raw = w.readframes(n)
        comp = w.getcomptype()
    if comp != "NONE":
        raise RuntimeError("compressed wav not supported: %s" % comp)
    if sw == 1:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif sw == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        v = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8)
             | (b[:, 2].astype(np.int32) << 16))
        v = np.where(v >= (1 << 23), v - (1 << 24), v)
        x = v.astype(np.float64) / float(1 << 23)
    elif sw == 4:
        x = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    else:
        raise RuntimeError("unsupported sample width %d" % sw)
    if nch > 1:
        x = x.reshape(-1, nch)
        mono = x.mean(axis=1)
    else:
        x = x.reshape(-1, 1)
        mono = x[:, 0]
    return dict(sr=sr, nch=nch, sw=sw, n=n, data=x, mono=mono, dur=n / float(sr))


def db(v, floor=-120.0):
    return max(floor, 20.0 * math.log10(max(v, 1e-12)))


def band_energy(spec_sq, freqs, lo, hi, total):
    m = (freqs >= lo) & (freqs < hi)
    return 100.0 * float(np.sum(spec_sq[m])) / total


def analysis(path):
    d = read_wav(path)
    sr, mono, x = d["sr"], d["mono"], d["data"]
    n = d["n"]
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x ** 2)))
    crest = peak / (rms + 1e-12)
    dc = float(np.mean(mono))
    clip_samples = int(np.sum(np.abs(x) >= 0.999))
    # longest run of samples above 0.98 (hard-clip evidence)
    hard = (np.abs(mono) >= 0.98).astype(np.int8)
    max_run = 0
    run = 0
    for v in hard:
        run = run + 1 if v else 0
        if run > max_run:
            max_run = run
    zcr = float(np.mean(np.abs(np.diff(np.signbit(mono).astype(np.int8)))) * sr / 2.0)
    diffs = np.abs(np.diff(mono))
    diff_mean = float(np.mean(diffs))
    diff_p999 = float(np.percentile(diffs, 99.9))
    max_jump = float(np.max(diffs))

    # spectrum over whole file (hann), report band shares and centroid
    win = np.hanning(n)
    spec = np.abs(np.fft.rfft(mono * win))
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    spec_sq = spec ** 2
    total = float(np.sum(spec_sq)) + 1e-30
    bands = {
        "0-200": band_energy(spec_sq, freqs, 0, 200, total),
        "200-1k": band_energy(spec_sq, freqs, 200, 1000, total),
        "1k-2k": band_energy(spec_sq, freqs, 1000, 2000, total),
        "2k-4k": band_energy(spec_sq, freqs, 2000, 4000, total),
        "4k-6k": band_energy(spec_sq, freqs, 4000, 6000, total),
        "6k-8k": band_energy(spec_sq, freqs, 6000, 8000, total),
        "8k-12k": band_energy(spec_sq, freqs, 8000, 12000, total),
        "12k+": band_energy(spec_sq, freqs, 12000, sr / 2.0 + 1, total),
    }
    centroid = float(np.sum(freqs * spec_sq) / total)
    hf8k = bands["8k-12k"] + bands["12k+"]
    # absolute level per band (dBFS RMS of the band-limited signal; Parseval-equivalent)
    fft_full = np.fft.rfft(mono)
    band_ranges = {
        "0-200": (0, 200), "200-1k": (200, 1000), "1k-2k": (1000, 2000),
        "2k-4k": (2000, 4000), "4k-6k": (4000, 6000), "6k-8k": (6000, 8000),
        "8k-12k": (8000, 12000), "12k+": (12000, sr / 2.0 + 1),
    }
    band_dbfs = {}
    for nm, (lo, hi) in band_ranges.items():
        mask = (freqs >= lo) & (freqs < hi)
        y = np.fft.irfft(fft_full * mask, n=n)
        band_dbfs[nm] = round(db(float(np.sqrt(np.mean(y ** 2)))), 2)
    band_dbfs["2k-6k"] = round(db(float(np.sqrt(np.mean(
        np.fft.irfft(fft_full * ((freqs >= 2000) & (freqs < 6000)), n=n) ** 2)))), 2)
    harsh_2_6k = sum(bands[k] for k in ("2k-4k", "4k-6k")) + \
        max(0.0, band_energy(spec_sq, freqs, 1000, 2000, total) * 0.0)

    # HF (3-10 kHz) kurtosis: spiky/clipped brightness -> high kurtosis
    hf = np.fft.irfft(np.fft.rfft(mono) * ((freqs >= 3000) & (freqs < 10000)))
    hf_rms = float(np.sqrt(np.mean(hf ** 2)))
    hf_m4 = float(np.mean(hf ** 4))
    hf_kurt = hf_m4 / (hf_rms ** 4 + 1e-30)

    # transients: peaks of 2-8 kHz envelope above 4x its median, keep >= 20 ms apart
    hf_band = np.fft.irfft(np.fft.rfft(mono) * ((freqs >= 2000) & (freqs < 8000)))
    env = np.abs(hf_band)
    env_sr = sr
    k = max(1, int(0.005 * sr))  # 5ms moving average
    env_s = np.convolve(env, np.ones(k) / k, mode="same")
    med = float(np.median(env_s)) + 1e-9
    above = env_s > 4.0 * med
    # count rising edges with 20ms dead time
    dead = int(0.02 * sr)
    transients = []
    last = -dead
    for i in np.nonzero(above & ~np.roll(above, 1))[0]:
        if i - last >= dead:
            transients.append(i)
            last = i
    transients_per_sec = len(transients) / d["dur"]
    transient_peak_ratio = float(np.max(env_s) / (med + 1e-12))

    # narrowband tonal prominence in 2.5-6.5 kHz (cricket / whistle): strongest bin over local floor
    m = (freqs >= 2500) & (freqs < 6500)
    if np.any(m):
        sub = 20.0 * np.log10(spec[m] / (np.max(spec) + 1e-30) + 1e-12)
        floor = float(np.median(sub))
        tonal_db = float(np.max(sub) - floor)
        tonal_freq = float(freqs[m][int(np.argmax(sub))])
    else:
        tonal_db, tonal_freq = 0.0, 0.0

    # envelope modulation peak (0.05-2 Hz) -- helps distinguish "breathing" ambience from static hiss
    env_full = np.abs(mono)
    dec = max(1, int(sr / 200))
    env_d = env_full[: len(env_full) // dec * dec].reshape(-1, dec).mean(axis=1)
    env_d = env_d - env_d.mean()
    if len(env_d) > 64:
        ef = np.abs(np.fft.rfft(env_d * np.hanning(len(env_d))))
        efr = np.fft.rfftfreq(len(env_d), dec / float(sr))
        valid = (efr >= 0.05) & (efr <= 2.0)
        mod_peak = float(efr[valid][int(np.argmax(ef[valid]))]) if np.any(valid) else 0.0
    else:
        mod_peak = 0.0

    # loop seam: last->first sample jump against normal sample-diff distribution
    first, last = float(mono[0]), float(mono[-1])
    jump = abs(first - last)
    z = (jump - diff_mean) / (float(np.std(diffs)) + 1e-12)
    edge = max(1, int(0.010 * sr))
    edge_rms_first = float(np.sqrt(np.mean(mono[:edge] ** 2)))
    edge_rms_last = float(np.sqrt(np.mean(mono[-edge:] ** 2)))
    env_step_db = db(edge_rms_first) - db(edge_rms_last)
    # best crossfade window suggestion: match last 100ms against head candidates
    w = int(0.05 * sr)
    best_norm = None
    if n > 4 * w:
        seg_last = mono[-w:]
        best = (1e9, 0)
        lo = int(0.9 * sr)
        for pos in range(max(w, lo), int(1.6 * sr), max(1, int(0.002 * sr))):
            cand = mono[pos:pos + w]
            if len(cand) < w:
                break
            norm = float(np.linalg.norm(cand - seg_last)) / (float(np.linalg.norm(seg_last)) + 1e-12)
            if norm < best[0]:
                best = (norm, pos)
        best_norm = {"offset_s": best[1] / float(sr), "normdist": round(best[0], 4)}

    return {
        "file": os.path.basename(path),
        "sr": sr, "ch": d["nch"], "bits": d["sw"] * 8, "frames": n,
        "dur_s": round(d["dur"], 3),
        "peak": round(peak, 5), "peak_dbfs": round(db(peak), 2),
        "rms": round(rms, 6), "rms_dbfs": round(db(rms), 2),
        "crest": round(crest, 2), "dc": round(dc, 6),
        "clip_samples": clip_samples, "hard_clip_max_run": max_run,
        "max_sample_jump": round(max_jump, 5),
        "diff_mean": round(diff_mean, 6), "diff_p999": round(diff_p999, 6),
        "zcr_per_s": round(zcr, 1),
        "centroid_hz": round(centroid, 1),
        "band_pct": {k: round(v, 2) for k, v in bands.items()},
        "band_dbfs": band_dbfs,
        "hf8k_ratio_pct": round(hf8k, 2),
        "harsh_2_6k_pct": round(bands["2k-4k"] + bands["4k-6k"], 2),
        "hf_3_10k_kurtosis": round(hf_kurt, 2),
        "hf_transients": len(transients),
        "hf_transients_per_s": round(transients_per_sec, 2),
        "hf_peak_over_median": round(transient_peak_ratio, 1),
        "tonal_peak_db_2p5_6p5k": round(tonal_db, 1),
        "tonal_freq_hz": round(tonal_freq, 1),
        "envelope_mod_hz": round(mod_peak, 3),
        "seam": {
            "first": round(first, 6), "last": round(last, 6),
            "jump": round(jump, 6),
            "z_vs_sample_diff": round(z, 2),
            "edge10ms_rms_first": round(edge_rms_first, 5),
            "edge10ms_rms_last": round(edge_rms_last, 5),
            "edge_rms_step_db": round(env_step_db, 2),
            "best_xfade": best_norm,
        },
    }


def collect(directory):
    out = {}
    for name in TARGET_FILES:
        p = os.path.join(directory, name)
        if os.path.exists(p):
            out[name] = analysis(p)
        else:
            out[name] = {"file": name, "missing": True}
    return out


def fmt_report(info, title):
    lines = ["=" * 100, title, "=" * 100]
    for name in TARGET_FILES:
        a = info.get(name, {})
        if not a or a.get("missing"):
            lines.append("[%s] MISSING" % name)
            continue
        b = a["band_pct"]
        lines.append("[%s] sr=%d ch=%d bits=%d frames=%d dur=%.3fs"
                     % (name, a["sr"], a["ch"], a["bits"], a["frames"], a["dur_s"]))
        lines.append("    peak=%.4f (%.2f dBFS) rms=%.5f (%.2f dBFS) crest=%.2f dc=%+.6f "
                     "clip_samples=%d hard_clip_run=%d"
                     % (a["peak"], a["peak_dbfs"], a["rms"], a["rms_dbfs"], a["crest"],
                        a["dc"], a["clip_samples"], a["hard_clip_max_run"]))
        lines.append("    centroid=%.0f Hz  >8k=%.2f%%  2-6k=%.2f%%  HF(3-10k) kurtosis=%.2f  "
                     "HF transients=%d (%.2f/s) peak/median=%.1f"
                     % (a["centroid_hz"], a["hf8k_ratio_pct"], a["harsh_2_6k_pct"],
                        a["hf_3_10k_kurtosis"], a["hf_transients"],
                        a["hf_transients_per_s"], a["hf_peak_over_median"]))
        lines.append("    bands%%: 0-200=%.1f 200-1k=%.1f 1-2k=%.1f 2-4k=%.1f 4-6k=%.1f 6-8k=%.1f "
                     "8-12k=%.1f 12k+=%.2f  zcr=%.0f/s"
                     % (b["0-200"], b["200-1k"], b["1k-2k"], b["2k-4k"], b["4k-6k"],
                        b["6k-8k"], b["8k-12k"], b["12k+"], a["zcr_per_s"]))
        bd = a["band_dbfs"]
        lines.append("    band level dBFS: 0-200=%.1f 200-1k=%.1f 1-2k=%.1f 2-4k=%.1f 4-6k=%.1f "
                     "6-8k=%.1f 8-12k=%.1f 12k+=%.1f  2-6k=%.1f"
                     % (bd["0-200"], bd["200-1k"], bd["1k-2k"], bd["2k-4k"], bd["4k-6k"],
                        bd["6k-8k"], bd["8k-12k"], bd["12k+"], bd["2k-6k"]))
        lines.append("    tonal peak @ %.0f Hz = %.1f dB above floor | envelope mod=%.3f Hz"
                     % (a["tonal_freq_hz"], a["tonal_peak_db_2p5_6p5k"], a["envelope_mod_hz"]))
        s = a["seam"]
        lines.append("    seam: first=%+.5f last=%+.5f jump=%.6f (z=%.2f vs sample-diff) "
                     "edge10ms rms first=%.5f last=%.5f step=%.2f dB  best_xfade=%s"
                     % (s["first"], s["last"], s["jump"], s["z_vs_sample_diff"],
                        s["edge10ms_rms_first"], s["edge10ms_rms_last"],
                        s["edge_rms_step_db"], json.dumps(s["best_xfade"])))
    return lines


def compare(before, after):
    lines = ["=" * 100, "P6 task-2 AUDIO COMPARISON  before -> after", "=" * 100]
    hdr = ("%-22s %-12s %12s %12s %10s" % ("metric", "file", "before", "after", "delta"))
    lines.append(hdr)
    lines.append("-" * 100)
    metrics = [
        ("peak_dbfs", "peak dBFS", "%.2f"),
        ("rms_dbfs", "RMS dBFS", "%.2f"),
        ("crest", "crest", "%.2f"),
        ("centroid_hz", "centroid Hz", "%.0f"),
        ("hf8k_ratio_pct", ">8k energy %", "%.2f"),
        ("harsh_2_6k_pct", "2-6k energy %", "%.2f"),
        ("hf_3_10k_kurtosis", "HF kurtosis", "%.2f"),
        ("hf_transients_per_s", "HF transients/s", "%.2f"),
        ("tonal_peak_db_2p5_6p5k", "tonal peak dB", "%.1f"),
        ("tonal_freq_hz", "tonal freq Hz", "%.0f"),
        ("max_sample_jump", "max sample jump", "%.4f"),
        ("clip_samples", "clip samples", "%d"),
        ("seam_jump", "loop seam jump", "%.6f"),
        ("seam_z", "seam z", "%.2f"),
        ("edge_step_db", "seam edge step dB", "%.2f"),
    ]
    for fname in FOCUS + [n for n in TARGET_FILES if n not in FOCUS]:
        b = before.get(fname, {})
        a = after.get(fname, {})
        if b.get("missing") or a.get("missing"):
            continue
        lines.append("[%s]" % fname)
        for key, label, fmt in metrics:
            if key == "seam_jump":
                bv, av = b["seam"]["jump"], a["seam"]["jump"]
            elif key == "seam_z":
                bv, av = b["seam"]["z_vs_sample_diff"], a["seam"]["z_vs_sample_diff"]
            elif key == "edge_step_db":
                bv, av = b["seam"]["edge_rms_step_db"], a["seam"]["edge_rms_step_db"]
            else:
                bv, av = b.get(key), a.get(key)
            if bv is None or av is None:
                continue
            dv = av - bv
            lines.append("  %-20s %-12s %12s %12s %10s"
                         % (label, "", fmt % bv, fmt % av,
                            ("%+.3f" % dv) if fmt != "%d" else ("%+d" % dv)))
        if fname in FOCUS:
            for bk in ("2k-4k", "4k-6k", "6k-8k", "2k-6k"):
                bv = b["band_dbfs"][bk]
                av = a["band_dbfs"][bk]
                lines.append("  %-20s %-12s %12.2f %12.2f %+10.2f"
                             % ("band dBFS " + bk, "", bv, av, av - bv))
        # band table diff for focus files
        if fname in FOCUS:
            lines.append("  band energy %: before -> after")
            for k in b["band_pct"]:
                lines.append("    %-8s %8.2f -> %8.2f  (%+7.2f)" % (k, b["band_pct"][k], a["band_pct"][k],
                                                                    a["band_pct"][k] - b["band_pct"][k]))
    lines.append("")
    lines.append("JUDGEMENT (heuristic, headless metrics only; no listening test in CI):")
    for fname in FOCUS:
        b = before[fname]
        a = after[fname]
        ok_hf = a["hf8k_ratio_pct"] < b["hf8k_ratio_pct"] and a["hf8k_ratio_pct"] <= 2.0
        ok_harsh = a["harsh_2_6k_pct"] < b["harsh_2_6k_pct"]
        ok_seam = a["seam"]["jump"] <= max(3.0 * a["diff_mean"], 0.01) and abs(a["seam"]["edge_rms_step_db"]) <= 1.5
        ok_tonal = a["tonal_peak_db_2p5_6p5k"] <= b["tonal_peak_db_2p5_6p5k"] or a["tonal_peak_db_2p5_6p5k"] <= 18.0
        lines.append("  %s: hf8k<=2%%:%s harsh_2-6k reduced:%s seam clean:%s tonal softened:%s"
                     % (fname, ok_hf, ok_harsh, ok_seam, ok_tonal))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["before", "after", "compare"], required=True)
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--outdir", default=OUTDIR)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    if args.phase in ("before", "after"):
        info = collect(args.dir)
        jp = os.path.join(args.outdir, "audio6_%s.json" % args.phase)
        tp = os.path.join(args.outdir, "audio6_analysis_%s.txt" % args.phase)
        with open(jp, "w", encoding="utf-8") as f:
            json.dump(info, f, ensure_ascii=False, indent=1)
        lines = fmt_report(info, "P6 task-2 AUDIO ANALYSIS (%s) dir=%s" % (args.phase, args.dir))
        with open(tp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("\n".join(lines))
        print("\njson=", jp)
        print("txt=", tp)
    else:
        bp = os.path.join(args.outdir, "audio6_before.json")
        ap_ = os.path.join(args.outdir, "audio6_after.json")
        with open(bp, encoding="utf-8") as f:
            before = json.load(f)
        with open(ap_, encoding="utf-8") as f:
            after = json.load(f)
        lines = compare(before, after)
        fp = os.path.join(args.outdir, "audio6_analysis.txt")
        with open(fp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("\n".join(lines))
        print("\nreport=", fp)


if __name__ == "__main__":
    main()
