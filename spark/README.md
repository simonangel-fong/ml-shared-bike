# Spark — PySpark cluster

[Back](../docs/de/01-pyspark-warehouse.md)

## Layout

| file                         | role                                                        |
| ---------------------------- | ----------------------------------------------------------- |
| `docker-compose.yml`         | master + worker + jupyter driver                            |
| `jupyter/Dockerfile.jupyter` | driver image: pyspark-notebook plus project Python packages |
| `jupyter/requirements.txt`   | driver Python dependencies                                  |
| `jupyter/spark_session.py`   | `get_spark()` factory used by every notebook and script     |
| `jupyter/verify_spark.py`    | Phase 1 check: read one raw CSV, print the row count        |
| `.env.example`               | worker sizing and the Jupyter token                         |

Everything under `jupyter/` is baked into the driver image at build time, not
bind-mounted — edit those files and rebuild with `docker compose up -d --build`.

## Mounts

| host         | container        | notes                  |
| ------------ | ---------------- | ---------------------- |
| `data/`      | `/opt/data`      | all three services     |
| `notebooks/` | `/opt/notebooks` | driver only            |
| `jobs/`      | `/opt/jobs`      | master and worker only |

Warehouse root is `/opt/data/warehouse` (`data/warehouse/` on the host), tables
written as Parquet.

## Run

```bash
cd spark
cp .env.example .env
docker compose up -d --build
```

| service         | URL                                       |
| --------------- | ----------------------------------------- |
| Jupyter         | http://localhost:8888 (token `bikeshare`) |
| Spark master UI | http://localhost:8080                     |
| Worker UI       | http://localhost:8081                     |
| Application UI  | http://localhost:4040 (while a job runs)  |

## Verify

```bash
docker compose exec jupyter python /home/jovyan/verify_spark.py
```

Expected: the Spark version, the first raw CSV path, its row count and columns,
then a Parquet write/read round trip proving the warehouse mount is writable.

## Use from a notebook

```python
from spark_session import get_spark, RAW_DIR, table_path

spark = get_spark("stage_trips")
df = spark.read.csv(f"{RAW_DIR}/2025/*.csv", header=True)
df.write.mode("overwrite").parquet(table_path("stage_trips"))
```

`spark_session.py` is on `PYTHONPATH` via `/home/jovyan`, so the import works
from any notebook without a path fix-up.

## Stop

```bash
docker compose down        # keep data/
docker compose down -v     # also drop anonymous volumes
```

## Notes

- Cluster and driver both pin Spark 3.5.0. They must match exactly — a driver
  on a different patch version than the executors fails in confusing ways.
- The images are `apache/spark`, not `bitnami/spark`: Bitnami moved its free
  catalog to `bitnamilegacy/` in 2025 and `bitnami/spark:3.5` no longer pulls.
  Master and worker therefore need explicit `spark-class` commands rather than
  Bitnami's `SPARK_MODE` entrypoint.
- The driver runs in the `jupyter` service, not on the master, so executors must
  be able to call back to it. The container's `hostname` is `spark-jupyter`,
  while `spark_session.py` defaults `spark.driver.host` to `jupyter`; set
  `SPARK_DRIVER_HOST=spark-jupyter` if executors cannot reach the driver.
- `spark.sql.sources.partitionOverwriteMode=dynamic` is set so Phase 3 reruns
  overwrite only the partitions they touch.
- `spark.sql.legacy.timeParserPolicy=CORRECTED` keeps the mixed 2019–2023 /
  2024–2025 timestamp formats from aborting a read.
- Session timezone is `America/Toronto`, matching the source data.
- Worker sizing lives in `.env`; raise `SPARK_WORKER_MEMORY` before running the
  full 2019–2025 load.

```

```
