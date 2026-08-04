"""Submit mlops/train.py as a SageMaker training job.

Runs the same script that runs locally, on managed compute, against the split
already on S3. Writes model.tar.gz (model.skops + metrics.json) under
s3://<bucket>/trains/<job-name>/.

The bucket and role come from Terraform, which owns them:

    python mlops/submit.py \
      --bucket $(terraform -chdir=infra output -raw ml_bucket_name) \
      --role $(terraform -chdir=infra output -raw sagemaker_execution_role_arn)

Add --dry-run to print the plan without submitting, or --no-wait to return as
soon as the job starts.

Requires mlops/requirements-dev.txt on the laptop; the container installs
mlops/requirements.txt itself.
"""

from __future__ import annotations

import argparse
import sys

import boto3
from sagemaker.inputs import TrainingInput
from sagemaker.session import Session
from sagemaker.sklearn.estimator import SKLearn

REGION = "ca-central-1"
SPLIT_PREFIX = "data/split/"
OUTPUT_PREFIX = "trains/"

# Pinned because image_uris.retrieve() rejects this tag - it is in ECR but not
# in the registry bundled with sagemaker 2.x. py312 is required, not preferred:
# the default 1.4-2 image runs Python 3.10, and scikit-learn 1.9.0 needs >=3.11.
IMAGE_URI = (
    "341280168497.dkr.ecr.ca-central-1.amazonaws.com/"
    "sagemaker-scikit-learn:1.4-2-py312-cpu-py3"
)

INSTANCE_TYPE = "ml.m5.xlarge"

# Runaway guard, not an estimate - training takes ~3 min.
MAX_RUN_SECONDS = 45 * 60


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--bucket",
        required=True,
        help="ml bucket name (terraform output ml_bucket_name)",
    )
    p.add_argument(
        "--role",
        required=True,
        help="execution role arn (terraform output sagemaker_execution_role_arn)",
    )
    p.add_argument("--quantile", type=float, default=0.8)
    p.add_argument("--instance-type", default=INSTANCE_TYPE)
    p.add_argument(
        "--no-wait",
        action="store_true",
        help="return once submitted instead of streaming logs",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="print the job configuration without submitting",
    )

    args = p.parse_args()

    if not 0 < args.quantile < 1:
        p.error(f"--quantile must be in (0, 1), got {args.quantile}")
    if not args.role.startswith("arn:aws:iam::"):
        p.error(f"--role must be an IAM role arn, got {args.role}")

    return args


def main() -> None:
    args = parse_args()

    # Streamed container logs crash the waiter on a cp1252 console mid-job. The
    # job is unaffected, but the traceback reads like a training failure.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    boto_session = boto3.Session(region_name=REGION)
    split = f"s3://{args.bucket}/{SPLIT_PREFIX}"
    output = f"s3://{args.bucket}/{OUTPUT_PREFIX}"

    print(f"region    {REGION}")
    print(f"role      {args.role}")
    print(f"image     {IMAGE_URI.split('/')[-1]}")
    print(f"instance  {args.instance_type}")
    print(f"input     {split}")
    print(f"output    {output}")
    print(f"quantile  q{int(args.quantile * 100)}")

    if args.dry_run:
        print("\ndry run - nothing submitted")
        return

    estimator = SKLearn(
        entry_point="train.py",
        source_dir="mlops",
        role=args.role,
        instance_type=args.instance_type,
        instance_count=1,
        image_uri=IMAGE_URI,
        hyperparameters={"quantile": args.quantile},
        output_path=output,
        # Without this the source tarball lands in the bucket root, apart from
        # the model it produced.
        code_location=output,
        max_run=MAX_RUN_SECONDS,
        base_job_name=f"annual-demand-q{int(args.quantile * 100)}",
        sagemaker_session=Session(boto_session=boto_session),
    )

    # Channel name must stay "split" - train.py reads SM_CHANNEL_SPLIT.
    estimator.fit(
        {"split": TrainingInput(split, distribution="FullyReplicated")},
        wait=not args.no_wait,
    )

    print(f"\njob       {estimator.latest_training_job.name}")
    if args.no_wait:
        print("submitted - not waiting")
    else:
        print(f"model     {estimator.model_data}")


if __name__ == "__main__":
    main()
