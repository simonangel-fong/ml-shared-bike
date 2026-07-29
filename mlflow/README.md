# MLflow — experiment tracking

[Back](../docs/PLAN.md)

Tracking server for Phase 05. Independent of the Spark stack — separate compose file,
separate network, own lifecycle. Start it before running
[ml/train.ipynb](../ml/train.ipynb).

## Layout

| file                  | role                                              |
| --------------------- | ------------------------------------------------- |
| `docker-compose.yml`  | tracking server + Postgres backend store          |
| `Dockerfile.mlflow`   | official MLflow image plus the Postgres driver    |
| `.env.example`        | credentials and host port                         |
| `artifacts/`          | artifact store, bind-mounted (gitignored)         |

## Stores

| store    | backing                        | holds                                     |
| -------- | ------------------------------ | ----------------------------------------- |
| backend  | Postgres (`postgres-data` vol) | runs, params, metrics, tags, registry     |
| artifact | `./artifacts` bind mount       | models, figures, `metrics.json`, tables   |

The server runs with `--serve-artifacts`, so it proxies artifact uploads itself. The
training client only needs `MLFLOW_TRACKING_URI` — it never touches the artifact path
directly, which is what keeps the notebook working unchanged when this moves to S3 in a
later phase.

## Run

```bash
cp mlflow/.env.example mlflow/.env    # optional; defaults work as-is

docker compose -f mlflow/docker-compose.yml up -d --build

docker compose -f mlflow/docker-compose.yml down       # keeps run history
docker compose -f mlflow/docker-compose.yml down -v    # wipes it
```

| service    | URL                   |
| ---------- | --------------------- |
| MLflow UI  | http://localhost:5000 |

Postgres is not published to the host — only the server talks to it.

## What the training run logs

Experiment `bike-share-demand`. One run per model, plus one per baseline so the
leaderboard has a bar to compare against.

| run                        | logs                                                          |
| -------------------------- | ------------------------------------------------------------- |
| `baseline: <name>` (×5)    | test MAE / RMSE / R²                                          |
| `Ridge`                    | params, test metrics, model with signature                    |
| `hgb-grid-search`          | parent run; best params, best `val_MAE`                       |
| ↳ `hgb lr=… leaves=…` (×3) | per-candidate params, `val_MAE`, stopping iteration           |
| `HistGradientBoosting`     | params, test metrics, model, diagnostics, `metrics.json`      |

Every run carries the dataset context as params and tags — station subset, row counts per
split, split periods, feature list, excluded columns. A metric without its input contract
is not reproducible, and this project has three known upstream data defects that make the
contract load-bearing.

Grid candidates log `val_MAE` only. The 2023 test set is scored exactly once per model,
after tuning — logging test metrics per candidate would turn the holdout into a tuning
signal.

## Model registry

The final HGB run is registered as `bike-share-demand-hgb` with the alias `champion`,
**only if it beats the `lag_168h` baseline**. Load it downstream with:

```python
import mlflow.sklearn
model = mlflow.sklearn.load_model("models:/bike-share-demand-hgb@champion")
```

Aliases rather than stages — stages are deprecated in MLflow 2.x.

## Notes

- If the server is down the notebook still trains and writes `ml/artifacts/`; it prints a
  warning and skips tracking (`MLFLOW_ENABLED`).
- MLflow 3 serialises sklearn models with `skops`, which rejects unknown types on load.
  `HistGradientBoostingRegressor` pulls in `functools.partial` and
  `sklearn.utils.validation.check_array`, so the notebook passes them via
  `skops_trusted_types` — without it `log_model` raises `UntrustedTypesFoundException`.
- On a Windows `cp1252` console MLflow's "🏃 View run" line raises `UnicodeEncodeError`
  and aborts the run, so the notebook sets `MLFLOW_SUPPRESS_PRINTING_URL_TO_STDOUT`.
- Override the endpoint with `MLFLOW_TRACKING_URI` if you change `MLFLOW_PORT`.
- Client and server versions should stay on the same minor (v2.19) — see
  [ml/requirements.txt](../ml/requirements.txt).
