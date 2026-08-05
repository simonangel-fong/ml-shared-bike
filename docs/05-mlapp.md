# ML application

[Back](../README.md)

- [ML application](#ml-application)
  - [Goal](#goal)
  - [Why Lambda, not a SageMaker endpoint](#why-lambda-not-a-sagemaker-endpoint)
  - [Phases](#phases)
  - [Development](#development)
    - [Phase 2: lambda](#phase-2-lambda)
    - [Phase 3: api gateway](#phase-3-api-gateway)

---

## Goal

- deploy ml model with RESTful API
  - lambda (container image, model baked in)
  - api gateway
  - cloudfront
  - cloudflare(dns)
- managed by terraform
  - infra/

---

- Metadata
  - existing s3 bucket: `toronto-shared-bike-ml-ud3m7h`
  - model: `s3://toronto-shared-bike-ml-ud3m7h/trains/annual-demand-q80-2026-08-04-22-00-42-965/output/model.tar.gz`
    - `output/model.tar.gz` is the artifact (model.skops + model.joblib +
      metrics.json). `source/sourcedir.tar.gz` is the training code the SDK
      uploaded - not servable.

---

## Why Lambda, not a SageMaker endpoint

The first attempt was a SageMaker serverless endpoint. It never reached
`InService`. The prebuilt sklearn container fetches the handler from S3 at
startup, runs `pip install .` on it, and only then imports it - and that
install lands somewhere off `sys.path`, so the import fails. The container
reports every such failure as `No module named 'inference'`, naming the entry
point rather than whatever was actually missing, which makes it slow to
diagnose. Startup also refused outright on the py312 image until
`PIP_BREAK_SYSTEM_PACKAGES` was set, because the image is Debian based
(PEP 668).

None of that machinery is needed here. The model is 11MB and a prediction is a
single tree-ensemble call.

|                | Lambda (container)       | SageMaker serverless          |
| -------------- | ------------------------ | ----------------------------- |
| model delivery | baked into the image     | pulled from S3 at cold start  |
| dependencies   | baked in, no startup pip | `pip install` on every start  |
| cold start     | ~1-3s                    | ~30-60s                       |
| memory         | up to 10GB               | 1-6GB                         |
| image size     | 10GB max                 | no practical limit            |
| timeout        | 15 min                   | 60s per request               |
| local testing  | identical via RIE        | does not reproduce (verified) |

Baking the image removes the failure mode entirely: no `SAGEMAKER_PROGRAM`, no
`SAGEMAKER_SUBMIT_DIRECTORY`, no startup install. It is also testable locally -
the Lambda runtime emulator behaves as production does, which the SageMaker
container did not.

What is given up: the SageMaker-native story (model registry, endpoint metrics,
traffic splitting) and the ability to serve models too large for a 10GB image.
Neither applies to this model.

The endpoint is loading `model.joblib` rather than `model.skops`, because
joblib ships in the image and skops would be another dependency for no gain
inside a container we control. `train.py` writes both - skops stays as the
archival format, since it does not execute arbitrary code on load.

---

## Phases

| #   | Phase      | Description                                      |
| --- | ---------- | ------------------------------------------------ |
| 1   | init       | init terraform                                   |
| 2   | lambda     | container image with the model baked in          |
| 3   | api gtw    | config api gateway                               |
| 4   | s3 website | config html, s3 key: `web/`                      |
| 4   | cloudfront | config cloudfront, forward api and s3            |
| 5   | cloudflare | config cloudflare dns `trip-ml.arguswatcher.net` |

---

## Development

```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra plan
terraform -chdir=infra apply -auto-approve
```

---

### Phase 2: lambda

```
app/lambda/
  Dockerfile        public.ecr.aws/lambda/python:3.12 + deps + model
  handler.py        loads the model at import, predicts per request
  model/            model.joblib, downloaded from S3, not committed
```

The model is loaded once at container init and reused across invocations, so
only a cold start pays for it.

Local run, no AWS:

```sh
# fetch the model for local development
aws s3 cp s3://toronto-shared-bike-ml-ud3m7h/trains/annual-demand-q80-2026-08-04-22-00-42-965/output/model.tar.gz - | tar -xzO model.joblib > app/lambda/model/model.joblib

docker build -t bike-ml-api app/lambda/
docker run --rm -p 9000:8080 bike-ml-api

curl -s -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"body": "{\"station_id\":7000,\"season\":\"summer\",\"hour\":17,\"quarter\":3,\"month\":7,\"weekday\":2,\"week_of_year\":28,\"is_weekend\":0,\"is_holiday\":0,\"hour_sin\":-0.2588,\"hour_cos\":-0.9659,\"weekday_sin\":0.7818,\"weekday_cos\":0.6235,\"month_sin\":-0.5,\"month_cos\":-0.866,\"py_station_hour_weekday_mean\":8.2,\"py_station_month_mean\":6.1}"}'

# {"predictions": [4.9716]}
```

Build and push:

```sh
aws ecr get-login-password --region ca-central-1 \
  | docker login --username AWS --password-stdin 099139718958.dkr.ecr.ca-central-1.amazonaws.com

REPO=$(terraform -chdir=infra output -raw api_ecr_repository_url)

terraform -chdir=infra output -raw api_ecr_repository_url
# 099139718958.dkr.ecr.ca-central-1.amazonaws.com/toronto-shared-bike-ml-api

docker buildx build --platform linux/amd64 --provenance=false --sbom=false --output "type=image,name=099139718958.dkr.ecr.ca-central-1.amazonaws.com/toronto-shared-bike-ml-api:v1,oci-mediatypes=false,push=true" app/lambda/
```

Then point Terraform at the tag and apply:

```sh
# infra/terraform.tfvars
lambda_image_tag = "v1"
```

---

```sh
# test
aws lambda invoke `
  --function-name toronto-shared-bike-ml-api `
  --region ca-central-1 `
  --cli-binary-format raw-in-base64-out `
  --payload "file://$env:TEMP\payload.json" `
  "$env:TEMP\out.json"

Get-Content "$env:TEMP\out.json"
# {"statusCode": 200, ..., "body": "{\"predictions\": [4.9716]}"}

```

The lambda function url is `AWS_IAM`, so it needs a signed request
(`awscurl --service lambda --region ca-central-1 ...`). It is not public: this
account is in an organization whose SCP blocks unauthenticated function urls -
`authorization_type = "NONE"` answers 403 regardless of the function policy.
The api gateway route below has no such restriction.

---

### Phase 3: api gateway

HTTP API (v2), one route, proxy integration. `handler.py` already returns
`{statusCode, headers, body}` and unwraps `event["body"]`, so there are no
mapping templates.

```
POST https://<api-id>.execute-api.ca-central-1.amazonaws.com/predict
```

`$default` stage with `auto_deploy`, so there is no deployment step and no
stage prefix in the path. CORS is set on the api (not in the handler) because
the phase 4 front end is served from another origin and will preflight.

```sh
terraform -chdir=infra output -raw api_predict_url
# https://twn44lawi3.execute-api.ca-central-1.amazonaws.com/predict

# single record
curl -s -XPOST "https://twn44lawi3.execute-api.ca-central-1.amazonaws.com/predict" -H 'Content-Type: application/json' -d '{"station_id":7000,"season":"summer","hour":17,"quarter":3,"month":7,"weekday":2,"week_of_year":28,"is_weekend":0,"is_holiday":0,"hour_sin":-0.2588,"hour_cos":-0.9659,"weekday_sin":0.7818,"weekday_cos":0.6235,"month_sin":-0.5,"month_cos":-0.866,"py_station_hour_weekday_mean":8.2,"py_station_month_mean":6.1}'; echo
# {"predictions": [4.9716]}

```

Verified: 200 single, 200 batch, 400 on missing features, 204 on preflight,
404 on an unknown route. Cold call ~2.7s, warm ~0.17s.

The route is public and unauthenticated - fine for a demo endpoint serving a
public-data model, and it is what CloudFront will sit in front of in phase 4.
Add throttling or an api key here if that changes.
