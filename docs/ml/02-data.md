# ML Data Collection & Data Cleansing

[Back](../../README.md)

- [ML Data Collection \& Data Cleansing](#ml-data-collection--data-cleansing)
  - [Step 1: Data Collection](#step-1-data-collection)
    - [Source](#source)
    - [Run](#run)
  - [Step 2: Data cleansing](#step-2-data-cleansing)
    - [Tasks](#tasks)
    - [Cleaned Dataset Profile](#cleaned-dataset-profile)

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

## Step 2: Data cleansing

- Data quality checks

| Dimension    | What to check                   | Example                               |
| ------------ | ------------------------------- | ------------------------------------- |
| Validity     | Values follow rules and formats | Age must be between 0 and 120         |
| Completeness | Missing or null values          | `customer_id` must not be null        |
| Uniqueness   | Duplicate records or keys       | `order_id` must be unique             |
| Consistency  | Related fields do not conflict  | `end_date` must be after `start_date` |
| Accuracy     | Values represent reality        | Postal code matches province          |
| Timeliness   | Data is recent enough           | Daily data arrived before 8:00 a.m.   |

- Input: `data/raw/<year>`
- Output: `data/cleaned/<year>`

---

### Tasks

| #   | Task               | Description                                          |
| --- | ------------------ | ---------------------------------------------------- |
| 1   | Install packages   | Install pandas and jupyter                           |
| 2   | Schema check       | spot schame shift, and standardize schema            |
| 3   | Validity check     | Value formats                                        |
| 4   | Completeness check | Missing or null values                               |
| 5   | Uniqueness check   | Duplicate records                                    |
| 6   | Consistency check  | Conflicts between related fields                     |
| 7   | Accuracy check     | Whether values represent reality                     |
| 8   | Timeliness check   | Oldest and latest data points; rows per year         |
| 9   | Summary            | Build the data profiling table and update 02-data.md |

---

- Install packages

```sh
# Activate the virtual environment (Windows)
.venv\Scripts\activate

# Install the packages
pip install pandas jupyter ipykernel
```

- Data Cleansing: `data-engineer/02-quality-checks.ipynb`

---

### Cleaned Dataset Profile

- Schema
  | Column | Notes |
  | ------ | ----- |

- Metadata

| Year | Trips |
| ---- | ----- |
