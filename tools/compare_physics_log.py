#!/usr/bin/env python3
"""Compare our physics bench CSV with a real-flight telemetry CSV.

The simulator bench writes qa_shots/physics/physics_bench.csv with one row per
preset.  A real log can be a Betaflight blackbox export or a hand-made CSV that
has the same key columns (preset/name + the metric columns you measured).

Usage:
  python tools/compare_physics_log.py \
      --bench qa_shots/physics/physics_bench.csv \
      --real  qa_shots/physics/real_5inch.csv \
      --tolerance 0.15

Only metrics present in both files are compared.  Exit code 1 means at least
one metric is outside the tolerance, which makes this usable in CI.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

METRICS = [
    ("physical_twr", "TWR"),
    ("hover_pct", "hover %"),
    ("spool90_s", "0-90% spool, s"),
    ("brake10_s", "90-10% brake, s"),
    ("sag_factor", "sag factor"),
    ("ge_2cm", "ground effect 2 cm"),
    ("ge_10cm", "ground effect 10 cm"),
    ("ge_30cm", "ground effect 30 cm"),
]


def read_rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows: dict[str, dict[str, str]] = {}
        for row in reader:
            key = (row.get("preset") or row.get("name") or "").strip()
            if key:
                rows[key] = row
        return rows


def as_float(row: dict[str, str], key: str) -> float | None:
    raw = (row.get(key) or "").strip()
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", default="qa_shots/physics/physics_bench.csv")
    parser.add_argument("--real", required=True)
    parser.add_argument("--tolerance", type=float, default=0.15,
                        help="allowed relative error, default 0.15 = 15%%")
    parser.add_argument("--out", default="", help="optional CSV report path")
    args = parser.parse_args()

    bench_path = Path(args.bench)
    real_path = Path(args.real)
    if not bench_path.exists():
        print(f"[compare] missing bench file: {bench_path}", file=sys.stderr)
        return 2
    if not real_path.exists():
        print(f"[compare] missing real log: {real_path}", file=sys.stderr)
        return 2

    bench = read_rows(bench_path)
    real = read_rows(real_path)
    shared = [key for key in bench if key in real]
    if not shared:
        print("[compare] no matching preset/name keys", file=sys.stderr)
        return 2

    report: list[list[str]] = []
    failures = 0
    print(f"{'preset':<10} {'metric':<20} {'bench':>10} {'real':>10} {'delta':>9}  result")
    for key in shared:
        for column, label in METRICS:
            b = as_float(bench[key], column)
            r = as_float(real[key], column)
            if b is None or r is None:
                continue
            denominator = max(abs(b), abs(r), 1e-9)
            delta = abs(b - r) / denominator
            ok = delta <= args.tolerance
            if not ok:
                failures += 1
            report.append([key, column, f"{b:.4f}", f"{r:.4f}",
                           f"{delta:.1%}", "PASS" if ok else "FAIL"])
            print(f"{key:<10} {label:<20} {b:>10.4f} {r:>10.4f} {delta:>8.1%}  "
                  f"{'PASS' if ok else 'FAIL'}")

    if not report:
        print("[compare] no shared numeric metrics", file=sys.stderr)
        return 2

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["preset", "metric", "bench", "real", "delta", "result"])
            writer.writerows(report)
        print(f"[compare] report -> {out_path}")

    print(f"[compare] {len(report) - failures}/{len(report)} metrics within "
          f"{args.tolerance:.0%}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
