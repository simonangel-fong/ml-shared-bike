"""Load dim_user_type: one row per membership type.

The reference assigns the key with a SERIAL; here it is row_number over the
name, so the same input always yields the same ids and the fact table can be
reloaded independently.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/09_load_dim_user_type.py
"""

from pyspark.sql import SparkSession, Window, functions as F

WAREHOUSE = "/opt/data/warehouse"
DIM_USER_TYPE_PATH = f"{WAREHOUSE}/dim_user_type"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"


def build_dim_user_type(spark):
    stage = spark.table("stage_trips")

    names = (
        stage.select(F.col("user_type").alias("dim_user_type_name"))
        .filter(F.col("dim_user_type_name").isNotNull())
        .distinct()
    )

    return names.select(
        F.row_number()
        .over(Window.orderBy("dim_user_type_name"))
        .cast("int")
        .alias("dim_user_type_id"),
        "dim_user_type_name",
    )


def main():
    spark = (
        SparkSession.builder.appName("load_dim_user_type")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    dim = build_dim_user_type(spark)
    dim.coalesce(1).write.mode("overwrite").parquet(DIM_USER_TYPE_PATH)
    spark.sql("REFRESH TABLE dim_user_type")

    loaded = spark.table("dim_user_type")
    print(f"dim_user_type : {loaded.count():,} rows")
    loaded.orderBy("dim_user_type_id").show(truncate=False)

    spark.stop()


if __name__ == "__main__":
    main()
