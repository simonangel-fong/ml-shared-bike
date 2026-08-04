# ml-shared-bike

A machine learning project that explores key features of shared bike dataset.

---

## Documentation

1. [Problem definition](./docs/ml/01-problem.md)
2. [Data profile](./docs/data-profile.md)
3. [PySpark warehouse](./docs/de/01-pyspark-warehouse.md) — [Spark cluster setup](./spark/README.md)
4. [Project plan](./docs/PLAN.md)



platform

- infra
  - setup sakemaker
    - jupyter notebook
    - pipeline
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

---

ref:

- https://medium.com/@jimwang3589/end-to-end-sagemaker-pipeline-design-for-a-machine-learning-product-0632c77aaa65s
- https://oneuptime.com/blog/post/2026-02-23-how-to-build-an-ai-ml-pipeline-infrastructure-with-terraform/view
- https://oneuptime.com/blog/post/2026-02-23-create-sagemaker-notebooks-in-terraform/view#lifecycle-configurations\
- https://medium.com/@mohitverma160288/sagemaker-terraform-multi-account-mlops-pt-2-03278d0c94cf

export MSYS_NO_PATHCONV=1; docker exec ml-jupyter rm -rf /opt/data/ml/featured/annual && echo "removed corrupt featured/annual"; docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}" 2>&1