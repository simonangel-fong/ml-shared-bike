# ML Problem Definition

## Problem

| Item             | Definition                                                                                                                                            |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Business problem | Predict how many bikes will be rented from each station each hour, so the operations team can move bikes to the right places before stations run out. |
| Target           | `trip_count` — bikes rented from a station in one hour (regression)                                                                                   |
| Grain            | One row per station, per date, per hour. Hours with no trips = 0.                                                                                     |
| Features         | hour, day of week, month, weekend flag; counts from 1h / 24h / 1 week ago; 24h and 1-week averages; station id                                        |
| Model / algo     | LightGBM (poisson). Baseline to beat: same station, same hour, last week.                                                                             |
| Split            | By time — train ≤2023, validate 2024-01→06, test 2024-07→09                                                                                           |
| Metric           | MAE (main), RMSE                                                                                                                                      |
| Inference        | Input: station + date/time → Output: predicted bikes rented                                                                                           |

All features are derived from `Start Time` and `Start Station Id`. No external data sources required.

## Dataset

Bike Share Toronto ridership, `data/raw/{2019..2024}/` — 59 CSV files, ~3.1 GB, ~24.6M trips.
2019 is quarterly, 2020 onward is monthly, 2024 ends at September.

| Column                                | Notes                                              |
| ------------------------------------- | -------------------------------------------------- |
| Trip Id                               | int                                                |
| Trip Duration                         | seconds                                            |
| Start Station Id / End Station Id     | int; end is nullable                               |
| Start Time / End Time                 | `MM/DD/YYYY HH:MM` — minute resolution, no seconds |
| Start Station Name / End Station Name | free text, may contain commas                      |
| Bike Id                               | int                                                |
| User Type                             | `Annual Member` / `Casual Member`                  |
| Model                                 | 2024-02 onward only: `ICONIC`, `EFIT G5`, `EFIT`   |

| Year | Trips           |
| ---- | --------------- |
| 2019 | 2.44M           |
| 2020 | 2.91M           |
| 2021 | 3.58M           |
| 2022 | 4.62M           |
| 2023 | 5.71M           |
| 2024 | 5.34M (Jan–Sep) |

## Data Quality Issues

| Issue                    | Detail                                                                                                                                    | Impact                                                           |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `User Type` is corrupted | Casual share climbs to 100% for 2023-08 → 2024-01, then falls back to 79–94%. Not real behaviour.                                         | Column unusable after 2023-06. Not used by this model.           |
| Header drift             | `Trip Duration` (2019) vs `Trip  Duration` (double space, 2020+). BOM on 44 of 59 files, absent on 15. `Model` only from 2024-02.         | Normalize column names on load.                                  |
| Encoding drift           | 2024 files are cp1252; earlier files are UTF-8.                                                                                           | Read with UTF-8, fall back to cp1252.                            |
| Missing values           | ~0.06% null `End Station Id`/`Name`. 2023 files use the literal string `NULL`. 2024-07 has 20.6k null start-station names with valid IDs. | Key on station **id**, not name.                                 |
| Station churn            | 463 stations (2020) → 610 (2021) → 826 (2024). Names change over time.                                                                    | Use station id as the key; add a station-age feature.            |
| Duration outliers        | Min 0 seconds, max 12.4M seconds.                                                                                                         | Not used as a feature, but affects any duration-based filtering. |
| COVID break              | April 2020 drops to 71.8k trips.                                                                                                          | Structural break in the training period.                         |

## Build Notes

- Aggregate the raw trips to a station × date × hour panel before training. Zero-fill hours with no departures — a station with no trips in an hour is a real zero, not a missing row.
- Split by time only. A random split leaks future data into the training set and inflates the metrics.
- The seasonal-naive baseline (same station, same hour, last week) must be beaten for the model to be worth deploying.
