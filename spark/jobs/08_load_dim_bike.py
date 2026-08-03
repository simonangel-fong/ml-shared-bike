"""Load dim_bike: one row per bike, carrying its model.

Model is absent from the pre-2024 source and lands as UNKNOWN, so a real
model wins wherever one exists and UNKNOWN is only the fallback.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/08_load_dim_bike.py
"""

from pyspark.sql import SparkSession, functions as F

WAREHOUSE = "/opt/data/warehouse"
DIM_BIKE_PATH = f"{WAREHOUSE}/dim_bike"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"


def build_dim_bike(spark):
    stage = spark.table("stage_trips")

    return (
        stage.select(
            F.col("bike_id").cast("int").alias("dim_bike_id"),
            F.col("model").alias("model"),
        )
        .filter(F.col("dim_bike_id").isNotNull())
        .groupBy("dim_bike_id")
        # max() over the non-UNKNOWN values, falling back to UNKNOWN
        .agg(
            F.coalesce(
                F.max(
                    F.when(F.col("model") != "UNKNOWN", F.col("model"))
                ),
                F.lit("UNKNOWN"),
            ).alias("dim_bike_model")
        )
    )


def main():
    spark = (
        SparkSession.builder.appName("load_dim_bike")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    dim = build_dim_bike(spark).orderBy("dim_bike_id")
    dim.coalesce(1).write.mode("overwrite").parquet(DIM_BIKE_PATH)
    spark.sql("REFRESH TABLE dim_bike")

    loaded = spark.table("dim_bike")
    unknown = loaded.filter("dim_bike_model = 'UNKNOWN'").count()
    print(f"dim_bike : {loaded.count():,} rows")
    print(f"unknown  : {unknown:,}")
    loaded.groupBy("dim_bike_model").count().show()
    loaded.orderBy("dim_bike_id").show(5, truncate=False)

    spark.stop()


if __name__ == "__main__":
    main()
