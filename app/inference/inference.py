"""Serving handler for the annual-demand quantile model.

Runs inside the SageMaker sklearn container behind the serverless endpoint.
The container's default handler cannot load model.skops - it expects a pickle -
so all four hooks are overridden here.

Input (application/json), one record or a list of them:

    {"station_id": 7000, "season": "summer", "hour": 17, ...}

Every feature in split.json must be present; the model is a fitted
ColumnTransformer and a missing column is a 500, not a silent zero.

Output:

    {"predictions": [12.4]}

Predictions are clipped at zero to match train.py - a quantile fit can go
negative, and negative demand is not a stocking level.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd
import skops.io as sio

CONTENT_TYPE = "application/json"

# The column order the ColumnTransformer was fitted on. Kept literal rather
# than read from split.json: the endpoint ships the model, not the split.
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


def model_fn(model_dir: str):
    """Load model.skops from the extracted model.tar.gz."""
    path = Path(model_dir) / "model.skops"

    # skops refuses unknown types by default. The artifact is written by our own
    # training job into our own bucket, so its own types are the trusted set.
    untrusted = sio.get_untrusted_types(file=path)
    if untrusted and os.environ.get("SKOPS_TRUST_ALL", "true").lower() != "true":
        raise ValueError(f"untrusted types in {path}: {untrusted}")

    return sio.load(path, trusted=untrusted)


def input_fn(body: str, content_type: str = CONTENT_TYPE) -> pd.DataFrame:
    """JSON record or list of records -> feature frame in fitted column order."""
    if content_type != CONTENT_TYPE:
        raise ValueError(f"unsupported content type: {content_type}")

    payload = json.loads(body)

    # Accept the bare record, a list, and {"instances": [...]} so the API
    # gateway mapping can stay a passthrough.
    if isinstance(payload, dict):
        payload = payload.get("instances", [payload])
    if not isinstance(payload, list) or not payload:
        raise ValueError("body must be a record or a non-empty list of records")

    frame = pd.DataFrame(payload)

    missing = [c for c in FEATURES if c not in frame.columns]
    if missing:
        raise ValueError(f"missing features: {missing}")

    return frame[FEATURES]


def predict_fn(frame: pd.DataFrame, model):
    return np.clip(model.predict(frame), 0, None)


def output_fn(prediction, accept: str = CONTENT_TYPE) -> tuple[str, str]:
    if accept not in (CONTENT_TYPE, "*/*"):
        raise ValueError(f"unsupported accept type: {accept}")

    body = json.dumps({"predictions": [round(float(v), 4) for v in prediction]})
    return body, CONTENT_TYPE
