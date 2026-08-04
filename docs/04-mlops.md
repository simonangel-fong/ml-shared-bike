# MLOps

[Back](../../README.md)

- [MLOps](#mlops)
  - [Goal](#goal)
  - [Pipeline](#pipeline)
  - [Files](#files)
  - [Steps](#steps)
  - [Not now](#not-now)
  - [Devlopment](#devlopment)
    - [Data to S3](#data-to-s3)
    - [Local Run](#local-run)
    - [Training job](#training-job)

---

## Goal

**Make it work:** a push to `mlops/` runs the training on SageMaker instead of
on the laptop, and leaves the model on S3.

That is the whole of this stage. Not automatic promotion, not a gate, not
drift. One trigger, one training job, one artifact.

Reference: `ml/notebooks/05-train-quantile.ipynb` - the shipped
`annual-demand-q80` model. The notebooks stay as they are.

---

## Pipeline

```
push to mlops/ ──► GitHub Actions ──► SageMaker training job ──► S3
                     (submit, wait)      (sklearn container)     (model + metrics.json)
```

Actions submits and waits. All compute is on SageMaker. Nothing is promoted
automatically - read `metrics.json`, and if it looks good, register the model
by hand as today.

**Tracking.** The job writes `metrics.json` next to the model on S3. Local
MLflow stays for exploration. Managed MLflow is ~$0.64/hr with no scale-to-zero

- roughly $470/month for a model retrained annually, so not now.

---

## Files

```
mlops/
  train.py            runs inside the container
  submit.py           builds the estimator, calls .fit()
  requirements.txt
.github/workflows/
  train.yml
```

Two scripts. Config lives in `submit.py` as constants until there is a second
model to justify a config file.

---

## Steps

| #   | Step        | Done when                                             |
| --- | ----------- | ----------------------------------------------------- |
| 1   | Data to S3  | the annual split is on the `ml_data` bucket           |
| 2   | `train.py`  | runs locally, reproduces the notebook's q80 metrics   |
| 3   | `submit.py` | trains on SageMaker from the laptop                   |
| 4   | CI identity | GitHub OIDC role, `PassRole` on `sagemaker_execution` |
| 5   | `train.yml` | a push to `mlops/` produces a model on S3             |

Step 2 is the one that matters. If the script does not reproduce the notebook's
numbers, automating it just produces wrong models faster.

`train.py` is notebook steps 1-3 without the plots: read the split from
`/opt/ml/input/data/`, fit, score, write the model and `metrics.json` to
`/opt/ml/model/`. Keep the leakage assert (train < val < test by `start_date`)

- it is three lines and catches a silent, expensive mistake.

Estimator: `sagemaker.sklearn.SKLearn` on `ml.m5.xlarge`, with a max runtime
set so a stuck job cannot bill overnight.

---

## Not now

Each of these is a later stage. Listed so they read as deferred, not forgotten.

| Deferred         | Revisit when                                   |
| ---------------- | ---------------------------------------------- |
| Promotion gate   | the pipeline has run a few times by hand first |
| DVC on `data/`   | data actually changes                          |
| Hosted MLflow    | the cost is justified by retrain frequency     |
| Serving endpoint | there is a consumer for predictions            |
| Drift monitoring | there is production traffic                    |

---

## Devlopment

### Data to S3

```sh
# upload split data to s3
aws s3 cp ml/data/split/annual/ s3://toronto-shared-bike-ml-ud3m7h/data/split/ --recursive --exclude "*" --include "*.parquet" --include "split.json"
# upload: ml\data\split\annual\split.json to s3://toronto-shared-bike-ml-ud3m7h/data/split/split.json
# upload: ml\data\split\annual\test.parquet to s3://toronto-shared-bike-ml-ud3m7h/data/split/test.parquet
# upload: ml\data\split\annual\val.parquet to s3://toronto-shared-bike-ml-ud3m7h/data/split/val.parquet
# upload: ml\data\split\annual\train.parquet to s3://toronto-shared-bike-ml-ud3m7h/data/split/train.parquet

aws s3 ls s3://toronto-shared-bike-ml-ud3m7h/data/split/
# 2026-08-04 15:00:02          0
# 2026-08-04 15:04:11       1566 split.json
# 2026-08-04 15:04:11    3533914 test.parquet
# 2026-08-04 15:04:11    5856389 train.parquet
# 2026-08-04 15:04:11    3739010 val.parquet
```

---

### Local Run

```sh
python mlops/train.py --quantile 0.8
# train 1,280,712 | val   639,480 | test   586,920
# 17 features -> trip_count
# fitted
#
# test 2022
#   MAE                1.0452
#   MAE_peak           1.5513
#   MAE_busy           6.9058
#   under_rate_busy    1.0000
#   shortfall_busy     0.5631
#   pinball            0.3248
#   over_supply        0.8523
#
# wrote model.skops and metrics.json to mlops/output
```

---

### Training job

Install the submit-side deps once; the container installs
`mlops/requirements.txt` itself.

```sh
pip install -r mlops/requirements-dev.txt
```

The bucket and role are Terraform's, so pass them from its outputs rather than
hardcoding. Check the plan before spending anything:

```sh
terraform -chdir=infra output -raw ml_bucket_name
# toronto-shared-bike-ml-ud3m7h

terraform -chdir=infra output -raw sagemaker_execution_role_arn
# arn:aws:iam::099139718958:role/toronto-shared-bike-ml-sagemaker-execution-role

# dry-run
python mlops/submit.py --dry-run --bucket toronto-shared-bike-ml-ud3m7h   --role arn:aws:iam::099139718958:role/toronto-shared-bike-ml-sagemaker-execution-role
# region    ca-central-1
# role      arn:aws:iam::099139718958:role/toronto-shared-bike-ml-sagemaker-execution-role
# image     sagemaker-scikit-learn:1.4-2-py312-cpu-py3
# instance  ml.m5.xlarge
# input     s3://toronto-shared-bike-ml-ud3m7h/data/split/
# output    s3://toronto-shared-bike-ml-ud3m7h/trains/
# quantile  q80

# dry run - nothing submitted

python mlops/submit.py --bucket toronto-shared-bike-ml-ud3m7h   --role arn:aws:iam::099139718958:role/toronto-shared-bike-ml-sagemaker-execution-role
# 2026-08-04 20:32:45 Uploading - Uploading generated training modeltest 2022
#   MAE                1.0452
#   MAE_peak           1.5513
#   MAE_busy           6.9058
#   under_rate_busy    1.0000
#   shortfall_busy     0.5631
#   pinball            0.3248
#   over_supply        0.8523
# wrote model.skops and metrics.json to /opt/ml/model
# 2026-08-04 20:32:41,356 sagemaker-training-toolkit INFO     Reporting training SUCCESS
```

- confirm

```sh
JOB=annual-demand-q80-2026-08-04-20-06-15-076
aws s3 cp s3://toronto-shared-bike-ml-ud3m7h/trains/$JOB/output/model.tar.gz .
tar -xzf model.tar.gz && cat metrics.json
# "sklearn_version": "1.9.0"
# "MAE": 1.0451602991462254 ...
```

The job reproduces the local and notebook metrics to four decimals.

> **Why the `py312` image.** The default `1.4-2` image runs Python 3.10, and
> scikit-learn 1.9.0 - the version behind the reference metrics - requires
> >=3.11. Both images ship sklearn 1.4.2; `mlops/requirements.txt` upgrades it
> in place, which only resolves on 3.12. The image URI is pinned in
> `submit.py` because the SDK's bundled registry does not list that tag.

> Pip prints `sagemaker-sklearn-container 2.0 requires numpy==2.1.0 ...`
> conflicts during the upgrade. Those pins belong to the container's serving
> stack, which training does not use - the job succeeds. They would matter if
> this image were used for inference.

---

### CI

`.github/workflows/train.yml` submits the same job on a push to `mlops/` on
`master`, or on demand. No AWS keys are stored: the workflow exchanges a
GitHub OIDC token for `github_actions_role_arn`, whose trust policy accepts
only this repo on this branch.

One-time setup - three repo variables under **Settings → Secrets and variables
→ Actions → Variables**. None are secret; they are ARNs and a bucket name.

```sh
terraform -chdir=infra output -raw github_actions_role_arn
# arn:aws:iam::099139718958:role/toronto-shared-bike-ml-github-actions-role
```

| Variable             | Value                                       |
| -------------------- | ------------------------------------------- |
| `AWS_ROLE_ARN`       | `github_actions_role_arn` output            |
| `ML_BUCKET`          | `ml_bucket_name` output                     |
| `SAGEMAKER_ROLE_ARN` | `sagemaker_execution_role_arn` output       |

Run it from the Actions tab, or:

```sh
# no cost - checks OIDC and the variables without submitting
gh workflow run train.yml -f dry_run=true

gh workflow run train.yml
gh run watch
```

> Trigger the first run with `dry_run=true`. It exercises the whole identity
> path - assume role, resolve variables, build the estimator - and stops before
> spending anything, so a failure is unambiguously auth or config.

> `cancel-in-progress` is off. Cancelling the runner would abandon the
> SageMaker job rather than stop it, leaving it to bill unwatched.
