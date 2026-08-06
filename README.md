# Toronto Shared Bike MLOps Project

A project demonstrates an end-to-end `MLOps` workflow by training, deploying, and serving a bike-demand forecasting model.

- [Toronto Shared Bike MLOps Project](#toronto-shared-bike-mlops-project)
  - [Business challenge](#business-challenge)
  - [Machine learning](#machine-learning)
    - [Problem Definition](#problem-definition)
    - [Data Collection \& Preparation](#data-collection--preparation)
    - [Model Development \& Training \& Validation](#model-development--training--validation)
    - [Training Pipeline with `Amazon Sagemaker`](#training-pipeline-with-amazon-sagemaker)
  - [Application Deployment](#application-deployment)
  - [Monitoring](#monitoring)
  - [Takeway \& Roadmap](#takeway--roadmap)
  - [Documentation](#documentation)

---

## Business challenge

Machine learning turns historical data into insights for faster, data-driven decisions.

> However, **integrating machine learing models reliably into business applications** remains a significant challenge.

This project demonstrates an end-to-end `MLOps` workflow by training, deploying, and serving a bike-demand forecasting model.

---

## Machine learning

### Problem Definition

**Problem**:

> Predict hourly bike rentals at the 73 busiest stations for annual members, whose demand is driven primarily by predictable weekday commuting patterns.

**Business impact**:

- **Operations team**: Anticipate demand and rebalance bikes before high-demand stations run out.
- **Annual members**: Improve bike availability and service reliability during regular commutes.

---

### Data Collection & Preparation

This project builds on the [Toronto Shared Bike Data Engineering project](https://trip.arguswatcher.net/), which provides the data warehouse and ETL pipeline.

The trip data is exported from the warehouse and prepared for feature engineering and model training.

---

### Model Development & Training & Validation

Setup `Jupyter Notebook` to develop model locally

- `Jupyter Notebook`: Local tarining

  ![ml_notebook01](./docs/img/ml_notebook01.png)

Train, evaluate, and track model training by `MLflow`

- `MLflow`: Runs

  ![ml_mlflow_hyperparameter02](./docs/img/ml_mlflow_hyperparameter02.png)

- MLflow: Hyperparameter Training

  ![ml_mlflow_hyperparameter01](./docs/img/ml_mlflow_hyperparameter01.png)

---

### Training Pipeline with `Amazon Sagemaker`

**`Amazone Sagemaker`: Training Jobs**
![sagemaker_training_job01](./docs/img/sagemaker_training_job01.png)

**`GitHub Actions`: MLOps Pipeline**
![mlops_github01](./docs/img/mlops_github01.png)

---

## Application Deployment

- Deploy ML application on AWS:
  - `Lambda`(Docker Image): serverless inference
  - `API Gateway`(HTTPv2): entry point for service with low cost
  - `S3 bucket`: host frontend files
  - `Cloudfront`: cached for performance
  - `Cloudflare`: DNS




- Automate deployment by `GitHub Actions` workflows
  - Triggered when updated codes and/or completed model training jobs
  - Build and push Docker image
  - Update application in AWS.

---

## Monitoring

Cloudwatch + grafana

---

## Takeway & Roadmap

- Roles
  platform engineer
  Data engineer
  Data scientist
  ML Engineer
  MLOps Engineer

---

## Documentation

- [Data Engineering - Data warehouse(spark)](./docs/01-de-warehouse.md)
- [Machine Learning Engineering - Jupter Notebook & MLflow](./docs/02-ml.md)
- [MLOps - Amazon Sagemaker & GitHub Actions](./docs/04-mlops.md)
- [ML Application Deployment](./docs/05-mlapp.md)
- ***

feature of the project

local train
mlops pipeline: github actions + sagemaker
app: s3(html) lambda(docker) + api gateway + cloudfront + dns
devops pipeline: github actions(tf + docker image)
