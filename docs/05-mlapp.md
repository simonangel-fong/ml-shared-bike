# ML Application

[Back](../README.md)

- [ML Application](#ml-application)
  - [ML application Deployment Design](#ml-application-deployment-design)
    - [Lambda vs. SageMaker endpoint](#lambda-vs-sagemaker-endpoint)
    - [Routing](#routing)
  - [Implementation Phases](#implementation-phases)
  - [Development](#development)
    - [Lambda function](#lambda-function)
    - [Build and push image](#build-and-push-image)
    - [API gateway](#api-gateway)
    - [DNS](#dns)
    - [Feature derivation](#feature-derivation)
    - [CICD](#cicd)

---

## ML application Deployment Design

### Lambda vs. SageMaker endpoint

- SageMaker endpoint attempt
  - never reached `InService`
  - debug
    - Python 3.9 to 3.12;
    - from skops to joblib
  - outcome:
    - failure due to `No module named 'inference'` error.
  - solution: work around by lambda

- Why lambda:
  - The model is 11MB and a prediction is a single tree-ensemble call.

|                | Lambda (container)       | SageMaker serverless          |
| -------------- | ------------------------ | ----------------------------- |
| model delivery | baked into the image     | pulled from S3 at cold start  |
| dependencies   | baked in, no startup pip | `pip install` on every start  |
| cold start     | ~1-3s                    | ~30-60s                       |
| memory         | up to 10GB               | 1-6GB                         |
| image size     | 10GB max                 | no practical limit            |
| timeout        | 15 min                   | 60s per request               |
| local testing  | identical via RIE        | does not reproduce (verified) |

---

### Routing

```
https://trip-ml.arguswatcher.net/          index.html from s3://<bucket>/web/
https://trip-ml.arguswatcher.net/api/*     api gateway
```

---

## Implementation Phases

| #   | Phase      | Description                                             |
| --- | ---------- | ------------------------------------------------------- |
| 1   | init       | init terraform                                          |
| 2   | lambda     | container image with the model baked in                 |
| 3   | api gtw    | config api gateway                                      |
| 4   | cloudfront | forward api; s3 origin added with the site              |
| 5   | s3 website | config html, s3 key: `web/`                             |
| 6   | cloudflare | config cloudflare dns `trip-ml.arguswatcher.net`        |
| 7   | cicd       | github actions workflow(docker image + terraform apply) |

---

## Development

```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra plan
terraform -chdir=infra apply -auto-approve
```

---

### Lambda function

```sh
# fetch the model for local development
aws s3 cp s3://toronto-shared-bike-ml-ud3m7h/trains/annual-demand-q80-2026-08-04-22-00-42-965/output/model.tar.gz
# unzip
tar -xzO model.joblib > app/lambda/model/model.joblib

docker build -t shared-bike-ml-api app/lambda/
docker run --rm -d --name shared-bike-ml-api  -p 8080:8080 bike-ml-api

# local test
# station
curl -s -XPOST "http://localhost:8080/2015-03-31/functions/function/invocations" -d '{"rawPath":"/api/stations"}'
# {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": "{\"stations\": [{\"id\": 7000, \"name\": \"Fort York Blvd / Capreol Ct\"}, {\"id\": 7001, \"name\": \"Wellesley Station Green P\"}, {\"id\": 7002, \"name\": \"St. George St / Bloor St W\"}, {\"id\": 7006, \"name\": \"Bay St / College St (East Side)\"}, {\"id\": 7007, \"name\": \"College St / Huron St\"}, {\"id\": 7012, \"name\": \"Elizabeth St / Edward St (Bus Terminal)\"}, {\"id\": 7014, \"name\": \"Sherbourne St / Carlton St (Allan Gardens)\"}, {\"id\": 7015, \"name\": \"King St W / Bay St (West Side)\"}, {\"id\": 7016, \"name\": \"Bay St / Queens Quay W (Ferry Terminal)\"}, {\"id\": 7020, \"name\": \"Phoebe St / Spadina Ave\"},

# predict
curl -s -XPOST "http://localhost:8080/2015-03-31/functions/function/invocations" -d '{"rawPath":"/api/forecast","body":"{\"station_id\":7000,\"date\":\"2023-07-19\",\"hour\":17}"}'; echo
# {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": "{\"predictions\": [6.3166]}"}

# batch
 curl -s -XPOST "http://localhost:8080/2015-03-31/functions/function/invocations" -d '{"rawPath":"/api/forecast","body":"{\"instances\":[{\"station_id\":7000,\"date\":\"2023-07-19\",\"hour\":8},{\"station_id\":7000,\"date\":\"2023-07-19\",\"hour\":17}]}"}'; echo
# {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": "{\"predictions\": [3.4854, 6.3166]}"}

# error handling
curl -s -XPOST "http://localhost:8080/2015-03-31/functions/function/invocations" -d '{"rawPath":"/api/forecast","body":"{\"station_id\":9999,\"date\":\"2023-07-19\",\"hour\":17}"}'

curl -s -XPOST "http://localhost:8080/2015-03-31/functions/function/invocations" -d '{"rawPath":"/api/forecast","body":"{\"station_id\":9999,\"date\":\"2023-07-19\",\"hour\":17}"}';echo
# {"statusCode": 400, "headers": {"Content-Type": "application/json"}, "body": "{\"error\": \"unknown station_id: 9999\"}"}
```

---

### Build and push image

```sh
aws ecr get-login-password --region ca-central-1 \
  | docker login --username AWS --password-stdin 099139718958.dkr.ecr.ca-central-1.amazonaws.com

terraform -chdir=infra output -raw ecr_repository_url
# 099139718958.dkr.ecr.ca-central-1.amazonaws.com/toronto-shared-bike-ml-api

# tag = v1
docker buildx build --platform linux/amd64 --provenance=false --sbom=false --output "type=image,name=099139718958.dkr.ecr.ca-central-1.amazonaws.com/toronto-shared-bike-ml-api:v1,oci-mediatypes=false,push=true" app/lambda/
```

---

### API gateway

```sh
terraform -chdir=infra output -raw api_gtw_url
# https://twn44lawi3.execute-api.ca-central-1.amazonaws.com

# test: stations
curl -s "https://twn44lawi3.execute-api.ca-central-1.amazonaws.com/stations"
# {"stations": [{"id": 7000, "name": "Fort York Blvd / Capreol Ct"}, {"id": 7001, "name": "Wellesley Station Green P"}, {"id": 7002, "name": "St. George St / Bloor St W"}, {"id": 7006, "name": "Bay St / College St (East Side)"}, {"id": 7007, "name": "College St / Huron St"}, {"id": 7012, "name": "Elizabeth St / Edward St (Bus Terminal)"}, {"id": 7014, "name": "Sherbourne St / Carlton St (Allan Gardens)"},

# forecast - station, date, hour
curl -s -XPOST "https://twn44lawi3.execute-api.ca-central-1.amazonaws.com/forecast" -H "Content-Type: application/json" -d '{"station_id":7000,"date":"2023-07-19","hour":17}'; echo
# {"predictions": [6.3166]}

# forecast - batch
curl -s -XPOST "https://twn44lawi3.execute-api.ca-central-1.amazonaws.com/forecast" -H "Content-Type: application/json" -d '{"instances":[{"station_id":7000,"date":"2023-07-19","hour":8},{"station_id":7000,"date":"2023-07-19","hour":17}]}'; echo
# {"predictions": [3.4854, 6.3166]}

# error handling
curl -s -XPOST "https://twn44lawi3.execute-api.ca-central-1.amazonaws.com/forecast" -H "Content-Type: application/json" -d '{"station_id":9999,"date":"2023-07-19","hour":17}'; echo
# {"error": "unknown station_id: 9999"}
```

---

### DNS

```sh
ping -c4 trip-ml.arguswatcher.net
# PING d2kuc4p3xrybk9.cloudfront.net (13.227.246.89) 56(84) bytes of data.
# 64 bytes from server-13-227-246-89.yto53.r.cloudfront.net (13.227.246.89): icmp_seq=1 ttl=247 time=22.2 ms
# 64 bytes from server-13-227-246-89.yto53.r.cloudfront.net (13.227.246.89): icmp_seq=2 ttl=247 time=16.8 ms
# 64 bytes from server-13-227-246-89.yto53.r.cloudfront.net (13.227.246.89): icmp_seq=3 ttl=247 time=22.7 ms
# 64 bytes from server-13-227-246-89.yto53.r.cloudfront.net (13.227.246.89): icmp_seq=4 ttl=247 time=16.6 ms

# --- d2kuc4p3xrybk9.cloudfront.net ping statistics ---
# 4 packets transmitted, 4 received, 0% packet loss, time 3168ms
# rtt min/avg/max/mdev = 16.593/19.554/22.665/2.888 ms

# the site
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" "https://trip-ml.arguswatcher.net/"
# 200 text/html; charset=utf-8

# http is redirected, not served
curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}\n" "http://trip-ml.arguswatcher.net/"
# 301 -> https://trip-ml.arguswatcher.net/

# the wildcard cert is what CloudFront presents
echo | openssl s_client -connect trip-ml.arguswatcher.net:443 -servername trip-ml.arguswatcher.net 2>/dev/null \
  | openssl x509 -noout -subject -issuer
# subject=CN=*.arguswatcher.net
# issuer=C=US, O=Amazon, CN=Amazon RSA 2048 M01

# api under /api/ - same origin as the page, so the browser never preflights
curl -s "https://trip-ml.arguswatcher.net/api/stations"
# {"stations": [{"id": 7000, "name": "Fort York Blvd / Capreol Ct"}, {"id": 7001, "name": "Wellesley Station Green P"}, {"id": 7002, "name": "St. George St / Bloor St W"}, {"id": 7006, "name": "Bay St / College St (East Side)"}, {"id": 7007, "name": "College St / Huron St"}, {"id": 7012, "name": "Elizabeth St / Edward St (Bus Terminal)"}, {"id": 7014, "name": "Sherbourne St / Carlton St (Allan Gardens)"}, {"id": 7015, "name": "King St W / Bay St (West Side)"}, {"id": 7016, "name": "Bay St / Queens Quay W (Ferry Terminal)"}, {"id": 7020, "name": "Phoebe St / Spadina Ave"},

curl -s -XPOST "https://trip-ml.arguswatcher.net/api/forecast" -H "Content-Type: application/json" -d '{"station_id":7000,"date":"2023-07-19","hour":17}'; echo
# {"predictions": [6.3166]}

curl -s -XPOST "https://trip-ml.arguswatcher.net/api/forecast" -H "Content-Type: application/json" -d '{"instances":[{"station_id":7000,"date":"2023-07-19","hour":8},{"station_id":7000,"date":"2023-07-19","hour":17}]}'; echo
# {"predictions": [3.4854, 6.3166]}

curl -s -XPOST "https://trip-ml.arguswatcher.net/api/forecast" -H "Content-Type: application/json" -d '{"station_id":9999,"date":"2023-07-19","hour":17}'; echo
# {"error": "unknown station_id: 9999"}
```

---

### Feature derivation

The model takes 17 features; a user knows three. The gap is closed in the `handler`.

| group    | features                                                                                       | source                     |
| -------- | ---------------------------------------------------------------------------------------------- | -------------------------- |
| user     | `station_id`, date, `hour`                                                                     | the request                |
| calendar | `season`, `quarter`, `month`, `weekday`, `week_of_year`, `is_weekend`, `is_holiday`, 6 sin/cos | derived in `handler.py`    |
| history  | `py_station_hour_weekday_mean`, `py_station_month_mean`                                        | lookup tables in the image |

- The history pair is `mean(trip_count)` of the **prior year**, keyed on `(station, hour, weekday)` and `(station, month)`.
- `build_features.py` writes `features/*.json` (~250KB, 12,264 + 803 keys) from `ml/data/split/annual/test.parquet`.

- `weekday` is **Sunday=1..Saturday=7** (Spark), not python's Monday=0
- `is_holiday` follows the pipeline's list, which omits Family Day in 2019 and the August civic holiday entirely

---

### CICD

```sh
gh workflow run app-infra.yml

gh run view
```