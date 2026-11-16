#!/usr/bin/env bash
(
set +x
set +a
unset access_key secret_key
if [[ $# == 1 && "$1" == --help ]]; then
  printf '%s\n' 'Usage: bash 03-check-garage-access.sh ENDPOINT REGION BUCKET' 'HeadBucket only; prompts for both credentials (hidden).'
  exit 0
fi
if [[ $# != 3 || "${1:-}" != https://* ]]; then
  printf '%s\n' 'Usage: bash 03-check-garage-access.sh ENDPOINT REGION BUCKET (HTTPS required)' >&2
  exit 1
fi
if ! IFS= read -rsp 'S3 access key ID (hidden): ' access_key; then
  printf '\nCredential input failed.\n' >&2
  exit 1
fi
printf '\n'
if ! IFS= read -rsp 'S3 secret access key (hidden): ' secret_key; then
  printf '\nCredential input failed.\n' >&2
  exit 1
fi
printf '\n'
if [[ -z "$access_key" || -z "$secret_key" ]]; then
  printf '%s\n' 'Both credentials must be nonempty.' >&2
  exit 1
fi
unset AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true AWS_PAGER='' AWS_MAX_ATTEMPTS=1 AWS_CLI_AUTO_PROMPT=off
export AWS_ACCESS_KEY_ID="$access_key" AWS_SECRET_ACCESS_KEY="$secret_key"
unset access_key secret_key
if timeout --kill-after=5s 30s aws --endpoint-url "$1" --region "$2" \
  --cli-connect-timeout 5 --cli-read-timeout 10 s3api head-bucket --bucket "$3"; then
  printf '%s\n' 'Success: credentials/basic bucket access work (HeadBucket only; does not prove PUT).'
else
  status=$?
  printf 'Failed (status %s): check credentials, permissions and IP allowlist. Stop for review.\n' "$status" >&2
  exit "$status"
fi
)
