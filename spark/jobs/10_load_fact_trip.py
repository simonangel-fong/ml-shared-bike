"""Load fact_trip from the stage table, resolving the dimension keys.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/10_load_fact_trip.py
"""

from pyspark.sql import SparkSession, Window, functions as F

WAREHOUSE = "/opt/data/warehouse"
FACT_TRIP_PATH = f"{WAREHOUSE}/fact_trip"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"

TS_FORMAT = "MM/dd/yyyy HH:mm"


def build_fact(spark):
    stage = spark.table("stage_trips")
    dim_user_type = spark.table("dim_user_type")

    start_ts = F.to_timestamp("start_time", TS_FORMAT)
    end_ts = F.to_timestamp("end_time", TS_FORMAT)

    typed = stage.select(
        F.col("trip_id").cast("int").alias("fact_trip_source_id"),
        F.col("trip_duration").cast("double").cast("int").alias(
            "fact_trip_duration"
        ),
        start_ts.alias("fact_trip_start_ts"),
        end_ts.alias("fact_trip_end_ts"),
        F.to_date(start_ts).alias("fact_trip_start_date_id"),
        F.to_date(end_ts).alias("fact_trip_end_date_id"),
        F.hour(start_ts).alias("fact_trip_start_hour"),
        F.minute(start_ts).alias("fact_trip_start_minute"),
        F.hour(end_ts).alias("fact_trip_end_hour"),
        F.minute(end_ts).alias("fact_trip_end_minute"),
        F.col("start_station_id").cast("int").alias(
            "fact_trip_start_station_id"
        ),
        F.col("end_station_id").cast("int").alias("fact_trip_end_station_id"),
        F.col("bike_id").cast("int").alias("fact_trip_bike_id"),
        F.col("user_type").alias("user_type"),
        F.year(start_ts).alias("start_year"),
        F.month(start_ts).alias("start_month"),
    )

    # small enough to broadcast, so the join does not shuffle 18.9M rows
    resolved = typed.join(
        F.broadcast(dim_user_type),
        typed.user_type == dim_user_type.dim_user_type_name,
        "inner",
    ).withColumnRenamed("dim_user_type_id", "fact_trip_user_type_id")

    # ordered by the source id so a reload reproduces the same keys
    return resolved.select(
        F.row_number()
        .over(Window.orderBy("fact_trip_source_id"))
        .cast("bigint")
        .alias("fact_trip_id"),
        "fact_trip_source_id",
        "fact_trip_duration",
        "fact_trip_start_ts",
        "fact_trip_end_ts",
        "fact_trip_start_date_id",
        "fact_trip_end_date_id",
        "fact_trip_start_hour",
        "fact_trip_start_minute",
        "fact_trip_end_hour",
        "fact_trip_end_minute",
        "fact_trip_start_station_id",
        "fact_trip_end_station_id",
        "fact_trip_bike_id",
        "fact_trip_user_type_id",
        "start_year",
        "start_month",
    )


def main():
    spark = (
        SparkSession.builder.appName("load_fact_trip")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    stage_rows = spark.table("stage_trips").count()

    fact = build_fact(spark)
    (
        fact.write.mode("overwrite")
        .partitionBy("start_year", "start_month")
        .parquet(FACT_TRIP_PATH)
    )
    spark.sql("MSCK REPAIR TABLE fact_trip")

    loaded = spark.table("fact_trip")
    fact_rows = loaded.count()

    print(f"stage rows : {stage_rows:>12,}")
    print(f"fact rows  : {fact_rows:>12,}")
    print(f"dropped    : {stage_rows - fact_rows:>12,}")

    loaded.groupBy("start_year").count().orderBy("start_year").show()

    spark.stop()


if __name__ == "__main__":
    main()
