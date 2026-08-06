# Toronto Shared Bike: Machine learning

A machine learning project that explores key features of shared bike dataset.

- [Toronto Shared Bike: Machine learning](#toronto-shared-bike-machine-learning)
  - [Business challenge](#business-challenge)
  - [Machine learning](#machine-learning)
    - [Problem Definition](#problem-definition)
    - [Data Collection \& Preparation](#data-collection--preparation)
    - [Model Development \& Training \& Validation](#model-development--training--validation)
    - [Training Pipeline](#training-pipeline)
  - [Application](#application)
    - [Model Deployment](#model-deployment)
    - [Devops Pipeline](#devops-pipeline)
    - [Monitoring](#monitoring)
  - [Takeway \& Roadmap](#takeway--roadmap)
  - [Documentation](#documentation)

---

## Business challenge

---

## Machine learning

### Problem Definition

---

### Data Collection & Preparation

Data warehouse, etl, export

### Model Development & Training & Validation

setup Jupyter Notebook and MLflow locally
feature engineering && model selection

---

### Training Pipeline

Diagram

GitHub Action + Sagemaker

---

## Application

### Model Deployment

diagram

S3 + Lambda + api gateway + cloudfront + cloudflare

Capture

---

### Devops Pipeline

GitHub Action + terraform

---

### Monitoring

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
