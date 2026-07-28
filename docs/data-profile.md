# Step 2: Data Quality Checks

[Back](./ml/02-data.md)

## Objective

Produce measured evidence of every defect in `data/raw/`, assessed against the six quality dimensions.

- Expose defects only
- No cleansing at this stage

---

## Environment and Tools

pandas and jupyter installed in `.venv` (pip only for now).

---

## Approach

| Dimension    | What to check                   | Example                               |
| ------------ | ------------------------------- | ------------------------------------- |
| Validity     | Values follow rules and formats | Age must be between 0 and 120         |
| Completeness | Missing or null values          | `customer_id` must not be null        |
| Uniqueness   | Duplicate records or keys       | `order_id` must be unique             |
| Consistency  | Related fields do not conflict  | `end_date` must be after `start_date` |
| Accuracy     | Values represent reality        | Postal code matches province          |
| Timeliness   | Data is recent enough           | Daily data arrived before 8:00 a.m.   |

- Accuracy is assumed rather than verified.

---

## Steps

| #   | Step               | Description                                                            |
| --- | ------------------ | ---------------------------------------------------------------------- |
| 1   | Install packages   | Install pandas and jupyter                                             |
| 2   | Metadata check     | Validate CSV schema against the source; row, file, path, and ID counts |
| 3   | Validity check     | Value formats and ranges                                               |
| 4   | Completeness check | Missing or null values                                                 |
| 5   | Uniqueness check   | Duplicate records                                                      |
| 6   | Consistency check  | Conflicts between related fields                                       |
| 7   | Accuracy check     | Whether values represent reality                                       |
| 8   | Timeliness check   | Oldest and latest data points; rows per year                           |
| 9   | Summary            | Build the data profiling table and update 02-data.md                   |

---

## Development

- Install packages

```sh
# Activate the virtual environment (Windows)
.venv\Scripts\activate

# Install the packages
pip install pandas jupyter ipykernel
```
