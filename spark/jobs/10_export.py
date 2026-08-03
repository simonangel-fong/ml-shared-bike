"""Export the warehouse to data/export as parquet.

The same files serve as the backup and as the source for training and the
app: restoring reads all five tables, training reads fact_trip and dim_date,
the app reads the dimensions.

Run:
    docker compose -f spark/docker-compose.yml exec spark-master \
        /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
        /opt/jobs/11_export.py
"""

import json
import os
from datetime import datetime, timezone

from pyspark.sql import SparkSession

WAREHOUSE = "/opt/data/warehouse"
EXPORT = "/opt/data/export"
METASTORE_DIR = "/opt/data/metastore_db"
METASTORE_URL = f"jdbc:derby:;databaseName={METASTORE_DIR};create=true"

TABLES = {
    "fact_trip": ["start_year", "start_month"],
    "dim_date": [],
    "dim_station": [],
    "dim_bike": [],
    "dim_user_type": [],
}


def main():
    spark = (
        SparkSession.builder.appName("export")
        .config("spark.sql.warehouse.dir", WAREHOUSE)
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")
        .config("javax.jdo.option.ConnectionURL", METASTORE_URL)
        .enableHiveSupport()
        .getOrCreate()
    )

    manifest = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "spark_version": spark.version,
        "tables": {},
    }

    for name, partitions in TABLES.items():
        df = spark.table(name)
        rows = df.count()

        writer = df.write.mode("overwrite")
        if partitions:
            writer = writer.partitionBy(*partitions)
        else:
            writer = df.coalesce(1).write.mode("overwrite")

        writer.parquet(f"{EXPORT}/{name}")

        manifest["tables"][name] = {
            "rows": rows,
            "columns": len(df.columns),
            "partitioned_by": partitions,
        }
        print(f"{name:15s} {rows:>12,} rows")

    # plain file from the driver: spark would write a part- file, not json
    os.makedirs(EXPORT, exist_ok=True)
    with open(f"{EXPORT}/manifest.json", "w") as fh:
        json.dump(manifest, fh, indent=2)

    print()
    print(f"export -> {EXPORT}")

    spark.stop()


if __name__ == "__main__":
    main()
