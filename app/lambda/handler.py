"""
The model is baked into the image and loaded once at import, so only a cold
start pays for it; warm invocations reuse the same object.

Routes:
    POST /forecast   {"station_id": 7000, "date": "2023-07-19", "hour": 17}
    POST /predict    all 17 features, as the model sees them
    GET  /stations   the station list and the year this build serves
Output:
    {"predictions": [4.9716]}

Predictions are clipped at zero to match train.py - a quantile fit can go
negative, and negative demand is not a stocking level.
"""

from __future__ import annotations

import json
import math
from datetime import date as date_cls
from datetime import datetime
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

HERE = Path(__file__).parent
MODEL_PATH = HERE / "model" / "model.joblib"
FEATURES_DIR = HERE / "features"

# The column order the ColumnTransformer was fitted on.
FEATURES = [
    "station_id",
    "season",
    "hour",
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
    "py_station_hour_weekday_mean",
    "py_station_month_mean",
]

# Ontario statutory holidays
HOLIDAYS = {
    # 2019-2022: observed in the training data
    "2019-01-01", "2019-02-18", "2019-04-19", "2019-05-20", "2019-07-01",
    "2019-09-02", "2019-10-14", "2019-12-25", "2019-12-26",
    "2020-01-01", "2020-02-17", "2020-04-10", "2020-05-18", "2020-07-01",
    "2020-09-07", "2020-10-12", "2020-12-25", "2020-12-26",
    "2021-01-01", "2021-02-15", "2021-04-02", "2021-05-24", "2021-07-01",
    "2021-09-06", "2021-10-11", "2021-12-25", "2021-12-26", "2021-12-27",
    "2021-12-28",
    "2022-01-01", "2022-01-03", "2022-02-21", "2022-04-15", "2022-05-23",
    "2022-07-01", "2022-09-05", "2022-10-10", "2022-12-25", "2022-12-26",
    # 2023: the year this build serves
    "2023-01-01", "2023-01-02", "2023-02-20", "2023-04-07", "2023-05-22",
    "2023-07-01", "2023-09-04", "2023-10-09", "2023-12-25", "2023-12-26",
}

PY_HOUR_WEEKDAY = json.loads((FEATURES_DIR / "py_hour_weekday.json").read_text())
PY_MONTH = json.loads((FEATURES_DIR / "py_month.json").read_text())
META = json.loads((FEATURES_DIR / "meta.json").read_text())

STATIONS = set(META["stations"])

_MODEL = None


def get_model():
    """Load the model once per container, on first use rather than on import.

    Lazy for two reasons. It keeps importing this module free of the model,
    which lets the feature parity test run anywhere - joblib is pickle based,
    so loading an artifact written by scikit-learn 1.4.2 under a newer sklearn
    raises on a compiled class it cannot find, and CI has no reason to install
    the exact training version just to check calendar arithmetic.

    It also moves a corrupt or missing artifact from an import error, which
    Lambda reports as an opaque init failure, to the first request, which
    reports what actually went wrong.
    """
    global _MODEL
    if _MODEL is None:
        _MODEL = joblib.load(MODEL_PATH)
    return _MODEL


def _season(month: int) -> str:
    if month in (12, 1, 2):
        return "winter"
    if month in (3, 4, 5):
        return "spring"
    if month in (6, 7, 8):
        return "summer"
    return "fall"


