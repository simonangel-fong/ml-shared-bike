# ML Data Collection & Data Cleansing

[Back](../../README.md)

- [ML Data Collection \& Data Cleansing](#ml-data-collection--data-cleansing)
  - [Step 1: Data Collection](#step-1-data-collection)
    - [Source](#source)
    - [Run](#run)
  - [Step 2: Data quality checks](#step-2-data-quality-checks)
    - [Dataset Profile](#dataset-profile)
    - [quality checks report](#quality-checks-report)
  - [Data cleansing](#data-cleansing)

---

## Step 1: Data Collection

- download 2019 - 2025
- saved file
  - path: `data/raw/<year>/`

```sh
python -m venv .venv

pip install requests

python data-engineer/download.py # 2019-2025
```

---

### Source

- ref: https://open.toronto.ca/dataset/bike-share-toronto-ridership-data/

| Item          | Value                                                                       |
| ------------- | --------------------------------------------------------------------------- |
| CKAN endpoint | `https://ckan0.cf.opendata.inter.prod-toronto.ca/api/3/action/package_show` |
| Package id    | `bike-share-toronto-ridership-data`                                         |
| Years offered | 2016 – 2026 (yearly), plus `2014-2015` and a readme as XLSX                 |
| Format        | one ZIP per year, containing monthly or quarterly CSVs                      |

---

### Run

```bash
pip install requests

python data-engineer/download.py                    # 2019-2025 (default)
python data-engineer/download.py --years 2019 2020  # specific years
python data-engineer/download.py --force            # re-download existing years
```

---

## Step 2: Data quality checks

Guideline

- **Accuracy**: Data correctly reflects the real-world event or object it represents.
- **Completeness**: Required fields, files, or partitions are fully populated without missing components.
- **Consistency**: Values remain uniform and non-contradictory across different tables, sources, or systems.
- **Timeliness (Freshness)**: Data arrives and updates within established Service Level Agreements (SLAs).
- **Uniqueness**: Entity identifiers (such as primary keys) contain no unexpected duplicates.
- **Validity**: Data conforms strictly to defined formats, data types, and logical boundaries.

---

### Dataset Profile

| Column | Notes |
| ------ | ----- |

| Year | Trips |
| ---- | ----- |

...

---

### quality checks report

| #   | Issue | Solution |
| --- | ----- | -------- |

---

## Data cleansing

- Step

| #   | Step | Description |
| --- | ---- | ----------- |

- Output: `data/cleaned/<year>`

---
