# ML application

[Back](../README.md)

- [ML application](#ml-application)
  - [Goal](#goal)
  - [Why Lambda, not a SageMaker endpoint](#why-lambda-not-a-sagemaker-endpoint)
  - [Phases](#phases)
  - [Development](#development)
    - [Phase 2: lambda](#phase-2-lambda)
    - [Phase 3: api gateway](#phase-3-api-gateway)
    - [Phase 4: cloudfront](#phase-4-cloudfront)
    - [Phase 6: custom domain](#phase-6-custom-domain)
    - [Gating](#gating)

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
| 4   | cloudfront | forward api; s3 origin added with the site       |
| 5   | s3 website | config html, s3 key: `web/`                      |
| 6   | cloudflare | config cloudflare dns `trip-ml.arguswatcher.net` |

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
public-data model, and it is what CloudFront sits in front of in phase 4.
Add throttling or an api key here if that changes.

---

### Phase 4: cloudfront

One distribution, api gateway as the only origin. The s3 site gets added as a
second origin under its own path pattern when the site exists.

```
POST https://<dist>.cloudfront.net/predict
```

There is no caching value in fronting a POST-only api. What it buys is TLS
terminated at the edge, a stable hostname for the phase 6 dns record, and a
single front door for the api and the site.

Two settings matter, and both fail quietly if wrong:

- **Caching disabled** (AWS's `Managed-CachingDisabled`). CloudFront does not
  key its cache on the request body, so a cached POST would serve one caller's
  prediction to another. Verified: two different feature vectors returned
  different predictions with `X-Cache: Miss from cloudfront`. Note a custom
  policy with all TTLs at zero is rejected - `EnableAcceptEncodingGzip` is not
  allowed when caching is disabled - hence the managed one.
- **Host not forwarded.** The origin request policy whitelists `content-type`,
  `origin` and `accept`. Forwarding `Host` sends the CloudFront hostname to api
  gateway, which routes on it and answers 403.

`OPTIONS` is in `allowed_methods` so the browser preflight reaches the gateway;
CloudFront would otherwise reject it before the gateway ever saw it. CORS
itself is still answered by api gateway.

```sh
terraform -chdir=infra output -raw cloudfront_predict_url
# https://d2kuc4p3xrybk9.cloudfront.net/predict

curl -s -XPOST "https://d2kuc4p3xrybk9.cloudfront.net/predict" -H 'Content-Type: application/json' -d '{"station_id":7000,"season":"summer","hour":17,"quarter":3,"month":7,"weekday":2,"week_of_year":28,"is_weekend":0,"is_holiday":0,"hour_sin":-0.2588,"hour_cos":-0.9659,"weekday_sin":0.7818,"weekday_cos":0.6235,"month_sin":-0.5,"month_cos":-0.866,"py_station_hour_weekday_mean":8.2,"py_station_month_mean":6.1}'
# {"predictions": [4.9716]}
```

Verified: 200 single, 200 with a different vector and `X-Cache: Miss`, 204 on
preflight, 307 http -> https. Warm call ~0.17s.

`PriceClass_100` (NA + Europe) - the audience is Toronto.

---

### Phase 6: custom domain

```
POST https://trip-ml.arguswatcher.net/predict
```

Two pieces: an ACM cert on the distribution, and a Cloudflare CNAME to it.

The cert is looked up by domain rather than passed as an arn, through a
`us_east_1` aliased provider - CloudFront reads viewer certificates from
us-east-1 only, whatever region it serves from. The existing
`*.arguswatcher.net` wildcard covers this and any future subdomain.

```hcl
data "aws_acm_certificate" "this" {
  provider    = aws.us_east_1
  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}
```

The dns record is **not proxied**. Proxying puts Cloudflare in front of
CloudFront, and Cloudflare's request carries its own SNI, which does not match
the distribution alias - CloudFront answers 403. It looks like a certificate
problem and is not one.

The Cloudflare provider validates credentials when it is configured, not when a
resource uses it, so `cloudflare_api_token` has to be set for any apply once the
provider is declared. Keep it in the environment rather than tfvars:

```sh
$env:TF_VAR_cloudflare_api_token = "..."
```

```sh
curl -s -XPOST "https://trip-ml.arguswatcher.net/predict" -H 'Content-Type: application/json' -d '{"station_id":7000,"season":"summer","hour":17,"quarter":3,"month":7,"weekday":2,"week_of_year":28,"is_weekend":0,"is_holiday":0,"hour_sin":-0.2588,"hour_cos":-0.9659,"weekday_sin":0.7818,"weekday_cos":0.6235,"month_sin":-0.5,"month_cos":-0.866,"py_station_hour_weekday_mean":8.2,"py_station_month_mean":6.1}'; echo
# {"predictions": [4.9716]}
```

Verified: TLS validates, 200 on POST, 204 on preflight, warm ~0.16s.

---

### Feature derivation

The model takes 17 features; a user knows three. The gap is closed in the
handler, not the browser.

| group    | features                                            | source                  |
| -------- | --------------------------------------------------- | ----------------------- |
| user     | `station_id`, date, `hour`                          | the request             |
| calendar | `season`, `quarter`, `month`, `weekday`, `week_of_year`, `is_weekend`, `is_holiday`, 6 sin/cos | derived in `handler.py` |
| history  | `py_station_hour_weekday_mean`, `py_station_month_mean` | lookup tables in the image |

The history pair is `mean(trip_count)` of the **prior year**, keyed on
`(station, hour, weekday)` and `(station, month)`. Verified by recomputing them
from the training data: corr 1.000000, max abs diff 0.0. So the 2022 split
generates exactly what a 2023 prediction needs - **this build serves 2023**.

`build_features.py` writes `features/*.json` (~250KB, 12,264 + 803 keys) from
`ml/data/split/annual/test.parquet`. That curated split, not the raw
`featured/year=2022`, which holds 76 stations and is missing 14 of the model's
73.

Deriving in the browser was rejected: it would be a second implementation of
the feature logic in another language, and a convention mismatch there is
silent. Two were found here by testing against real rows:

- `weekday` is **Sunday=1..Saturday=7** (Spark), not python's Monday=0
- `is_holiday` follows the pipeline's list, which omits Family Day in 2019 and
  the August civic holiday entirely

Both produced plausible, wrong predictions. `test_features.py` rebuilds every
derived column for 2,000 real rows and compares - run it after any change:

```sh
docker run --rm --entrypoint bash \
  -v "$PWD/app/lambda:/app" -v "$PWD/ml/data/split/annual:/d" \
  <sklearn-image> -c "cd /app && python test_features.py /d/test.parquet"
# total mismatches: 0
```

A feature store (DynamoDB/S3) would be the general answer, and is the wrong one
here: another resource and a per-request round trip, for two numbers that
change once a year - at which point the image is rebuilt anyway for the
retrained model.

---

### Routes

```sh
D=https://trip-ml.arguswatcher.net

curl -s "$D/stations"
# {"stations": [7000, ...], "target_year": 2023, "history_year": 2022}

curl -s -XPOST "$D/forecast" -H 'Content-Type: application/json' \
  -d '{"station_id":7000,"date":"2023-07-19","hour":17}'
# {"predictions": [6.3166]}

curl -s -XPOST "$D/forecast" -H 'Content-Type: application/json' \
  -d '{"instances":[{"station_id":7000,"date":"2023-07-19","hour":8},{"station_id":7000,"date":"2023-07-19","hour":17}]}'
# {"predictions": [3.4854, 6.3166]}
```

`/predict` still takes all 17 features, for testing and for callers that hold
real vectors. Verified identical: `/forecast` and `/predict` return the same
6.3166 for the same moment.

---

### Gating

One switch, `enable_deployment`, covers lambda, api gateway, cloudfront and
dns. Off leaves the ecr repo and iam in place, so an image can be pushed before
the function that runs it exists - which is the order a first apply needs.
