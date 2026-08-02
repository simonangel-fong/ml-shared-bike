# PySpark Warehouse

[Back](../../README.md)

- [PySpark Warehouse](#pyspark-warehouse)
  - [Objective](#objective)
  - [phases](#phases)
  - [Development](#development)
    - [init spark](#init-spark)
    - [stage table](#stage-table)
    - [extract data](#extract-data)

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