# ML application

[Back](../README.md)

- [ML application](#ml-application)
  - [Goal](#goal)
  - [Phases](#phases)
  - [Development](#development)
    - [Phase 2: model + endpoint](#phase-2-model--endpoint)

---

## Goal

- deploy ml model with RESTful API
  - sagemaker model, endpoint(serverless)
  - lambda
  - api gateway
  - cloudfront
  - cloudflare(dns)
- managed by terraform
  - infra/mlapp/

---

- Metadata
  - existing s3 bucket: `toronto-shared-bike-ml-ud3m7h`
  - model: `s3://toronto-shared-bike-ml-ud3m7h/trains/annual-demand-q80-2026-08-04-22-00-42-965/output/model.tar.gz`
    - `output/model.tar.gz` is the artifact (model.skops + metrics.json).
      `source/sourcedir.tar.gz` is the training code the SDK uploaded - not
      servable.

---

## Phases

| #   | Phase              | Description                                      |
| --- | ------------------ | ------------------------------------------------ |
| 1   | init               | init terraform                                   |
| 2   | sagemaker endpoint | set up model, endpoint                           |
| 3   | lambda             | create lambda                                    |
| 3   | api gtw            | config api gateway                               |
| 4   | s3 website         | config html, s3 key: `web/`                      |
| 4   | cloudfront         | config cloudfront, forward api and s3            |
| 5   | cloudflare         | config cloudflare dns `trip-ml.arguswatcher.net` |

---

## Development

```sh
terraform -chdir=infra/mlapp init -backend-config=backend.hcl
terraform -chdir=infra/mlapp fmt && terraform -chdir=infra/mlapp validate

terraform -chdir=infra/mlapp plan
terraform -chdir=infra/mlapp apply -auto-approve
```

---

### Phase 2: model + endpoint

```
app/inference/
  inference.py      model_fn/input_fn/predict_fn/output_fn - the stock handler
                    cannot load model.skops
  requirements.txt  sklearn 1.9.0 etc, pinned to match mlops/requirements.txt
infra/mlapp/
  sagemaker-iam.tf       serving role - read trains/ and serve/, decrypt the key
  sagemaker-code.tf      tars app/inference/ -> s3://<bucket>/serve/sourcedir.tar.gz
  sagemaker-endpoint.tf  model -> endpoint config (serverless) -> endpoint
```

Model and endpoint config are immutable in the API, so both carry a name
derived from `md5(model_data_url + image + inference hash)` and use
`create_before_destroy`. The endpoint name is stable
(`toronto-shared-bike-ml-demand`) and is what phase 3 points API Gateway at.

Retraining is one variable:

```sh
terraform -chdir=infra/mlapp apply \
  -var 'model_data_url=s3://toronto-shared-bike-ml-ud3m7h/trains/<job>/output/model.tar.gz'
```

Smoke test once applied - first call is a cold start, ~30-60s while the
container pip-installs the pinned wheels:

```sh
aws sagemaker-runtime invoke-endpoint \
  --endpoint-name toronto-shared-bike-ml-demand \
  --content-type application/json \
  --body "$(echo '{"station_id":7000,"season":"summer","hour":17,"quarter":3,"month":7,"weekday":2,"week_of_year":28,"is_weekend":0,"is_holiday":0,"hour_sin":-0.2588,"hour_cos":-0.9659,"weekday_sin":0.7818,"weekday_cos":0.6235,"month_sin":-0.5,"month_cos":-0.866,"py_station_hour_weekday_mean":8.2,"py_station_month_mean":6.1}' | base64)" \
  /dev/stdout
# {"predictions": [<count>]}
```
