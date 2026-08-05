"""Lambda handler for the annual-demand quantile model.

The model is baked into the image and loaded once at import, so only a cold
start pays for it; warm invocations reuse the same object.

Accepts either an API Gateway proxy event (the body is a JSON string) or a bare
record, so the same function can be invoked directly for testing and through
API Gateway in phase 3.

Input, one record or a list of them:

    {"station_id": 7000, "season": "summer", "hour": 17, ...}

Output:

    {"predictions": [4.9716]}

Predictions are clipped at zero to match train.py - a quantile fit can go
negative, and negative demand is not a stocking level.
"""

from __future__ import annotations

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

MODEL_PATH = Path(__file__).parent / "model" / "model.joblib"

# The column order the ColumnTransformer was fitted on. Kept literal rather than
# read from split.json: the image ships the model, not the split.
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

# Module scope on purpose: Lambda reuses the process across invocations, so this
# runs once per container rather than once per request.
MODEL = joblib.load(MODEL_PATH)


def _records(event) -> list[dict]:
    """Pull the payload out of whichever envelope it arrived in."""
    payload = event

    # API Gateway proxy integration delivers the request body as a string.
    if isinstance(payload, dict) and "body" in payload:
        body = payload["body"]
        payload = json.loads(body) if isinstance(body, str) else body

    if isinstance(payload, dict):
        payload = payload.get("instances", [payload])

    if not isinstance(payload, list) or not payload:
        raise ValueError("body must be a record or a non-empty list of records")

    return payload


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):  # noqa: ARG001 - context is unused
    try:
        frame = pd.DataFrame(_records(event))

        missing = [c for c in FEATURES if c not in frame.columns]
        if missing:
            return _response(400, {"error": f"missing features: {missing}"})

        preds = np.clip(MODEL.predict(frame[FEATURES]), 0, None)

        return _response(
            200, {"predictions": [round(float(v), 4) for v in preds]}
        )

    except (ValueError, KeyError, TypeError) as exc:
        # A bad payload is the caller's problem, not a 500.
        return _response(400, {"error": str(exc)})
