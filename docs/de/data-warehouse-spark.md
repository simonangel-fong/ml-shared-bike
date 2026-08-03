# Data Warehouse (Spark)

[Back](../../README.md)

- [Data Warehouse (Spark)](#data-warehouse-spark)
  - [Data Warehouse Design](#data-warehouse-design)
  - [Development](#development)
    - [Download raw data](#download-raw-data)
    - [Init spark](#init-spark)
    - [Create stage table](#create-stage-table)
    - [Extract data](#extract-data)
    - [Transform data](#transform-data)
    - [Create data warehouse](#create-data-warehouse)
    - [Load data](#load-data)
    - [Export data](#export-data)
  - [Archive to S3](#archive-to-s3)
  - [Clean up](#clean-up)

---

## Data Warehouse Design

- Table: `dim_date`
  - ~1,825 rows (2019-01-01 → 2023-12-31)

| Col                 | Type    | Desc                                      |
| ------------------- | ------- | ----------------------------------------- |
| dim_date_id         | DATE    | PK, the calendar date itself              |
| dim_date_year       | INT     | 2019–2023                                 |
| dim_date_quarter    | INT     | 1–4                                       |
| dim_date_month      | INT     | 1–12                                      |
| dim_date_day        | INT     | 1–31                                      |
| dim_date_week       | INT     | ISO week, 1–53                            |
| dim_date_weekday    | INT     | 1–7, Sunday-first (Spark dayofweek)       |
| dim_date_is_weekend | BOOLEAN | weekday in (1,7)                          |
| dim_date_is_holiday | BOOLEAN | Ontario holidays via the holidays package |
| dim_date_season     | STRING  | winter/spring/summer/fall                 |

- Table: `dim_station`

| Col              | Type   | Desc                             |
| ---------------- | ------ | -------------------------------- |
| dim_station_id   | INT    | PK, natural key from source      |
| dim_station_name | STRING | latest name seen for the station |

- Table: `dim_bike`

| Col            | Type   | Desc                        |
| -------------- | ------ | --------------------------- |
| dim_bike_id    | INT    | PK, natural key from source |
| dim_bike_model | STRING | UNKNOWN for 2019–2023       |

- Table: `dim_user_type`

| Col                | Type   | Desc               |
| ------------------ | ------ | ------------------ |
| dim_user_type_id   | INT    | PK, surrogate 1..n |
| dim_user_type_name | STRING | annual / casual    |

- Table: `fact_trip`
  - ~18,920,187 rows
  - partitioned by start_year, start_month

| Col                        | Type      | Desc                 |
| -------------------------- | --------- | -------------------- |
| fact_trip_id               | BIGINT    | PK, surrogate        |
| fact_trip_source_id        | INT       | source trip_id       |
| fact_trip_duration         | INT       | seconds              |
| fact_trip_start_ts         | TIMESTAMP | full start timestamp |
| fact_trip_end_ts           | TIMESTAMP | full end timestamp   |
| fact_trip_start_date_id    | DATE      | → dim_date           |
| fact_trip_end_date_id      | DATE      | → dim_date           |
| fact_trip_start_hour       | INT       | 0–23                 |
| fact_trip_start_minute     | INT       | 0–59                 |
| fact_trip_end_hour         | INT       | 0–23                 |
| fact_trip_end_minute       | INT       | 0–59                 |
| fact_trip_start_station_id | INT       | → dim_station        |
| fact_trip_end_station_id   | INT       | → dim_station        |
| fact_trip_bike_id          | INT       | → dim_bike           |
| fact_trip_user_type_id     | INT       | → dim_user_type      |
| start_year                 | INT       | partition key        |
| start_month                | INT       | partition key        |

---

## Development

### Download raw data

```sh
# download raw data to data/raw
python download-raw.py
```

---

### Init spark

```sh
# spin up
docker compose -f spark/docker-compose.yml up -d --build

# confirm
docker compose -f spark/docker-compose.yml ps
# NAME             IMAGE                COMMAND                  SERVICE          CREATED          STATUS                            PORTS
# spark-jupyter    spark-jupyter        "tini -g -- start.sh…"   jupyter          11 seconds ago   Up 4 seconds (health: starting)   0.0.0.0:4040->4040/tcp, [::]:4040->4040/tcp, 0.0.0.0:7078-7079->7078-7079/tcp, [::]:7078-7079->7078-7079/tcp, 0.0.0.0:8888->8888/tcp, [::]:8888->8888/tcp
# spark-master     apache/spark:3.5.0   "/opt/entrypoint.sh …"   spark-master     11 seconds ago   Up 10 seconds (healthy)           0.0.0.0:7077->7077/tcp, [::]:7077->7077/tcp, 0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
# spark-worker-1   apache/spark:3.5.0   "/opt/entrypoint.sh …"   spark-worker-1   11 seconds ago   Up 4 seconds (health: starting)   0.0.0.0:8081->8081/tcp, [::]:8081->8081/tcp
# spark-worker-2   apache/spark:3.5.0   "/opt/entrypoint.sh …"   spark-worker-2   11 seconds ago   Up 4 seconds (health: starting)   0.0.0.0:8082->8081/tcp, [::]:8082->8081/tcp
```

Then open Jupyter at http://localhost:8888 (token `bikeshare`) and run the jobs below.

---

### Create stage table

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/02_stage_table.py
```

---

### Extract data

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/03_extract.py
```

---

### Transform data

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/04_transform.py
```

---

### Create data warehouse

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/05_create_warehouse.py
```

---

### Load data

`dim_date` runs from the jupyter container: the calendar is built in the
driver with `holidays`, which is only installed in that image. It runs on
`local[*]` — ~1,800 rows need no cluster, and the executors run as a
different uid from this container.

```sh
# dim_date: runs on jupyter container
docker compose -f spark/docker-compose.yml exec jupyter /usr/local/spark/bin/spark-submit --master local[*] /opt/jobs/06_load_dim_date.py

# dim_station
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/07_load_dim_station.py

# dim_bike
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/08_load_dim_bike.py

# dim_user
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/09_load_dim_user_type.py

# fact_trip
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/10_load_fact_trip.py
```

---

### Export data

All five tables are written to `data/export/` as parquet, with partitioning
preserved. The same files back up the warehouse, feed feature engineering and
training from `fact_trip`, and serve station and user-type lookups to the app.

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/11_export.py
```

- `data/export/`
  - `dim_bike/`
  - `dim_date/`
  - `dim_station/`
  - `dim_user_type/`
  - `fact_trip/`

---

## Archive to S3

```sh
aws s3 cp data/export s3://toronto-shared-bike-data-warehouse-data-bucket/warehouse --recursive
```

---

## Clean up

```sh
docker compose -f spark/docker-compose.yml down -v
```