def build_features(station_id: int, day: date_cls, hour: int) -> dict:
    """Expand (station, date, hour) into the 17 columns the model expects.

    Mirrors the feature engineering the model was trained on. The cyclical
    encodings use the same periods as training - 24 for hour, 7 for weekday,
    12 for month - and getting one wrong here is silent, not loud.
    """
    month = day.month

    weekday = day.isoweekday() % 7 + 1
    week_of_year = day.isocalendar()[1]

    hw = PY_HOUR_WEEKDAY.get(
        f"{station_id}|{hour}|{weekday}", META["default_hour_weekday"]
    )
    mo = PY_MONTH.get(f"{station_id}|{month}", META["default_month"])

    return {
        "station_id": station_id,
        "season": _season(month),
        "hour": hour,
        "quarter": (month - 1) // 3 + 1,
        "month": month,
        "weekday": weekday,
        "week_of_year": week_of_year,
        "is_weekend": int(weekday in (1, 7)),  # Sunday=1, Saturday=7
        "is_holiday": int(day.isoformat() in HOLIDAYS),
        "hour_sin": round(math.sin(2 * math.pi * hour / 24), 6),
        "hour_cos": round(math.cos(2 * math.pi * hour / 24), 6),
        "weekday_sin": round(math.sin(2 * math.pi * weekday / 7), 6),
        "weekday_cos": round(math.cos(2 * math.pi * weekday / 7), 6),
        "month_sin": round(math.sin(2 * math.pi * month / 12), 6),
        "month_cos": round(math.cos(2 * math.pi * month / 12), 6),
        "py_station_hour_weekday_mean": hw,
        "py_station_month_mean": mo,
    }


def _parse_forecast(records: list[dict]) -> list[dict]:
    """Validate user-facing input and expand it. Raises ValueError on bad input."""
    out = []

    for rec in records:
        try:
            station_id = int(rec["station_id"])
            hour = int(rec["hour"])
            day = datetime.strptime(str(rec["date"]), "%Y-%m-%d").date()
        except KeyError as exc:
            raise ValueError(f"missing field: {exc.args[0]}") from exc
        except (TypeError, ValueError) as exc:
            raise ValueError(f"bad field: {exc}") from exc

        if station_id not in STATIONS:
            raise ValueError(f"unknown station_id: {station_id}")
        if not 0 <= hour <= 23:
            raise ValueError(f"hour must be 0-23, got {hour}")

        out.append(build_features(station_id, day, hour))

    return out


def _records(event) -> tuple[list[dict], str]:
    """Pull the payload and the route out of whichever envelope arrived."""
    path = ""
    payload = event

    if isinstance(event, dict):
        # API Gateway v2 puts the route here; direct invokes have neither.
        path = (
            event.get("rawPath")
            or event.get("requestContext", {}).get("http", {}).get("path", "")
            or ""
        )
        if "body" in event:
            body = event["body"]
            payload = json.loads(body) if isinstance(body, str) else body

    if isinstance(payload, dict):
        payload = payload.get("instances", [payload])

    if not isinstance(payload, list) or not payload:
        raise ValueError("body must be a record or a non-empty list of records")

    return payload, path


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):  # noqa: ARG001 - context is unused
    try:
        # GET /stations is what the front end fills its dropdown and date
        # bounds from, so it does not have to hardcode either.
        raw_path = ""
        if isinstance(event, dict):
            raw_path = (
                event.get("rawPath")
                or event.get("requestContext", {}).get("http", {}).get("path", "")
                or ""
            )
        if raw_path.endswith("/stations"):
            names = META.get("station_names", {})
            return _response(
                200,
                {
                    "stations": [
                        {"id": s, "name": names.get(str(s), str(s))}
                        for s in sorted(STATIONS)
                    ],
                    "target_year": META["target_year"],
                    "history_year": META["history_year"],
                },
            )

        records, path = _records(event)

        # Route on the path, but fall back to sniffing the payload so a direct
        # invoke (no path at all) still does the right thing.
        is_forecast = path.endswith("/forecast") or (
            not path.endswith("/predict") and "date" in records[0]
        )

        rows = _parse_forecast(records) if is_forecast else records
        frame = pd.DataFrame(rows)

        missing = [c for c in FEATURES if c not in frame.columns]
        if missing:
            return _response(400, {"error": f"missing features: {missing}"})

        preds = np.clip(get_model().predict(frame[FEATURES]), 0, None)

        return _response(
            200, {"predictions": [round(float(v), 4) for v in preds]}
        )

    except (ValueError, KeyError, TypeError) as exc:
        # A bad payload is the caller's problem, not a 500.
        return _response(400, {"error": str(exc)})
