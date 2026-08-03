"""Extract raw CSVs into the stage table, one partition per source year.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/03_extract.py
"""

from pyspark.sql import SparkSession, functions as F

RAW = "/opt/data/raw"
WAREHOUSE = "/opt/data/warehouse"
STAGE_TRIPS_PATH = f"{WAREHOUSE}/stage_trips"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"


YEARS = [2019, 2020, 2021, 2022, 2023]

COLUMN_MAP = {
    "Trip Id": "trip_id",
    "Trip  Duration": "trip_duration",
    "Start Time": "start_time",
    "Start Station Id": "start_station_id",
    "Start Station Name": "start_station_name",
    "End Time": "end_time",
    "End Station Id": "end_station_id",
    "End Station Name": "end_station_name",
    "Bike Id": "bike_id",
    "User Type": "user_type",
}

STAGE_COLUMNS = list(COLUMN_MAP.values()) + ["model"]


def read_year(spark, year):
    """Read every csv for one year, normalized to the stage columns."""
    df = spark.read.csv(
        f"{RAW}/{year}/*.csv",
        header=True,
        inferSchema=False,
        # a BOM rides on the first header of every year but 2021
        encoding="UTF-8",
        multiLine=False,
    )

    renamed = {}
    for name in df.columns:
        clean = name.replace("﻿", "").strip()
        if clean in COLUMN_MAP:
            renamed[name] = COLUMN_MAP[clean]

    missing = set(COLUMN_MAP.values()) - set(renamed.values())
    if missing:
        raise ValueError(f"{year}: csv header missing {sorted(missing)}")

    for old, new in renamed.items():
        df = df.withColumnRenamed(old, new)

    if "model" not in df.columns:
        df = df.withColumn("model", F.lit(None).cast("string"))

    return df.select(*STAGE_COLUMNS)


def main():
    spark = (
        SparkSession.builder.appName("extract")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    total = 0
    for year in YEARS:
        df = read_year(spark, year).withColumn("source_year", F.lit(str(year)))

        (
            df.write.mode("overwrite")
            .partitionBy("source_year")
            .parquet(STAGE_TRIPS_PATH)
        )

        rows = df.count()
        total += rows
        print(f"{year} -> {rows:>9,} rows")

    # the metastore does not learn about directories written underneath it
    spark.sql("MSCK REPAIR TABLE stage_trips")

    print(f"{'total':<5}    {total:>9,} rows")
    print(f"stage_trips  {spark.table('stage_trips').count():>9,} rows")

    spark.stop()


if __name__ == "__main__":
    main()
