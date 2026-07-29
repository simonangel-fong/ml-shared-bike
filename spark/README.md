# Spark — PySpark cluster

[Back](../docs/de/01-pyspark-warehouse.md)

## Layout

| file                         | role                                                        |
| ---------------------------- | ----------------------------------------------------------- |
| `docker-compose.yml`         | master + worker + jupyter driver                            |
| `jupyter/Dockerfile.jupyter` | driver image: pyspark-notebook plus project Python packages |
| `jupyter/requirements.txt`   | driver Python dependencies                                  |
| `.env.example`               | worker sizing and the Jupyter token                         |

Everything under `jupyter/` is baked into the driver image at build time, not
bind-mounted — edit those files and rebuild with `docker compose up -d --build`.

The Spark session is built in the notebooks themselves — see
[warehouse.ipynb](../notebooks/warehouse.ipynb), which connects to
`spark://spark-master:7077` and sets `spark.driver.host` to `spark-jupyter`
so executors can route results back to the driver container.

## Mounts

| host         | container           | notes                  |
| ------------ | ------------------- | ---------------------- |
| `data/`      | `/opt/data`         | all three services     |
| `notebooks/` | `/home/jovyan/work` | driver only            |
| `jobs/`      | `/opt/jobs`         | master and worker only |

Warehouse root is `/opt/data/warehouse` (`data/warehouse/` on the host), tables
written as Parquet.

## Run

```bash
cd spark
docker compose up -d --build

docker compose down -v
```

| service         | URL                                       |
| --------------- | ----------------------------------------- |
| Jupyter         | http://localhost:8888 (token `bikeshare`) |
| Spark master UI | http://localhost:8080                     |
| Worker UI       | http://localhost:8081                     |
| Application UI  | http://localhost:4040 (while a job runs)  |
