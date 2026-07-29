# PySpark Warehouse

[Back](../../README.md)

- [PySpark Warehouse](#pyspark-warehouse)
  - [Objective](#objective)
  - [Source Data](#source-data)
  - [Phase 1 — Deploy PySpark with Docker](#phase-1--deploy-pyspark-with-docker)
  - [Phase 2 — Create Warehouse](#phase-2--create-warehouse)
    - [stage\_trips](#stage_trips)
    - [dim\_station](#dim_station)
    - [dim\_user](#dim_user)
    - [fact\_trips](#fact_trips)
  - [Phase 3 — ETL](#phase-3--etl)
    - [Extract](#extract)
    - [Transform](#transform)
    - [Load](#load)
    - [Validation](#validation)
  - [Phase 4 — ML Dataset](#phase-4--ml-dataset)
  - [Phase 5 — Split Dataset](#phase-5--split-dataset)
  - [Development](#development)

---

## Objective

Build a star-schema warehouse on PySpark that turns raw trip CSVs into an hourly
station-level dataset for the demand model defined in [01-problem.md](../ml/01-problem.md).

Grain of the fact table: **one row per trip**.
Grain of the ML output: **one row per station per hour**.

---

## Source Data

`data/raw/<year>/*.csv`. The full archive spans 2019–2025 in two header variants:

| years     | header style                                                                               | extra column | time format           |
| --------- | ------------------------------------------------------------------------------------------ | ------------ | --------------------- |
| 2019–2023 | `Trip Id`, `Trip  Duration` (space-separated, double space in duration, BOM on most files) | —            | `dd/MM/yyyy HH:mm`    |
| 2024–2025 | `Trip_Id`, `Trip_Duration` (underscore)                                                    | `Bike_Model` | `yyyy-MM-dd HH:mm:ss` |

Normalization rule: lowercase, collapse whitespace/underscores to `_`, strip BOM.
`bike_model` is kept as nullable — it is absent before 2024.

**Current scope: 2019–2020 only.** Both years use the space-separated header and
are **month-first** — `MM/dd/yyyy HH:mm`, not the `dd/MM` the table above claims.
Verified from the file boundaries: `2019-Q1.csv` ends at `03/31/2019` (there is
no 31st month) and each 2020 monthly file opens with its own month.

This matters because a day-first read fails silently in two ways at once: rows
with day > 12 give an invalid month and are dropped (~61% of the data), while
rows with day <= 12 parse to a real but wrong date. The transform therefore
asserts the result rather than trusting the format — every timestamp must land
in the year its folder claims, and the monthly distribution must not be flat
(a swap spreads days 1–31 across the twelve month buckets, which shows up as a
peak-to-trough ratio near 1).

Later years must each be verified the same way before being added to `YEARS`;
2024+ additionally use the underscore header and `yyyy-MM-dd HH:mm:ss`.

---

## Phase 1 — Deploy PySpark with Docker

- `docker-compose.yml` with a Spark master + worker and a Jupyter/PySpark driver.
- Mount `data/` and `notebooks/` into the container.
- Warehouse root at `data/warehouse/`, tables written as Parquet.
- Verify: the first cell of [warehouse.ipynb](../../notebooks/warehouse.ipynb)
  builds the session and runs a small job on the cluster.

Implemented in [spark/](../../spark/) — see its [README](../../spark/README.md)
for the run and verify commands.

| file                                                           | role                               |
| -------------------------------------------------------------- | ---------------------------------- |
| [docker-compose.yml](../../spark/docker-compose.yml)            | master + worker + jupyter driver   |
| [Dockerfile.jupyter](../../spark/jupyter/Dockerfile.jupyter)    | driver image                       |
| [warehouse.ipynb](../../notebooks/warehouse.ipynb)              | session setup and later phases     |

---

## Phase 2 — Create Warehouse

Layered layout:

```
raw (csv)  ->  stage_trips  ->  dim_* + fact_trips  ->  ml dataset
```

### stage_trips

Raw columns after header normalization, all read as `string` to avoid parse
failures; typing happens in the transform step.

| column             | type   | description                                             |
| ------------------ | ------ | ------------------------------------------------------- |
| trip_id            | string | source trip identifier                                  |
| trip_duration      | string | reported duration, seconds                              |
| start_station_id   | string | source start station id                                 |
| start_time         | string | raw start timestamp, mixed formats                      |
| start_station_name | string | source start station name                               |
| end_station_id     | string | source end station id                                   |
| end_time           | string | raw end timestamp, mixed formats                        |
| end_station_name   | string | source end station name                                 |
| bike_id            | string | source bike identifier                                  |
| user_type          | string | `Annual Member` / `Casual Member` / `Member` / `Casual` |
| bike_model         | string | 2024+ only, null otherwise                              |
| source_file        | string | lineage, e.g. `2025/bikeshare_2025_01.csv`              |

Partitioned by `source_year`.

### dim_station

| column       | type   | description                      |
| ------------ | ------ | -------------------------------- |
| station_id   | int    | primary key, from source id      |
| station_name | string | most recent name seen for the id |

Built from the distinct union of start and end stations. Where an id maps to
several names across years, the latest `start_time` wins.

### dim_user

| column       | type   | description                         |
| ------------ | ------ | ----------------------------------- |
| user_type_id | int    | surrogate key                       |
| user_type    | string | canonical label: `member`, `casual` |

`Annual Member` and `Member` collapse to `member`; `Casual Member` and `Casual`
collapse to `casual`.

### fact_trips

| column            | type   | description                          |
| ----------------- | ------ | ------------------------------------ |
| trip_id           | bigint | primary key                          |
| trip_duration     | int    | seconds, recomputed as `end - start` |
| start_year        | int    | 2019–2025                            |
| start_month       | int    | 1–12                                 |
| start_date        | date   | calendar date of start               |
| start_day_of_week | int    | 1 = Monday … 7 = Sunday              |
| start_hour        | int    | 0–23, join key for the ML dataset    |
| start_quarter     | int    | 1–4                                  |
| end_year          | int    |                                      |
| end_month         | int    |                                      |
| end_date          | date   |                                      |
| end_day_of_week   | int    |                                      |
| end_hour          | int    |                                      |
| end_quarter       | int    |                                      |
| start_station_id  | int    | FK → `dim_station`                   |
| end_station_id    | int    | FK → `dim_station`                   |
| user_type_id      | int    | FK → `dim_user`                      |

Partitioned by `start_year`, `start_month`.

---

## Phase 3 — ETL

### Extract

- Read each year's CSVs as all-string columns; assert the header matches the
  expected variant so an unnoticed schema shift fails loudly.
- Normalize headers, add `source_file` and `source_year`, union the years.
- Write `stage_trips`.

Implemented in [etl.ipynb](../../notebooks/etl.ipynb).

### Transform

1. **Type cast** — ids and duration to numeric; rows failing the cast are
   dropped and counted.
2. **Parse timestamps** — `dd/MM/yyyy HH:mm` for the years in scope; a null
   result means the row is rejected. Adding 2024+ requires a fallback to
   `yyyy-MM-dd HH:mm:ss`.
3. **Filter invalid trips** — drop where `end_time <= start_time`,
   duration < 60s or > 24h, or either station id is null.
4. **Deduplicate** — drop duplicate `trip_id`, keeping the first occurrence.
5. **Conform** — map `user_type` to `user_type_id`, derive the calendar columns.

### Load

- Build `dim_station` and `dim_user` first, then `fact_trips` with FK joins.
- Write Parquet with `overwrite` per partition so reruns are idempotent.

### Validation

- Row counts: raw → stage → fact, with rejects itemized by rule.
- No orphan FKs: every `start_station_id` / `end_station_id` exists in `dim_station`.
- `trip_id` is unique in `fact_trips`.

---

## Phase 4 — ML Dataset

Aggregate `fact_trips` to the model grain and write `data/featured/`.

Base: `group by start_station_id, start_date, start_hour` → `trip_count` (the target).

Zero-fill: the cross join of stations × the hourly calendar, so hours with no
departures become `trip_count = 0` rather than missing rows.

Additional features:

| feature                                 | source                                   |
| --------------------------------------- | ---------------------------------------- |
| hour, day_of_week, month, quarter, year | calendar columns                         |
| is_weekend                              | `day_of_week in (6, 7)`                  |
| is_holiday                              | Ontario statutory holiday calendar       |
| hour_sin, hour_cos                      | cyclical encoding of hour                |
| dow_sin, dow_cos                        | cyclical encoding of day of week         |
| lag_1h, lag_24h, lag_168h               | `trip_count` shifted per station         |
| roll_mean_24h, roll_mean_168h           | rolling mean of `trip_count` per station |
| member_ratio                            | member trips / total trips in the hour   |

Lags and rolling means are computed with a window partitioned by station and
ordered by timestamp, so no future information leaks into a row.

---

## Phase 5 — Split Dataset

Chronological split — random splits would leak future demand into training.

Matches the 2019–2023 ETL scope:

| split | range             |
| ----- | ----------------- |
| train | 2019-01 – 2022-12 |
| test  | 2023-01 – 2023-12 |

Roughly 80/20 by row count. A single test year keeps the split chronological
while leaving four years for training; 2023 is also clear of the COVID period,
so test error reflects ordinary demand rather than the 2020–2021 disruption.

> **2020–2021 remain in the training set.** April 2020 (~72k trips) and the
> summer peaks (~460–494k) are a lockdown collapse followed by a recreational
> surge, unlike any other year in the series. They are useful training signal
> but not representative, so a model may underfit them.

- Rows whose lag features fall outside the available history are dropped from
  the head of the train split.
- Write `data/featured/train/` and `data/featured/test/` as Parquet.
- Record row counts and the target's mean/variance per split for reference.

---

## Development

```sh
cd spark && cp .env.example .env && docker compose up -d --build
```

Then open Jupyter at http://localhost:8888 (token `bikeshare`) and run
[warehouse.ipynb](../../notebooks/warehouse.ipynb) from the top.