"""Phase 1 verification: read one raw CSV through the cluster and count rows.

Run inside the jupyter container:

    docker compose exec jupyter python /home/jovyan/verify_spark.py
"""

import glob
import sys

from spark_session import RAW_DIR, WAREHOUSE_DIR, get_spark


def first_raw_csv() -> str:
    matches = sorted(glob.glob(f"{RAW_DIR}/*/*.csv"))
    if not matches:
        sys.exit(f"no CSVs found under {RAW_DIR} — is data/ mounted?")
    return matches[0]


def main() -> None:
    spark = get_spark("phase1-verify")
    print(f"spark {spark.version} on {spark.sparkContext.master}")

    path = first_raw_csv()
    df = spark.read.csv(path, header=True, inferSchema=False)

    print(f"file    : {path}")
    print(f"rows    : {df.count():,}")
    print(f"columns : {df.columns}")
    df.show(5, truncate=False)

    # round-trip a tiny table so the warehouse mount is proven writable
    probe = f"{WAREHOUSE_DIR}/_verify_probe"
    df.limit(10).write.mode("overwrite").parquet(probe)
    print(f"parquet write/read ok: {spark.read.parquet(probe).count()} rows at {probe}")

    spark.stop()


if __name__ == "__main__":
    main()
