#   docker build -t bike-ml-api app/lambda/
#   docker run --rm -p 9000:8080 bike-ml-api
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

COPY model/model.joblib ${LAMBDA_TASK_ROOT}/model/

COPY features/ ${LAMBDA_TASK_ROOT}/features/

COPY handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
