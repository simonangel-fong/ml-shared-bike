"""Create the stage table: a raw landing zone, every column string.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/02_stage_table.py
"""

from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType

WAREHOUSE = "/opt/data/warehouse"
STAGE_TRIPS_PATH = f"{WAREHOUSE}/stage_trips"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"

# `model` is absent from the pre-2024 CSVs and lands null
STAGE_TRIPS_SCHEMA = StructType(
    [
        StructField("trip_id", StringType()),
        StructField("trip_duration", StringType()),
        StructField("start_time", StringType()),
        StructField("start_station_id", StringType()),
        StructField("start_station_name", StringType()),
        StructField("end_time", StringType()),
        StructField("end_station_id", StringType()),
        StructField("end_station_name", StringType()),
        StructField("bike_id", StringType()),
        StructField("user_type", StringType()),
        StructField("model", StringType()),
    ]
)

PARTITION_COLS = ["source_year"]


def create_stage_table(spark):
    """Register stage_trips as an external Parquet table.

    Declared via DDL, not by writing an empty DataFrame: an empty write
    produces no Parquet files, leaving a reader nothing to infer a schema
    from (UNABLE_TO_INFER_SCHEMA).
    """
    partition_fields = [StructField(c, StringType()) for c in PARTITION_COLS]
    full_schema = StructType(STAGE_TRIPS_SCHEMA.fields + partition_fields)

    columns = ",\n    ".join(
        f"{f.name} STRING" for f in STAGE_TRIPS_SCHEMA.fields
    )
    partition_by = ", ".join(f"{c} STRING" for c in PARTITION_COLS)

    spark.sql("DROP TABLE IF EXISTS stage_trips")
    spark.sql(
        f"""
        CREATE TABLE stage_trips (
            {columns}
        )
        USING parquet
        PARTITIONED BY ({partition_by})
        LOCATION '{STAGE_TRIPS_PATH}'
        """
    )
    return full_schema


def main():
    spark = (
        SparkSession.builder.appName("stage_table")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    full_schema = create_stage_table(spark)

    print(f"stage_trips -> {STAGE_TRIPS_PATH}")
    print(f"columns     : {len(full_schema)}")
    print(f"partitions  : {', '.join(PARTITION_COLS)}")
    spark.table("stage_trips").printSchema()

    spark.stop()


if __name__ == "__main__":
    main()
