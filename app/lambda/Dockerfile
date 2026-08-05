# Lambda container image: deps and model baked in, nothing fetched at runtime.
#
# Build (from the repo root, so the model/ directory is in context):
#   docker build -t bike-ml-api app/lambda/
#
# Run locally - the base image ships the runtime interface emulator, so this
# behaves as the deployed function does:
#   docker run --rm -p 9000:8080 bike-ml-api
FROM public.ecr.aws/lambda/python:3.12

# Dependencies first: they change far less often than the handler, so this
# layer stays cached across code edits.
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Only model.joblib - model.skops is the archival copy and would add 11MB to
# every pull for nothing, and metrics.json is a training record.
COPY model/model.joblib ${LAMBDA_TASK_ROOT}/model/

# Prior-year lookups, ~250KB. Baked in for the same reason as the model: the
# alternative is a feature store queried per request, for two numbers that
# change once a year. Regenerate with build_features.py after a retrain.
COPY features/ ${LAMBDA_TASK_ROOT}/features/

COPY handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
