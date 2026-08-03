"""Load dim_station: one row per station, carrying its most recent name.

Stations appear as both trip origin and destination and get renamed over
time, so the two sides are unioned and the latest name by trip timestamp
wins.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/07_load_dim_station.py
"""

from pyspark.sql import SparkSession, Window, functions as F

WAREHOUSE = "/opt/data/warehouse"
DIM_STATION_PATH = f"{WAREHOUSE}/dim_station"

METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"

TS_FORMAT = "MM/dd/yyyy HH:mm"


def station_names(spark):
    """Every (id, name, when) pair from both ends of every trip."""
    stage = spark.table("stage_trips")

    starts = stage.select(
        F.col("start_station_id").cast("int").alias("station_id"),
        F.col("start_station_name").alias("station_name"),
        F.to_timestamp("start_time", TS_FORMAT).alias("seen_at"),
    )
    ends = stage.select(
        F.col("end_station_id").cast("int").alias("station_id"),
        F.col("end_station_name").alias("station_name"),
        F.to_timestamp("end_time", TS_FORMAT).alias("seen_at"),
    )

    return starts.unionByName(ends).filter(
        F.col("station_id").isNotNull() & F.col("station_name").isNotNull()
    )


def latest_name(df):
    """Keep the name seen most recently for each station."""
    # UNKNOWN is a placeholder from the transform, not a real rename, so it
    # only wins when a station has never had a real name
    ranked = df.withColumn(
        "rn",
        F.row_number().over(
            Window.partitionBy("station_id").orderBy(
                (F.col("station_name") == "UNKNOWN").asc(),
                F.col("seen_at").desc(),
            )
        ),
    )
    return ranked.filter("rn = 1").select(
        F.col("station_id").alias("dim_station_id"),
        F.col("station_name").alias("dim_station_name"),
    )


def main():
    spark = (
        SparkSession.builder.appName("load_dim_station")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    pairs = station_names(spark)
    dim = latest_name(pairs).orderBy("dim_station_id")

    dim.coalesce(1).write.mode("overwrite").parquet(DIM_STATION_PATH)
    spark.sql("REFRESH TABLE dim_station")

    loaded = spark.table("dim_station")
    unknown = loaded.filter("dim_station_name = 'UNKNOWN'").count()
    print(f"dim_station : {loaded.count():,} rows")
    print(f"unknown     : {unknown:,}")
    loaded.orderBy("dim_station_id").show(5, truncate=False)

    spark.stop()


if __name__ == "__main__":
    main()
