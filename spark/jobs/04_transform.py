"""Clean the stage table in place: drop invalid rows, repair the rest.

Key columns (trip_id, trip_duration, start_time, start_station_id,
end_station_id) must be valid or the row goes. Everything else gets a
default. Values stay string-typed; the load casts them.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/04_transform.py
"""

from pyspark.sql import SparkSession, functions as F

WAREHOUSE = "/opt/data/warehouse"
STAGE_TRIPS_PATH = f"{WAREHOUSE}/stage_trips"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"


# month first: december files hold 12 in the first field and 1-31 in the second
TS_FORMAT = "MM/dd/yyyy HH:mm"
TS_PATTERN = r"^[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}$"
INT_PATTERN = r"^[0-9]+$"
NUM_PATTERN = r"^[0-9]+(\.[0-9]+)?$"

KEY_COLUMNS = [
    "trip_id",
    "trip_duration",
    "start_time",
    "start_station_id",
    "end_station_id",
]


def valid_rows(df):
    """Rows whose key columns are present, well formed and positive."""
    present = F.lit(True)
    for c in KEY_COLUMNS:
        present = present & F.col(c).isNotNull()

    well_formed = (
        F.col("trip_id").rlike(INT_PATTERN)
        & F.col("trip_duration").rlike(NUM_PATTERN)
        & F.col("start_station_id").rlike(INT_PATTERN)
        & F.col("end_station_id").rlike(INT_PATTERN)
        & F.col("start_time").rlike(TS_PATTERN)
        & F.to_timestamp("start_time", TS_FORMAT).isNotNull()
    )

    positive = F.col("trip_duration").cast("double") > 0

    return present & well_formed & positive


def repair(df):
    """Fill or normalize the non-critical columns."""
    start_ts = F.to_timestamp("start_time", TS_FORMAT)

    # a missing or malformed end_time is recoverable from start + duration
    end_ok = F.col("end_time").rlike(TS_PATTERN) & F.to_timestamp(
        "end_time", TS_FORMAT
    ).isNotNull()
    derived_end = F.from_unixtime(
        F.unix_timestamp(start_ts) + F.col("trip_duration").cast("double"),
        TS_FORMAT,
    )

    # station names carry the literal string "NULL", not a null
    def clean_name(col):
        name = F.trim(F.col(col))
        return F.when(
            name.isNull() | (name == "NULL") | (name == ""), F.lit("UNKNOWN")
        ).otherwise(name)

    user_type = F.trim(F.regexp_replace(F.col("user_type"), "\r", ""))

    return (
        df.withColumn(
            "end_time", F.when(end_ok, F.col("end_time")).otherwise(derived_end)
        )
        .withColumn("start_station_name", clean_name("start_station_name"))
        .withColumn("end_station_name", clean_name("end_station_name"))
        .withColumn(
            "user_type",
            F.when(user_type == "Annual Member", F.lit("annual"))
            .when(user_type == "Casual Member", F.lit("casual"))
            .when(user_type.isNull() | (user_type == ""), F.lit("UNKNOWN"))
            .otherwise(user_type),
        )
        .withColumn(
            "bike_id",
            F.when(F.col("bike_id").rlike(INT_PATTERN), F.col("bike_id"))
            .otherwise(F.lit("-1")),
        )
        .withColumn(
            "model",
            F.when(
                F.col("model").isNull() | (F.trim(F.col("model")) == ""),
                F.lit("UNKNOWN"),
            ).otherwise(F.trim(F.col("model"))),
        )
    )


def main():
    spark = (
        SparkSession.builder.appName("transform")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    stage = spark.table("stage_trips")
    columns = stage.columns

    before = stage.count()
    kept = repair(stage.filter(valid_rows(stage))).select(*columns)

    # cache: the write and the count below would otherwise recompute the
    # whole chain, and the source is the table being overwritten
    kept.persist()
    after = kept.count()

    (
        kept.write.mode("overwrite")
        .partitionBy("source_year")
        .parquet(STAGE_TRIPS_PATH)
    )
    spark.sql("MSCK REPAIR TABLE stage_trips")

    print(f"before  {before:>10,}")
    print(f"dropped {before - after:>10,}")
    print(f"after   {after:>10,}")

    kept.unpersist()
    spark.stop()


if __name__ == "__main__":
    main()
