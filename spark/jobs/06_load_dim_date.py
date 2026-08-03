"""Load dim_date: one row per calendar date spanned by the stage data.

The calendar is generated in the driver rather than derived from the trips,
so every date in the range exists even if no trip started on it. `holidays`
is a driver-only import; it is not installed on the executors.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/06_load_dim_date.py
"""

from datetime import date, timedelta

import holidays
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import (
    StructType,
    StructField,
    DateType,
    IntegerType,
    BooleanType,
    StringType,
)

WAREHOUSE = "/opt/data/warehouse"
DIM_DATE_PATH = f"{WAREHOUSE}/dim_date"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"


TS_FORMAT = "MM/dd/yyyy HH:mm"

DIM_DATE_SCHEMA = StructType(
    [
        StructField("dim_date_id", DateType()),
        StructField("dim_date_year", IntegerType()),
        StructField("dim_date_quarter", IntegerType()),
        StructField("dim_date_month", IntegerType()),
        StructField("dim_date_day", IntegerType()),
        StructField("dim_date_week", IntegerType()),
        StructField("dim_date_weekday", IntegerType()),
        StructField("dim_date_is_weekend", BooleanType()),
        StructField("dim_date_is_holiday", BooleanType()),
        StructField("dim_date_season", StringType()),
    ]
)

SEASONS = {
    12: "winter", 1: "winter", 2: "winter",
    3: "spring", 4: "spring", 5: "spring",
    6: "summer", 7: "summer", 8: "summer",
    9: "fall", 10: "fall", 11: "fall",
}


def date_bounds(spark):
    """Min and max calendar date covered by the stage table."""
    stage = spark.table("stage_trips")
    bounds = stage.select(
        F.min(F.to_date(F.to_timestamp("start_time", TS_FORMAT))).alias("lo"),
        F.max(F.to_date(F.to_timestamp("end_time", TS_FORMAT))).alias("hi"),
    ).collect()[0]
    return bounds["lo"], bounds["hi"]


def build_calendar(first, last):
    """One tuple per date from first to last inclusive."""
    ca_holidays = holidays.Canada(
        subdiv="ON", years=range(first.year, last.year + 1)
    )

    rows = []
    day = first
    while day <= last:
        # python weekday() is 0=Monday; the warehouse uses spark's
        # dayofweek, 1=Sunday
        weekday = (day.weekday() + 1) % 7 + 1
        iso = day.isocalendar()
        rows.append(
            (
                day,
                day.year,
                (day.month - 1) // 3 + 1,
                day.month,
                day.day,
                iso[1],
                weekday,
                weekday in (1, 7),
                day in ca_holidays,
                SEASONS[day.month],
            )
        )
        day += timedelta(days=1)
    return rows


def main():
    # local[*]: ~1,800 rows needs no cluster, and running the write in the
    # driver keeps it off the executors, which run as a different uid than
    # this container and cannot write into paths root creates
    spark = (
        SparkSession.builder.appName("load_dim_date")
        .master("local[*]")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    first, last = date_bounds(spark)
    print(f"stage range : {first} -> {last}")

    rows = build_calendar(first, last)
    df = spark.createDataFrame(rows, schema=DIM_DATE_SCHEMA)

    df.coalesce(1).write.mode("overwrite").parquet(DIM_DATE_PATH)
    spark.sql("REFRESH TABLE dim_date")

    loaded = spark.table("dim_date")
    print(f"dim_date    : {loaded.count():,} rows")
    print(f"holidays    : {loaded.filter('dim_date_is_holiday').count():,}")
    print(f"weekend     : {loaded.filter('dim_date_is_weekend').count():,}")
    loaded.orderBy("dim_date_id").show(5)

    spark.stop()


if __name__ == "__main__":
    main()
