# Machine Learning

[Back](../../README.md)

- [Machine Learning](#machine-learning)
  - [Business problem](#business-problem)
  - [ML Application](#ml-application)
  - [ML](#ml)
  - [Development](#development)

---

## Business problem

Predict how many bikes will be rented from each **station** each **hour**, so the operations team can move bikes to the right places before stations run out.

---

## ML Application

Users: operation team
Use case:

- operation team can predict the bike usage per station at a piont in time

- input by selecting
  - month
  - date
  - hour
  - station
- output: trip count prediction

---

## ML

- Phase

| #   | Phase                                   | Description                                                    |
| --- | --------------------------------------- | -------------------------------------------------------------- |
| 0   | Spin notebook                           | init notebook for ml                                           |
| 1   | Data processing                         | collection and clean,data source: `data/export`                |
| 2   | Feature Engineering                     | select input variable, output `data/featured`                  |
| 3   | Spin MLflow                             | init mlflow with docker compose                                |
| 4   | Model selection                         | Select model, create training code                             |
| 5   | training with version 1 hyperparameters | Select version 1 hyperparameters, train model, track by mlflow |
| 6   | training with version 2 hyperparameters | Select version 2 hyperparameters, train model, track by mlflow |
| 7   | Evaluation                              | evaluate v1 and v2, decide whether to ship                     |
| 8   | Save and upload model                   | if shipped: package the winning run, upload to S3              |

---

## Development

```sh
docker compose
```
