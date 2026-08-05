"""Build the prior-year lookup tables the API needs.

The model takes 17 features, but a caller only knows station, date and hour.
Fifteen of the rest are calendar arithmetic; two are not:

    py_station_hour_weekday_mean(Y) = mean trip_count of year Y-1,
                                      keyed on (station_id, hour, weekday)
    py_station_month_mean(Y)        = mean trip_count of year Y-1,
                                      keyed on (station_id, month)

Verified against the training data: recomputing them this way reproduces the
stored values exactly (corr 1.000000, max abs diff 0.0).

Source is ml/data/split/annual/test.parquet - the curated 2022 split, which is
exactly the 73 stations in the model's station_pool. The raw featured/year=2022
data is the wrong input: it holds 76 stations and is missing 14 of the pool.

    python app/lambda/build_features.py

Writes app/lambda/features/*.json, which the Dockerfile bakes into the image.
Rerun when the model is retrained on a later year.
"""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

REPO = Path(__file__).resolve().parent.parent.parent
SOURCE = REPO / "ml" / "data" / "split" / "annual" / "test.parquet"
STATIONS = REPO / "data" / "export" / "dim_station"
OUT = Path(__file__).resolve().parent / "features"

# The year the source data covers. Predictions for TARGET_YEAR use it as
# history, so this is HISTORY_YEAR and the api serves HISTORY_YEAR + 1.
HISTORY_YEAR = 2022


def main() -> None:
    df = pd.read_parquet(SOURCE)
    OUT.mkdir(parents=True, exist_ok=True)

    # Keys are strings because JSON has no tuple key; the handler joins on "|".
    hw = (
        df.groupby(["station_id", "hour", "weekday"])["trip_count"]
        .mean()
        .round(6)
    )
    hw_map = {f"{s}|{h}|{w}": v for (s, h, w), v in hw.items()}

    mo = df.groupby(["station_id", "month"])["trip_count"].mean().round(6)
    mo_map = {f"{s}|{m}": v for (s, m), v in mo.items()}

    stations = sorted(int(s) for s in df.station_id.unique())

    # Names come from the warehouse dimension, which covers 856 stations - only
    # the model's pool is kept. Served by the api so the page does not carry a
    # second copy that can drift from the pool.
    dim = pd.read_parquet(next(STATIONS.glob("*.parquet")))
    names = dict(
        zip(
            dim.dim_station_id.astype(int),
            dim.dim_station_name.str.replace(r"\s+", " ", regex=True).str.strip(),
        )
    )
    unnamed = [s for s in stations if s not in names]
    if unnamed:
        raise SystemExit(f"no name for stations: {unnamed}")

    meta = {
        "history_year": HISTORY_YEAR,
        "target_year": HISTORY_YEAR + 1,
        "stations": stations,
        "station_names": {str(s): names[s] for s in stations},
        # Fallbacks for a key the tables do not hold. Better than 0, which the
        # model would read as a station that saw no trips at all.
        "default_hour_weekday": round(float(df.trip_count.mean()), 6),
        "default_month": round(float(df.trip_count.mean()), 6),
    }

    for name, obj in [
        ("py_hour_weekday.json", hw_map),
        ("py_month.json", mo_map),
        ("meta.json", meta),
    ]:
        path = OUT / name
        path.write_text(json.dumps(obj, separators=(",", ":")))
        print(f"{name:24s} {len(obj):>6,} keys  {path.stat().st_size / 1024:7.1f} KB")

    print(f"\nstations: {len(stations)}  history: {HISTORY_YEAR}  serves: {HISTORY_YEAR + 1}")


if __name__ == "__main__":
    main()
