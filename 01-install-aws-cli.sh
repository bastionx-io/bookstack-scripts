#!/usr/bin/env bash
# Install only the pinned AWS CLI after official-key and signature verification.
set -euo pipefail
umask 077

if [[ "${1:-}" == --help && $# == 1 ]]; then
  printf '%s\n' 'Usage: bash 01-install-aws-cli.sh [--help]' \
    'Installs AWS CLI 2.40.3 for Linux x86_64, without updating existing installs.' \
    'Run as a normal user; sudo is used only for the verified installer.' \
    'Requires curl, unzip, gpg, python3, sudo and standard Linux utilities.' \
    'Private staging is retained for review, including on failure.'
  exit 0
fi
if (( $# )); then
  printf 'Unexpected arguments; use --help\n' >&2
  exit 1
fi

test "$(uname -m)" = x86_64
for command_name in aws aws_completer; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'Existing command: %s; stop for review\n' "$command_name" >&2
    exit 1
  fi
done
for path in /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer; do
  if test -e "$path" || test -L "$path"; then
    printf 'Existing path: %s; stop for review\n' "$path" >&2
    exit 1
  fi
done
stage=$(mktemp -d /tmp/aws-cli-verify.XXXXXXXX)
trap 'status=$?; if (( status )); then printf "Installation stopped (exit %s); private staging retained: %s\n" "$status" "$stage" >&2; fi' EXIT
printf 'Private staging (retained for review): %s\n' "$stage"
export GNUPGHOME="$stage/gnupg"
mkdir -m 700 "$GNUPGHOME"
cd "$stage"
curl --proto '=https' --proto-redir '=https' --fail --show-error --location \
  --connect-timeout 10 --max-time 60 --max-filesize 2097152 --output install-guide.html \
  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
python3 - <<'PYKEY'
import html, pathlib, re
text = html.unescape(re.sub(r'<[^>]+>', '', pathlib.Path('install-guide.html').read_text()))
keys = set(re.findall(r'-----BEGIN PGP PUBLIC KEY BLOCK-----.*?-----END PGP PUBLIC KEY BLOCK-----', text, re.S))
if len(keys) != 1:
    raise SystemExit('Expected one distinct AWS CLI public key; stop for review')
pathlib.Path('aws-cli-public-key.asc').write_text(keys.pop() + '\n')
PYKEY
fingerprint=FB5DB77FD5C118B80511ADA8A6310ACC4672475C
gpg --no-options --batch --import aws-cli-public-key.asc
gpg --no-options --batch --with-colons --fingerprint > key.status
actual=$(awk -F: '$1 == "pub" {primary=1} $1 == "sub" {primary=0}
  $1 == "fpr" && primary {print $10; primary=0}' key.status)
test "$actual" = "$fingerprint"
awk -F: -v now="$(date +%s)" '
  $1 == "pub" && ($2 ~ /[er]/ || ($7 != "" && $7 != 0 && $7 <= now)) {bad=1}
  END {exit bad}' key.status
url=https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.40.3.zip
curl --proto '=https' --proto-redir '=https' --fail --show-error --location \
  --connect-timeout 10 --max-time 300 --output awscliv2.zip "$url"
curl --proto '=https' --proto-redir '=https' --fail --show-error --location \
  --connect-timeout 10 --max-time 60 --output awscliv2.sig "$url.sig"
gpg --no-options --batch --no-auto-key-retrieve --status-fd=1 \
  --verify awscliv2.sig awscliv2.zip > verification.status
awk -v fp="$fingerprint" '
  $2 == "VALIDSIG" {count++; if ($3 != fp && $NF != fp) bad=1}
  $2 ~ /^(BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|KEYEXPIRED|SIGEXPIRED|KEYREVOKED|NO_PUBKEY|FAILURE)$/ {bad=1}
  END {exit (count != 1 || bad)}' verification.status
nice -n 10 unzip -q awscliv2.zip
sudo nice -n 10 ./aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
version=$(/usr/local/bin/aws --version)
printf '%s\n' "$version"
if [[ "$version" != 'aws-cli/2.40.3 '* ]]; then
  printf 'Installed version mismatch; stop for review\n' >&2
  exit 1
fi
printf 'AWS CLI 2.40.3 installed; no configuration or uploads performed.\n'
