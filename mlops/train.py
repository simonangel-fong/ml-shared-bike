"""Train the annual quantile demand model.

Port of ml/notebooks/05-train-quantile.ipynb steps 1-3. Runs unchanged locally
and inside a SageMaker training job.

    python mlops/train.py --quantile 0.8

Reference (test 2022, q80), matching the notebook to four decimals:

    MAE 1.0452 | MAE_peak 1.5513 | MAE_busy 6.9058
    under_rate_busy 1.0 | shortfall_busy 0.5631 | pinball 0.3248
    over_supply 0.8523
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import skops.io as sio
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

# Used when the SM_* variables are absent, i.e. running from a laptop.
REPO = Path(__file__).resolve().parent.parent
LOCAL_SPLIT = REPO / "ml" / "data" / "split" / "annual"
LOCAL_OUT = REPO / "mlops" / "output"

# From the annual sweep winner. Changing these invalidates the reference metrics.
BASE = {
    "learning_rate": 0.05,
    "max_leaf_nodes": 127,
    "max_iter": 600,
    "max_features": 0.7,
    "early_stopping": False,
    "random_state": 0,
}


def parse_args() -> argparse.Namespace:
    """Hyperparameters arrive as flags, channel paths as SM_* env vars."""
    p = argparse.ArgumentParser(description=__doc__)

    p.add_argument(
        "--quantile",
        type=float,
        default=0.8,
        help="quantile to fit; 0.8 is the shipped model",
    )
    p.add_argument(
        "--split-dir",
        type=Path,
        default=Path(os.environ.get("SM_CHANNEL_SPLIT", LOCAL_SPLIT)),
        help="directory holding split.json and the parquet files",
    )
    p.add_argument(
        "--model-dir",
        type=Path,
        default=Path(os.environ.get("SM_MODEL_DIR", LOCAL_OUT)),
        help="where model.skops, model.joblib and metrics.json are written",
    )

    args = p.parse_args()

    if not 0 < args.quantile < 1:
        p.error(f"--quantile must be in (0, 1), got {args.quantile}")
    if not args.split_dir.is_dir():
        p.error(f"--split-dir does not exist: {args.split_dir}")

    return args


def build(**overrides) -> Pipeline:
    """One-hot the season, pass everything else through, then boost."""
    return Pipeline([
        ("prep", ColumnTransformer(
            [("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False),
              ["season"])],
            remainder="passthrough",
        )),
        ("model", HistGradientBoostingRegressor(**{**BASE, **overrides})),
    ])


def pinball(y_true, y_pred, q):
    d = y_true - y_pred
    return float(np.mean(np.maximum(q * d, (q - 1) * d)))


def evaluate(y_true, y_pred, hours, peak_hours, busy_threshold, q=0.5):
    """Business metrics from the notebook - MAE cannot judge a quantile model."""
    y_pred = np.clip(np.asarray(y_pred, dtype=float), 0, None)
    y_true = np.asarray(y_true, dtype=float)
    busy = y_true >= busy_threshold
    peak = np.isin(hours, peak_hours)
    return {
        "MAE": mean_absolute_error(y_true, y_pred),
        "MAE_peak": mean_absolute_error(y_true[peak], y_pred[peak]),
        "MAE_busy": mean_absolute_error(y_true[busy], y_pred[busy]),
        "under_rate_busy": float((y_pred[busy] < y_true[busy]).mean()),
        "shortfall_busy": float(1 - y_pred[busy].sum() / y_true[busy].sum()),
        "pinball": pinball(y_true, y_pred, q),
        "over_supply": float(np.maximum(y_pred - y_true, 0).mean()),
    }


def load_split(split_dir: Path) -> tuple[dict, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Read the frozen annual split and its contract."""
    contract = json.loads((split_dir / "split.json").read_text())

    train = pd.read_parquet(split_dir / "train.parquet")
    val = pd.read_parquet(split_dir / "val.parquet")
    test = pd.read_parquet(split_dir / "test.parquet")

    # Overlapping splits give metrics that are meaningless but still plausible.
    assert train["start_date"].max() < val["start_date"].min(), "train/val overlap"
    assert val["start_date"].max() < test["start_date"].min(), "val/test overlap"

    missing = set(contract["features"] + [contract["target"]]) - set(train.columns)
    assert not missing, f"columns missing from train: {sorted(missing)}"

    return contract, train, val, test


def write_output(
    model_dir: Path,
    model: Pipeline,
    metrics: dict,
    contract: dict,
    quantile: float,
) -> None:
    """Write the fitted model and its scorecard.

    SageMaker tars model_dir to S3, so this is the whole deliverable. With no
    tracking server, metrics.json is the only run record.
    """
    model_dir.mkdir(parents=True, exist_ok=True)

    # skops is the archival format: it does not execute arbitrary code on load,
    # so it is what to keep for a model that outlives this container.
    sio.dump(model, model_dir / "model.skops")

    # joblib is what the endpoint loads. The serving image ships joblib but not
    # skops, and adding skops there means a requirements.txt that the endpoint
    # pip-installs as an unprivileged user - the install lands off sys.path and
    # the container fails with a misleading "No module named 'inference'".
    # Writing both keeps serving dependency-free at the cost of one extra file.
    joblib.dump(model, model_dir / "model.joblib")

    (model_dir / "metrics.json").write_text(
        json.dumps(
            {
                "model": f"annual-demand-q{int(quantile * 100)}",
                "quantile": quantile,
                "trained_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "params": BASE,
                "features": contract["features"],
                "target": contract["target"],
                "test_years": contract["test_years"],
                "metrics": metrics,
                "sklearn_version": sklearn.__version__,
            },
            indent=2,
        )
    )


def main() -> None:
    args = parse_args()

    print(f"quantile  q{int(args.quantile * 100)}")
    print(f"split     {args.split_dir}")
    print(f"model     {args.model_dir}")

    contract, train, val, test = load_split(args.split_dir)
    print(
        f"train {len(train):>9,} | val {len(val):>9,} | test {len(test):>9,}"
    )
    print(f"{len(contract['features'])} features -> {contract['target']}")

    features, target = contract["features"], contract["target"]

    model = build(loss="quantile", quantile=args.quantile)
    model.fit(train[features], train[target])
    print("fitted")

    # A quantile model can predict below zero; negative demand is not a
    # stocking level.
    preds = np.clip(model.predict(test[features]), 0, None)

    metrics = evaluate(
        test[target],
        preds,
        test["hour"],
        contract["peak_hours"],
        contract["busy_threshold"],
        args.quantile,
    )

    print(f"\ntest {contract['test_years'][0]}")
    for name, value in metrics.items():
        print(f"  {name:18} {value:.4f}")

    write_output(args.model_dir, model, metrics, contract, args.quantile)
    print(f"\nwrote model.skops and metrics.json to {args.model_dir}")


if __name__ == "__main__":
    main()
