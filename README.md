# ml-shared-bike

A machine learning project that explores key features of shared bike dataset.

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

---

## Documentation

- [Data Engineering - Data warehouse(spark)](./docs/01-de-warehouse.md)
- [Machine Learning Engineering - Jupter Notebook & MLflow](./docs/02-ml.md)
- [MLOps - Amazon Sagemaker & GitHub Actions](./docs/04-mlops.md)
- 

---

feature of the project

local train
mlops pipeline: github actions + sagemaker
app: s3(html) lambda(docker) + api gateway + cloudfront + dns
devops pipeline: github actions(tf + docker image)
