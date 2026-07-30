# ml-shared-bike

A machine learning project that explores key features of shared bike dataset.

---

## Documentation

1. [Problem definition](./docs/ml/01-problem.md)
2. [Data profile](./docs/data-profile.md)
3. [PySpark warehouse](./docs/de/01-pyspark-warehouse.md) — [Spark cluster setup](./spark/README.md)
4. [Project plan](./docs/PLAN.md)

https://oneuptime.com/blog/post/2026-02-23-how-to-build-an-ai-ml-pipeline-infrastructure-with-terraform/view

platform

- infra
  - setup sakemaker pipeline
  - setup sakemaker mlflow
  - cicd

- cicd
  - github actions

ds

- local train
  - connect local mlflow
- push
  - train.py
  - dvc: data to s3
- pr
