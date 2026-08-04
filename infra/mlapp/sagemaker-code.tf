# sagemaker-code.tf

# Packages app/inference/ and uploads it beside the model. The container reads
# SAGEMAKER_SUBMIT_DIRECTORY, downloads this tarball, pip-installs its
# requirements.txt, then imports SAGEMAKER_PROGRAM.
#
# archive_file only produces zips and SageMaker requires tar.gz, so the tarball
# is built by local-exec. --sort=name and a fixed mtime keep the bytes stable
# across runs, so an unchanged source dir does not churn the endpoint.

locals {
  inference_files = fileset(local.inference_src_dir, "*")

  # Any content change re-tars and re-uploads; the etag then rolls the model.
  inference_hash = md5(join("", [
    for f in sort(tolist(local.inference_files)) :
    "${f}:${filemd5("${local.inference_src_dir}/${f}")}"
  ]))

  serve_tarball = "${path.module}/.terraform/tmp/sourcedir.tar.gz"
}

resource "null_resource" "package_inference" {
  triggers = {
    inference_hash = local.inference_hash
    tarball        = local.serve_tarball
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      mkdir -p "$(dirname '${local.serve_tarball}')"
      tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0 --numeric-owner \
        -czf '${local.serve_tarball}' \
        -C '${local.inference_src_dir}' ${join(" ", sort(tolist(local.inference_files)))}
    EOT
  }
}

resource "aws_s3_object" "inference_source" {
  bucket = data.aws_s3_bucket.ml.id
  key    = local.serve_source_key
  source = local.serve_tarball

  # local-exec runs at apply, so the file does not exist at plan time on a
  # fresh checkout. Keying on the content hash instead of filemd5() lets the
  # plan resolve without it.
  etag = local.inference_hash

  depends_on = [null_resource.package_inference]
}
