"""Create the star schema: four dimensions and the trip fact table.

Tables are declared empty here; the load populates them.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/05_create_warehouse.py
"""

from pyspark.sql import SparkSession

WAREHOUSE = "/opt/data/warehouse"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"


# parquet enforces no constraints, so PK/FK/CHECK and indexes have no
# equivalent here; the notebook validates the ranges instead
TABLES = {
    # date grain, not minute: ~1.8k rows against 18.9M facts, small enough to
    # broadcast, and the only level carrying attributes worth normalizing
    "dim_date": (
        """
        dim_date_id         DATE,
        dim_date_year       INT,
        dim_date_quarter    INT,
        dim_date_month      INT,
        dim_date_day        INT,
        dim_date_week       INT,
        dim_date_weekday    INT,
        dim_date_is_weekend BOOLEAN,
        dim_date_is_holiday BOOLEAN,
        dim_date_season     STRING
        """,
        [],
    ),
    "dim_station": (
        """
        dim_station_id   INT,
        dim_station_name STRING
        """,
        [],
    ),
    "dim_bike": (
        """
        dim_bike_id    INT,
        dim_bike_model STRING
        """,
        [],
    ),
    "dim_user_type": (
        """
        dim_user_type_id   INT,
        dim_user_type_name STRING
        """,
        [],
    ),
    # time of day lives here as plain ints: 1,440 possible values with no
    # attributes to hang off them is a measure, not a dimension
    "fact_trip": (
        """
        fact_trip_id               BIGINT,
        fact_trip_source_id        INT,
        fact_trip_duration         INT,
        fact_trip_start_ts         TIMESTAMP,
        fact_trip_end_ts           TIMESTAMP,
        fact_trip_start_date_id    DATE,
        fact_trip_end_date_id      DATE,
        fact_trip_start_hour       INT,
        fact_trip_start_minute     INT,
        fact_trip_end_hour         INT,
        fact_trip_end_minute       INT,
        fact_trip_start_station_id INT,
        fact_trip_end_station_id   INT,
        fact_trip_bike_id          INT,
        fact_trip_user_type_id     INT
        """,
        ["start_year INT", "start_month INT"],
    ),
}


def create_table(spark, name, columns, partitions):
    spark.sql(f"DROP TABLE IF EXISTS {name}")

    partition_clause = ""
    if partitions:
        columns = columns.rstrip() + ",\n        " + ",\n        ".join(
            partitions
        )
        names = [p.split()[0] for p in partitions]
        partition_clause = f"PARTITIONED BY ({', '.join(names)})"

    spark.sql(
        f"""
        CREATE TABLE {name} (
        {columns}
        )
        USING parquet
        {partition_clause}
        LOCATION '{WAREHOUSE}/{name}'
        """
    )


def main():
    spark = (
        SparkSession.builder.appName("create_warehouse")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    # the previous design normalized time to the minute
    spark.sql("DROP TABLE IF EXISTS dim_time")

    for name, (columns, partitions) in TABLES.items():
        create_table(spark, name, columns, partitions)
        df = spark.table(name)
        part = (
            f"  partitioned by {[p.split()[0] for p in partitions]}"
            if partitions
            else ""
        )
        print(f"{name:15s} {len(df.columns):2d} columns{part}")

    print()
    spark.sql("SHOW TABLES").show(truncate=False)

    spark.stop()


if __name__ == "__main__":
    main()
