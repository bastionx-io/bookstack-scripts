#!/usr/bin/env bash
# Setup only: private configuration and authenticated local distribution payloads.
set +x
set +a
unset source_url endpoint bucket region prefix recipient access_key secret_key confirmation
set -Eeuo pipefail
umask 077
set -o noclobber

if [[ "${1:-}" == --help && $# == 1 ]]; then
  cat <<'EOF'
Usage: sudo bash 02-configure-backup.sh [--help]
Setup only; run deliberately as authorized root on the client VM, from a TTY.
Requires local lib/bookstack-dr-backup and lib/bookstack-dr-backup.service,
age, python3, systemctl and standard Linux utilities; installs no dependencies.
Prompts for reviewed source APP_URL, S3 HTTPS endpoint, bucket, region, prefix,
age PUBLIC recipient, and S3 access/secret keys. No defaults for these inputs.
Credentials are read silently from the terminal, never arguments/environment.
Never enter a private identity, APP_KEY or database password. Do not share secret
input, terminal recordings, or screenshots of private keys.
Writes only protected configuration/state/runtime directories, runtime and unit;
then systemctl daemon-reload. No preflight, dump, upload, job start/enable, timer,
reboot, restart, application .env access or remote asset download.
Existing destinations/units are refused. No overwrite, update or cleanup mode;
partial state is retained on failure. Separate readiness approval is required
before preflight or a supervised service run.
EOF
  exit 0
fi
fatal() { printf '%s\n' "$*; stop for review (no automatic cleanup)." >&2; exit 1; }
(( $# == 0 )) || fatal 'Unexpected arguments; use --help'
[[ "$(id -u)" == 0 ]] || fatal 'Run only as authorized root: sudo bash 02-configure-backup.sh'
[[ -t 0 && -t 1 ]] || fatal 'Interactive terminal required; do not pipe inputs or log the session'
exec 3<>/dev/tty
trap 'printf "Setup failed; retain partial state for private review. No job was started.\n" >&2' ERR
for command_name in age python3 systemctl sha256sum stat dirname cat install chmod stty; do
  command -v "$command_name" >/dev/null 2>&1 || fatal 'Required local tool missing'
done

# Hash the in-memory snapshots that will be installed, not mutable source paths.
asset_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib"
for asset in bookstack-dr-backup bookstack-dr-backup.service; do
  [[ -f "$asset_dir/$asset" && ! -L "$asset_dir/$asset" ]] || fatal 'Missing or symlinked local payload'
done
runtime_payload="$(cat -- "$asset_dir/bookstack-dr-backup"; printf '.')"
runtime_payload="${runtime_payload%.}"
service_payload="$(cat -- "$asset_dir/bookstack-dr-backup.service"; printf '.')"
service_payload="${service_payload%.}"
[[ "$(printf '%s' "$runtime_payload" | sha256sum)" == '772676071058bdeadeeab58a5cce884d6acb42b77b7fc815de6001833d4e1ddc  -' ]] || fatal 'Runtime payload hash mismatch'
[[ "$(printf '%s' "$service_payload" | sha256sum)" == 'ddcc7f56714e5938e620dace48a7e2d96e105412b98c2dc082808f120db97508  -' ]] || fatal 'Service payload hash mismatch'

config_dir=/etc/bookstack-dr-backup
state_dir=/var/lib/bookstack-dr-backup
run_dir=/run/bookstack-dr-backup
runtime=/usr/local/sbin/bookstack-dr-backup
unit=/etc/systemd/system/bookstack-dr-backup.service

check_targets() {
  local path parent owner mode unit_name unit_state unit_overrides
  for path in "$config_dir" "$state_dir" "$run_dir" "$runtime" "$unit" "${unit}.d" "${unit%.service}.timer" "${unit%.service}.timer.d"; do
    [[ ! -e "$path" && ! -L "$path" ]] || fatal 'Existing destination or unit override'
    parent="$(dirname -- "$path")"
    while :; do
      [[ -d "$parent" && ! -L "$parent" ]] || fatal 'Missing or symlinked destination parent'
      read -r owner mode < <(stat -c '%u %a' -- "$parent")
      [[ "$owner" == 0 ]] && (( (8#$mode & 022) == 0 )) || fatal 'Destination parent must be root-owned and not group/other writable'
      [[ "$parent" != / ]] || break
      parent="$(dirname -- "$parent")"
    done
  done
  for unit_name in bookstack-dr-backup.service bookstack-dr-backup.timer; do
    unit_state="$(systemctl show --property=LoadState --value "$unit_name")" || fatal 'Cannot inspect installed units'
    unit_overrides="$(systemctl show --property=DropInPaths --value "$unit_name")" || fatal 'Cannot inspect unit overrides'
    [[ "$unit_state" == not-found && -z "$unit_overrides" ]] || fatal 'Unexpected existing unit or override'
  done
}
check_targets

tty_state="$(stty -g <&3)"
trap 'stty "$tty_state" <&3' EXIT
trap 'fatal "Setup interrupted"' INT TERM HUP
stty -echo <&3
printf '%s\n' 'Setup only. Enter reviewed private values locally; all inputs are hidden.' \
  'Never enter a private identity, APP_KEY or database password. Do not share secret input,' \
  'terminal recordings or screenshots of private keys. No application .env is read.' \
  'Confirm the exact prefix matches the separately reviewed retention lifecycle; setup does not apply it.' >&3
read_field() {
  printf '%s: ' "$2" >&3
  IFS= read -r -s -u 3 "$1" || fatal 'Input interrupted'
  printf '\n' >&3
  [[ -n "${!1}" && "${!1}" != *AGE-SECRET* && "${!1}" != *PRIVATE*KEY* && "${!1}" != *$'\r'* ]] || fatal 'Empty input or forbidden key/control material'
}
read_field source_url 'Source APP_URL (reviewed HTTPS URL)'
read_field endpoint 'S3 endpoint (reviewed HTTPS URL)'
read_field bucket 'S3 bucket (reviewed exact name)'
read_field region 'S3 region (reviewed exact value)'
read_field prefix 'S3 prefix (reviewed lifecycle-matching value, no leading/trailing slash)'
read_field recipient 'age PUBLIC recipient (age1...)'
read_field access_key 'S3 access key ID (hidden)'
read_field secret_key 'S3 secret access key (hidden)'

# Values go over stdin, not process arguments or environment. No network calls.
if ! printf '%s\n' "$source_url" "$endpoint" "$bucket" "$region" "$prefix" "$recipient" "$access_key" "$secret_key" | python3 -c '
import ipaddress, re, sys
from urllib.parse import urlsplit
values = sys.stdin.read().splitlines()
if len(values) != 8:
    sys.exit(1)
source, endpoint, bucket, region, prefix, recipient, access, secret = values

def https_url(value):
    if not re.fullmatch(r"[\x21-\x7e]+", value) or any(c in value for c in "@?#\\%"):
        return False
    try:
        url = urlsplit(value)
        host = url.hostname
        port = url.port
        if url.scheme != "https" or not host or url.username is not None or url.password is not None:
            return False
        if port is not None and not 1 <= port <= 65535:
            return False
        if url.netloc.endswith(":"):
            return False
        try:
            ipaddress.ip_address(host)
        except ValueError:
            if len(host) > 253 or not all(re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?", part) for part in host.split(".")):
                return False
        return not url.path or re.fullmatch(r"/[A-Za-z0-9/._~-]*", url.path) is not None
    except ValueError:
        return False

valid = https_url(source) and https_url(endpoint)
valid = valid and bool(re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket))
valid = valid and not any(part in bucket for part in ("..", ".-", "-."))
try:
    ipaddress.ip_address(bucket)
    valid = False
except ValueError:
    pass
valid = valid and bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,62}", region))
valid = valid and len(prefix) <= 512 and bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*(?:/[A-Za-z0-9][A-Za-z0-9_-]*)*", prefix))
valid = valid and bool(re.fullmatch(r"age1[023456789acdefghjklmnpqrstuvwxyz]{58}", recipient))
valid = valid and all(re.fullmatch(r"[A-Za-z0-9/+=._-]{1,256}", key) for key in (access, secret))
sys.exit(0 if valid else 1)
'; then
  fatal 'Invalid input format (values withheld)'
fi
# Only a native public recipient is accepted: no plugins, identities or network.
age --encrypt --recipient "$recipient" </dev/null >/dev/null 2>&1 || fatal 'Invalid age public recipient'

printf '%s\n' 'Confirm: writes only private config, state/run directories, runtime and service unit,' \
  'then daemon-reload. NO preflight, dump, upload, start/enable or timer.' >&3
read_field confirmation 'Type INSTALL SETUP ONLY to authorize these writes'
[[ "$confirmation" == 'INSTALL SETUP ONLY' ]] || fatal 'Not confirmed'
check_targets

install -d -o 0 -g 0 -m 0700 -- "$config_dir" "$state_dir" "$run_dir"
install -d -o 0 -g 0 -m 0700 -- "$state_dir/staging"
{
  printf 'SOURCE_APP_URL=%q\nS3_ENDPOINT_URL=%q\nS3_BUCKET=%q\nS3_PREFIX=%q\nAWS_REGION=%q\n' "$source_url" "$endpoint" "$bucket" "$prefix" "$region"
  printf 'AWS_PROFILE=%q\nMYSQL_DEFAULTS_FILE=%q\n' bookstack-backup ''
} > "$config_dir/config"
{
  printf '[profile bookstack-backup]\nregion = %s\n' "$region"
  printf 's3 =\n    addressing_style = path\n    signature_version = s3v4\n    max_concurrent_requests = 2\n    max_bandwidth = 1MB/s\n'
} > "$config_dir/aws-config"
{
  printf '[bookstack-backup]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$access_key" "$secret_key"
} > "$config_dir/aws-credentials"
printf '%s\n' "$recipient" > "$config_dir/age-recipient.txt"
chmod 0600 -- "$config_dir/config" "$config_dir/aws-config" "$config_dir/aws-credentials" "$config_dir/age-recipient.txt"
unset access_key secret_key
printf '%s' "$runtime_payload" | install -o 0 -g 0 -m 0755 -- /dev/stdin "$runtime"
printf '%s' "$service_payload" | install -o 0 -g 0 -m 0644 -- /dev/stdin "$unit"
systemctl daemon-reload
printf '%s\n' 'Setup installed; no job started or enabled. Stop here for separate readiness review.'
