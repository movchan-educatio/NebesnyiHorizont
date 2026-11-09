#!/usr/bin/env python3
"""Extract simulator-relevant metrics from Betaflight Blackbox logs.

This is intentionally a small, dependency-light adapter: install orangebox
(pure Python BBL parser), then point it at real .bbl/.bfl files.

Example:
  python tools/analyze_betaflight_log.py \
      --out qa_shots/physics/real_logs.csv \
      C:/logs/oscar_5inch.bbl C:/logs/ar8.bbl

The output is not a full blackbox analysis.  It extracts the numbers the
flight model needs: cell count, throttle range, current/voltage envelope,
estimated pack resistance and a hover-throttle estimate when baro altitude is
logged.
"""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from pathlib import Path

try:
    from orangebox import Parser
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Install orangebox first: python -m pip install orangebox") from exc


def _decode_vbat(raw: float, scale: float = 110.0) -> float:
    # Betaflight blackbox-tools: vbatADC * 3.3 * 10 * vbatscale / 4095
    return raw * 33.0 * 10.0 * scale / 4095.0 / 1000.0


def _safe_median(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def _percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def _linear_resistance(points: list[tuple[float, float]]) -> float:
    """Estimate pack resistance from (current, voltage) samples.

    A plain regression over a whole flight is biased by the pack discharging.
    Instead, use short local windows and keep only the negative dV/dI slopes
    from current steps.  This is still an estimate, not a lab measurement.
    """
    slopes: list[float] = []
    # points are ordered by time; compare samples ~0.2-1.5 s apart
    for i in range(1, len(points) - 1):
        i0 = max(0, i - 20)
        i1 = min(len(points) - 1, i + 20)
        i_a, v_a = points[i0]
        i_b, v_b = points[i1]
        di = i_b - i_a
        if abs(di) < 8.0:
            continue
        slope = (v_b - v_a) / di
        if -0.25 < slope < 0.0:
            slopes.append(-slope)
    return _safe_median(slopes)


def analyze(path: Path, cells_override: int = 0) -> dict[str, object] | None:
    parser = Parser.load(str(path))
    names = parser.field_names
    rows: list[dict[str, float]] = []
    for frame in parser.frames():
        rows.append(dict(zip(names, frame.data)))
    if not rows:
        return None

    vbat_scale = float(parser.headers.get("vbat_scale", 110))
    current_info = parser.headers.get("currentSensor") or [0, 0]
    current_scale = float(current_info[1]) if len(current_info) > 1 else 0.0

    voltages = [_decode_vbat(float(r.get("vbatLatest", 0)), vbat_scale) for r in rows]
    positive_v = [v for v in voltages if v > 1.0]
    max_v = max(positive_v) if positive_v else 0.0
    has_vbat = max_v > 1.0
    # Cell count is ambiguous when the pack is not fully charged (a 4S at
    # storage voltage looks like a full 3S).  Allow a manual override.
    if cells_override > 0:
        cells = cells_override
    elif has_vbat:
        cells = max(1, int(round(max_v / 4.2)))
    else:
        cells = 0
    valid_v = [v for v in voltages if cells > 0 and cells * 2.5 < v < cells * 4.35]

    throttle = [float(r.get("rcCommand[3]", 0)) for r in rows]
    throttle_pct = [max(0.0, min(1.0, (t - 1000.0) / 1000.0)) for t in throttle]
    currents: list[float] = []
    if current_scale > 0:
        currents = [max(0.0, float(r.get("amperageLatest", 0)) / current_scale) for r in rows]

    # Hover estimate from baro vertical speed when available.  BaroAlt is in
    # centimetres in Betaflight logs, not metres.
    hover_samples: list[float] = []
    hover_source = "throttle_median"
    if "BaroAlt" in names:
        alts = [float(r["BaroAlt"]) / 100.0 for r in rows]
        times = [float(r["time"]) / 1e6 for r in rows]
        for i in range(2, len(rows) - 2):
            dt = times[i + 1] - times[i - 1]
            if dt <= 0.001:
                continue
            vz = (alts[i + 1] - alts[i - 1]) / dt
            if abs(vz) < 0.35 and abs(throttle[i] - throttle[i - 1]) < 8:
                hover_samples.append(throttle_pct[i])
    if len(hover_samples) >= 10:
        hover_pct = _safe_median(hover_samples)
        hover_source = "baro"
    else:
        hover_pct = _safe_median(throttle_pct)

    pairs = [(currents[i], valid_v[i]) for i in range(min(len(currents), len(valid_v)))]
    resistance = _linear_resistance(pairs) if len(pairs) > 20 else 0.0
    if resistance < 0.001:
        resistance = 0.0

    return {
        "log": path.name,
        "craft": str(parser.headers.get("Craft name", "")),
        "firmware": str(parser.headers.get("Firmware revision", "")),
        "cells": cells,
        "frames": len(rows),
        "duration_s": round((float(rows[-1].get("time", 0)) - float(rows[0].get("time", 0))) / 1e6, 2),
        "throttle_median_pct": round(_safe_median(throttle_pct) * 100.0, 1),
        "throttle_p95_pct": round(_percentile(throttle_pct, 0.95) * 100.0, 1),
        "throttle_max_pct": round(max(throttle_pct) * 100.0, 1),
        "hover_pct": round(hover_pct * 100.0, 1),
        "hover_source": hover_source,
        "volt_max": round(max(valid_v) if valid_v else 0.0, 2),
        "volt_min": round(min(valid_v) if valid_v else 0.0, 2),
        "amp_max": round(max(currents) if currents else 0.0, 1),
        "amp_p95": round(_percentile(currents, 0.95), 1),
        "pack_resistance_ohm": round(resistance, 4),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--out", default="qa_shots/physics/real_logs.csv")
    parser.add_argument("--cells", default="",
                        help="optional comma-separated cell counts, one per log "
                             "(e.g. 4,4,6); use when a storage-voltage pack is ambiguous")
    args = parser.parse_args()
    cell_overrides = [int(x) for x in args.cells.split(",") if x.strip().isdigit()] if args.cells else []

    results = []
    for index, path in enumerate(args.logs):
        try:
            override = cell_overrides[index] if index < len(cell_overrides) else 0
            result = analyze(path, override)
            if result:
                results.append(result)
                print("[log]", result)
        except Exception as exc:  # noqa: BLE001 - report the bad log, keep going
            print(f"[log] FAILED {path}: {exc}")

    if not results:
        return 2
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(results[0].keys()))
        writer.writeheader()
        writer.writerows(results)
    print(f"[log] CSV -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
