"""Shared SparkSession factory for the bikeshare warehouse.

Import from notebooks or scripts running in the jupyter container:

    from spark_session import get_spark, RAW_DIR, WAREHOUSE_DIR
    spark = get_spark("stage_trips")
"""

import os

from pyspark.sql import SparkSession

RAW_DIR = os.environ.get("RAW_DIR", "/opt/data/raw")
WAREHOUSE_DIR = os.environ.get("WAREHOUSE_DIR", "/opt/data/warehouse")
MASTER_URL = os.environ.get("SPARK_MASTER_URL", "spark://spark-master:7077")
DRIVER_HOST = os.environ.get("SPARK_DRIVER_HOST", "jupyter")


def get_spark(app_name: str = "bikeshare", shuffle_partitions: int = 16) -> SparkSession:
    """Return the session for this JVM, creating it on first call."""
    return (
        SparkSession.builder.appName(app_name)
        .master(MASTER_URL)
        .config("spark.driver.host", DRIVER_HOST)
        .config("spark.sql.warehouse.dir", WAREHOUSE_DIR)
        .config("spark.sql.shuffle.partitions", shuffle_partitions)
        # per-partition overwrite keeps ETL reruns idempotent (Phase 3 Load)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        # mixed date formats across years must not abort the read
        .config("spark.sql.legacy.timeParserPolicy", "CORRECTED")
        .config("spark.sql.session.timeZone", "America/Toronto")
        .getOrCreate()
    )


def table_path(name: str) -> str:
    """Parquet location of a warehouse table."""
    return f"{WAREHOUSE_DIR}/{name}"
