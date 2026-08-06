# MLOps

[Back](../README.md)

- [MLOps](#mlops)
  - [Goal](#goal)
  - [Pipeline](#pipeline)
  - [Files](#files)
  - [Development](#development)
    - [Data to S3](#data-to-s3)
    - [Training job](#training-job)
    - [CI/CD](#cicd)

---

## Goal

**Make it work:** a push to `mlops/` runs the training on SageMaker instead of
on the laptop, and leaves the model on S3. Done.

That was the whole of this stage. Not automatic promotion, not a gate, not
drift. One trigger, one training job, one artifact.

Reference: `ml/notebooks/05-train-quantile.ipynb` - the shipped
`annual-demand-q80` model. The notebooks stay as they are; the job reproduces
their metrics to four decimals.

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
MLflow stays for exploration. Managed MLflow is ~$0.64/hr with no
scale-to-zero - roughly $470/month for a model retrained annually, so not now.

---

## Files

```
mlops/
  train.py                 runs inside the container
  submit.py                builds the estimator, calls .fit()
  requirements.txt         installed in the container - pins sklearn 1.9.0
  requirements-dev.txt     laptop/runner only - sagemaker SDK, pinned <3
.github/workflows/
  mlops-train.yml
infra/
  github-oidc.tf           CI role and trust policy
```

Two scripts. Config lives in `submit.py` as constants until there is a second
model to justify a config file.

`train.py` is notebook steps 1-3 without the plots: read the split from
`/opt/ml/input/data/`, fit, score, write `model.skops` and `metrics.json` to
`/opt/ml/model/`. It keeps the leakage assert (train < val < test by
`start_date`) - three lines against a silent, expensive mistake.

`submit.py` takes `--bucket` and `--role` rather than discovering them: an
earlier version scanned IAM and silently picked up an unmanaged QuickSetup
role. Everything persistent is Terraform's.

S3 layout on `s3_bucket_name`:

```
data/split/              train/val/test parquet + split.json
trains/<job-name>/
  source/sourcedir.tar.gz    uploaded by the SDK
  output/model.tar.gz        model.skops + metrics.json
```

---

## Development

### Data to S3

```sh
terraform -chdir=infra output -raw s3_bucket_name
# toronto-shared-bike-ml-ud3m7h

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

### Training job

Install the submit-side deps once; the container installs
`mlops/requirements.txt` itself.

```sh
pip install -r mlops/requirements-dev.txt
```

The bucket and role are Terraform's, so pass them from its outputs rather than
hardcoding. Check the plan before spending anything:

```sh
terraform -chdir=infra output -raw s3_bucket_name
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

![sagemaker_training_job01](./img/sagemaker_training_job01.png)

- confirm

```sh
JOB=annual-demand-q80-2026-08-04-20-06-15-076
aws s3 cp s3://toronto-shared-bike-ml-ud3m7h/trains/$JOB/output/model.tar.gz .
tar -xzf model.tar.gz && cat metrics.json
# "sklearn_version": "1.9.0"
# "MAE": 1.0451602991462254 ...
```

---

### CI/CD

GitHub Actions Variables

| Variable             | From                                                                     |
| -------------------- | ------------------------------------------------------------------------ |
| `AWS_OIDC_ROLE_ARN`  | `terraform -chdir=infra output -raw github_actions_role_arn` output      |
| `S3_BUCKET`          | `terraform -chdir=infra output -raw s3_bucket_name` output               |
| `SAGEMAKER_ROLE_ARN` | `terraform -chdir=infra output -raw sagemaker_execution_role_arn` output |

```sh
terraform -chdir=infra output
```

Run from the Actions tab, or:

```sh
# no cost - checks OIDC and the variables without submitting
gh workflow run mlops-train.yml -f dry_run=true

gh workflow run mlops-train.yml

gh run watch
# ✓ master train · 30953413046
# Triggered via workflow_dispatch about 5 minutes ago
#
# JOBS
# ✓ train in 4m31s (ID 92140740243)
#   ✓ Set up job
#   ✓ Run actions/checkout@v4
#   ✓ Run actions/setup-python@v5
#   ✓ Install submit-side deps
#   ✓ Assume AWS role
#   ✓ Submit training job
#   ✓ Complete job
```

![mlops_github01](./img/mlops_github01.png)
