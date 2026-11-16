# Reviewed AWS CLI installer

This folder contains one action: install **AWS CLI 2.40.3 on Linux x86_64**.
It does not configure credentials, upload data, install packages, enable schedules,
change services or reboot. No Git is needed on the target machine.

## Publish only these files

Create a **separate, clean public repository**, with only `01-install-aws-cli.sh`,
`SHA256SUMS` and this `README.md` at its root. Copy these three files only.
Do not publish the source repository, its history, other documentation, tests,
configuration, logs or machine-specific information. Review the public files
before publishing. Record the full reviewed commit ID and share the installer's
expected SHA-256 over an independently trusted channel.

`SHA256SUMS` covers the installer. A manifest fetched from the same URL is a
convenience check, **not independent authentication**. Use both the full reviewed
commit URL and the trusted expected hash. Never use a moving branch URL or
`curl | bash`.

## Before running

Confirm the authorized machine and installation scope. Check its clock, current
load, memory, staging and `/usr/local` free space; allow for the archive, extracted
tree and installed copy while preserving the agreed disk reserve. Review AWS's
Linux compatibility requirements (`glibc`, `groff`, `less`) in the
[official guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
Run read-only `dpkg --audit` on Debian/Ubuntu; pending configuration or errors
mean stop, not package repair. Observe application health during installation.

Requires Bash, curl, unzip, gpg, python3, sudo and standard Linux utilities
(including `nice` and `sha256sum`). Missing tools are a stop condition; this
installer does not install prerequisites. It stops if either AWS command or any
fixed installation destination already exists, including dangling symlinks.
There is no update/overwrite mode.

## Download, verify, run as a normal user

Replace `OWNER`, `REPO`, `FULL_COMMIT` and `TRUSTED_SHA256` below with the reviewed
public location and independently supplied hash. The repository URL is not yet
known; these placeholders are not runnable release instructions.

Run this block in Bash. It uses a subshell so failures do not exit the interactive
SSH shell. Download staging is private; the retained log is mode 0600 under
`/tmp`, outside Git. Do not run the whole block with sudo.

```bash
(
set -euo pipefail
umask 077
download=$(mktemp -d /tmp/client-tools.XXXXXXXX)
cd "$download"
curl --proto '=https' --proto-redir '=https' --fail --show-error --location \
  --connect-timeout 10 --max-time 60 --output 01-install-aws-cli.sh \
  'https://raw.githubusercontent.com/OWNER/REPO/FULL_COMMIT/01-install-aws-cli.sh'
printf '%s  01-install-aws-cli.sh\n' 'TRUSTED_SHA256' | sha256sum --check --strict -
bash 01-install-aws-cli.sh --help
log=$(mktemp /tmp/aws-cli-install.XXXXXXXX.log)
printf 'Download retained: %s\nPrivate log retained: %s\n' "$download" "$log"
if bash 01-install-aws-cli.sh > "$log" 2>&1; then
  printf 'Installer exited successfully; review the private log.\n'
else
  status=$?
  printf 'Installer stopped (exit %s); review the private log before retrying.\n' "$status" >&2
  exit "$status"
fi
)
```

Sudo is used only inside the installer, after signature verification. It fetches
one public key from the bounded official HTTPS guide, checks the pinned full
fingerprint `FB5DB77FD5C118B80511ADA8A6310ACC4672475C` in an isolated keyring,
rejects expired/revoked keys and invalid/other signatures, then extracts and
installs with niceness 10. Writes are limited to private staging plus
`/usr/local/aws-cli`, `/usr/local/bin/aws` and `/usr/local/bin/aws_completer`.
It verifies the installed version; this is not a no-impact guarantee.

A changed/unparseable key page, fingerprint/expiry/signature failure or network
error stops installation: never bypass verification. Private installer staging
(mode 0700), including verification evidence, is retained on success or failure;
its path is in the log. An installer failure may leave a partial installation;
stop for review rather than retrying or deleting it automatically. No existing
keyring is modified. Cleanup is a separate deliberate action; `/tmp` retention
is subject to the machine's cleanup policy.

Review logs locally and redact before sending output back through an approved
private channel. **Never upload logs or machine output to the public repository.**
Publishing and mocked tests do not establish a live installation result.
