# Toronto Shared Bike MLOps Project - Web

[Back](../README.md)

- [Toronto Shared Bike MLOps Project - Web](#toronto-shared-bike-mlops-project---web)
  - [Website](#website)
  - [Design](#design)

---

## Website

path:

- app/web
  - index.html: project website
  - error.html: return root in 15s
  - js/main.js
  - css/style.css
  - img/

---

## Design

framework: bootstrap
theme: dark

Navbar:

- nav title
  - content: "Toronto Shared Bike"
  - url: trip-ml.arguswatcher.net
  - style: left
- nav bar

---

section: hero

- title: Toronto Shared Bike MLOps
- subtitle: end-to-end MLOps workflow
- content: A project demonstrates an end-to-end MLOps workflow by training, deploying, and serving a bike-demand forecasting model.
- layout:
  - central
  - col-10
  - backgroud image: app\web\img\bg-image.jpg

---

section: challenge

- title: Business Challenge
- content:
  - Machine learning turns historical data into insights for faster, data-driven decisions.
  - However, integrating machine learing models reliably into business applications remains a significant challenge.
    - largeer font size
    - highlight
  - This project demonstrates an end-to-end MLOps workflow by training, deploying, and serving a bike-demand forecasting model.

---

section: ml-app

- ui to predict trip count per station

---

section: ml

- title: Machine Learning

---

subsection: ml-problem

- title: Problem Definition
- content: Predict hourly bike rentals at the 73 busiest stations for annual members, whose demand is driven primarily by predictable weekday commuting patterns.
- Business impact:
- bulletpoint:
  - Operations team: Anticipate demand and rebalance bikes before high-demand stations run out.
- bulletpoint:
  - Annual members: Improve bike availability and service reliability during regular commutes.

---

subsection: mlops

- title: MLOps Lifecycle
- carousel
  - slide1: Data Collection & Preparation
  - slide2: Model Development
  - slide3: Training Pipeline with Amazon Sagemaker

---

subsection: ml-app

- title: Application Deployment
- image: architecture diagram

---

subsection: take-away

- title: Application Deployment
- content:
  - A successful ML application requires clear ownership across multiple roles:
    - Data Engineer: Builds dependable data sources and ETL pipelines.
    - Data Scientist: Converts business problems into validated models and insights.
    - ML Engineer: Integrates models into production applications.
    - MLOps Engineer: Automates training, deployment, monitoring, and integration across the ML lifecycle.
  - Clear ownership improves delivery, while MLOps connects each component into a reliable, repeatable production system.
- image: ownership
