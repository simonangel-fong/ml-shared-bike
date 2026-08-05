"""Feature parity check: what the handler derives must equal what was trained.

The handler rebuilds 15 of the 17 features from (station, date, hour). If that
arithmetic drifts from the upstream pipeline, nothing raises - the model simply
receives a plausible feature vector describing a different moment in time, and
returns a confident wrong answer.

Two conventions have already bitten here and are the reason this file exists:

  - weekday is Sunday=1..Saturday=7 (Spark), not python's Monday=0
  - is_holiday follows the pipeline's list, which omits the August civic
    holiday and Family Day in 2019

Run inside the serving image, against the real split:

    docker run --rm --entrypoint bash \\
      -v "$PWD/app/lambda:/app" -v "$PWD/ml/data/split/annual:/d" \\
      <image> -c "cd /app && python test_features.py /d/test.parquet"
"""

from __future__ import annotations

import sys
import warnings
from pathlib import Path

import pandas as pd

warnings.filterwarnings("ignore")

import handler  # noqa: E402 - after the warning filter on purpose

# The two prior-year columns are looked up, not derived, so they are checked
# separately - a table built from a different year is expected to differ.
DERIVED = [
    "season",
    "quarter",
    "month",
    "weekday",
    "week_of_year",
    "is_weekend",
    "is_holiday",
    "hour_sin",
    "hour_cos",
    "weekday_sin",
    "weekday_cos",
    "month_sin",
    "month_cos",
]

TOLERANCE = 1e-4


def main(path: str, sample: int = 2000) -> int:
    frame = pd.read_parquet(path).sample(sample, random_state=1)
    bad: dict[str, int] = {c: 0 for c in DERIVED}

    for _, row in frame.iterrows():
        built = handler.build_features(
            int(row.station_id), row.start_date.date(), int(row.hour)
        )
        for col in DERIVED:
            got, want = built[col], row[col]
            if isinstance(want, str):
                if got != want:
                    bad[col] += 1
            elif abs(float(got) - float(want)) > TOLERANCE:
                bad[col] += 1

    print(f"feature parity vs {Path(path).name}, {len(frame):,} rows\n")
    for col, count in bad.items():
        print(f"  {col:24s} {'ok' if count == 0 else f'{count} MISMATCH'}")

    total = sum(bad.values())
    print(f"\ntotal mismatches: {total}")
    return 1 if total else 0


if __name__ == "__main__":
    source = sys.argv[1] if len(sys.argv) > 1 else "/d/test.parquet"
    raise SystemExit(main(source))
