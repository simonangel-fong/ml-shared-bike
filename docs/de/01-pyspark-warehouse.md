# PySpark Warehouse

[Back](../../README.md)

- [PySpark Warehouse](#pyspark-warehouse)
  - [Objective](#objective)
  - [Data Warehouse](#data-warehouse)
  - [phases](#phases)
  - [Development](#development)
    - [init spark](#init-spark)
    - [stage table](#stage-table)
    - [extract data](#extract-data)
    - [transform data](#transform-data)
    - [create warehouse](#create-warehouse)
    - [load data](#load-data)

---

## Objective

1. rebuild data warehouse in spark with SQL.
2. create etl
3. load 2019~2023 data
4. output fact and dimensions data.

reference:

- data warehouse via postgresql; same dataset;
- path: C:\Users\simon\OneDrive\Tech\Github\Project-Shared-Bike-OLAP\data-warehouse\postgresql
- sql script ready

source

- `data/raw/<year>/*.csv`

---

## Data Warehouse

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

## phases

| #   | Phase            | Description                             |
| --- | ---------------- | --------------------------------------- |
| 1   | init spark       | init spark with docker compose          |
| 2   | stage table      | create stage table                      |
| 3   | extract data     | extract data into stage table           |
| 4   | trasform data    | trasorm data in stage table             |
| 5   | create warehouse | create fact and dimension tables        |
| 6   | load data        | load data from stage table to warehouse |
| 7   | export data      | export warehouse and upload to s3       |

---

## Development

### init spark

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

Then open Jupyter at http://localhost:8888 (token `bikeshare`) and run

---

### stage table

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/02_stage_table.py
```

---

### extract data

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/03_extract.py
```

---

### transform data

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/04_transform.py
```

---

### create warehouse

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/05_create_warehouse.py
```

---

### load data

`dim_date` runs from the jupyter container: the calendar is built in the
driver with `holidays`, which is only installed in that image. It runs
`local[*]` — ~1,800 rows needs no cluster, and the executors run as a
different uid than this container.

```sh
docker compose -f spark/docker-compose.yml exec jupyter /usr/local/spark/bin/spark-submit --master local[*] /opt/jobs/06_load_dim_date.py
```

`dim_station` reads the full stage table, so it runs on the cluster.

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/07_load_dim_station.py
```

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/08_load_dim_bike.py
```

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/09_load_dim_user_type.py
```

```sh
docker compose -f spark/docker-compose.yml exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 /opt/jobs/10_load_fact_trip.py

```