# Reviewed client setup tools

Three separate, deliberate actions are provided:

- `01-install-aws-cli.sh`: install **AWS CLI 2.40.3 on Linux x86_64** only.
- `02-configure-backup.sh`: **setup only**, write private configuration and install
  the reviewed local runtime and systemd service, then `daemon-reload` only.
- `03-check-garage-access.sh`: **HeadBucket only**, check exported S3
  credentials/basic bucket access without saving credentials or reading `02` config.

None of these helpers starts/enables a backup, installs a timer, runs preflight, dumps,
archives or uploads application data, reboots or restarts services. No Git is
needed on the target machine. Publishing/downloading these files does nothing
until an operator deliberately executes a helper.

## Publish only this public working tree

Publish the **whole reviewed working tree of this folder, excluding `.git`**, to
its separate clean public repository. Its exact file list is:

```text
01-install-aws-cli.sh
02-configure-backup.sh
03-check-garage-access.sh
README.md
SHA256SUMS
lib/bookstack-dr-backup
lib/bookstack-dr-backup.service
lib/bookstack-dr-backup.timer
```

Do not publish the private parent project, its history, documentation, tests,
configuration, identities, logs or machine-specific information. Keep all private
values on the client VM or in approved private handoff records, never in this
public tree. Review every public file before publication. Record the **full
reviewed public commit ID** and share each helper's expected SHA-256 over an
independently trusted channel.

`SHA256SUMS` covers the helpers, README and payloads. A manifest fetched from the
same URL is a convenience check, **not independent authentication**. Establish
initial trust in `02` with its independently supplied hash and full reviewed
commit; it embeds hashes of both local payloads and checks the exact snapshots it
will install. There are no remote payload downloads or fallback paths. Never
use a moving branch URL or `curl | bash`.

## 01 — Before running (dependency installation only)

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

## 01 — Download, verify, run as a normal user

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

## 02 — Download the complete reviewed release, verify, run as root

Do not rerun `01` if the dependency is already installed and accepted. Missing
prerequisites for `02` are a stop condition, not permission to install packages.

Download/extract the **whole snapshot at the full reviewed public commit** into
a new local directory (for example, download the archive from
`https://github.com/OWNER/REPO/archive/FULL_COMMIT.zip`). Preserve `lib/` alongside
`02-configure-backup.sh`; a lone script download is insufficient. Alternatively,
an existing checkout of the separate public repository can be updated locally by
the operator, reviewed and checked out at that exact full commit. The helper
never fetches, pulls, updates itself or downloads missing assets. Do not use the
private parent project's checkout as the client distribution.

After checking the independently supplied full commit and `TRUSTED_02_SHA256`,
run these commands in the extracted public folder. Replace the hash placeholder
with the independently trusted value; never take it only from the same download.

```bash
printf '%s  02-configure-backup.sh\n' 'TRUSTED_02_SHA256' | sha256sum --check --strict -
sha256sum --check --strict SHA256SUMS
bash ./02-configure-backup.sh --help
set +x
source "$HOME/.config/bookstack-dr-backup/session.env.sh"
sudo --preserve-env=AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY bash 02-configure-backup.sh
```

Unlike `01`, **only `02` is run as authorized root via sudo**. Use an interactive
TTY. Source only a trusted, private file outside the public clone, containing the
exported `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`; both must be nonempty.
Keep that file mode 0600 and its parent directory private (0700). Never source an
untrusted script. Disable shell tracing before sourcing; never type credentials
inline in commands/history. Environment credentials remain visible to root and
potentially same-UID processes; this is not zero exposure. Changing this environment
does **not** rotate an already configured root credential file: `02` still refuses
existing targets; updating persisted credentials needs a separate approved change.
Do not pipe inputs, pass credentials as arguments, redirect the input session to a
log, share terminal recordings, or screenshot private keys. Xtrace is disabled.
Typed settings are visible, but the helper never prints S3 credentials.
Validation errors name the failing field without printing its value.
Never enter an age private identity, BookStack `APP_KEY` or database
password. The application `.env` is neither read nor changed during setup.

Prepare these reviewed values through the approved private handoff; none has a
blind default. Credentials come only from the exported pair, not prompts.
Prompts appear in this exact order:

1. `Source APP_URL (reviewed HTTPS URL)`
2. `S3 endpoint (reviewed HTTPS URL)`
3. `S3 bucket (reviewed exact name)`
4. `S3 region (reviewed exact value)`
5. `S3 prefix (reviewed lifecycle-matching value, no leading/trailing slash)`
6. `age PUBLIC recipient (age1...)`
7. `Type INSTALL SETUP ONLY to authorize these writes`

Use HTTPS URLs without embedded authentication, query, fragment, escapes or
control characters. Bucket names must be lowercase DNS-style, regions use
letters/digits/underscore/hyphen, and prefixes use nonempty slash-separated
letters/digits/underscore/hyphen segments. Only native `age1` public recipients
are accepted and checked locally by encrypting **empty input** to `/dev/null`;
this does not prove identity custody or decryptability. S3 keys must be single-line
letters/digits or `/+=._-`; unsupported formats are a stop for private review,
not a reason to bypass validation. No endpoint, credential, database, application
or lifecycle availability check runs in this helper.

Before confirmation, local assets, field formats and destination safety are
checked. Existing destinations, symlinks, unsafe parents, and already installed
units/overrides are refused; no overwrite/update/force option exists. After exact
confirmation it creates only these fixed root-owned targets:

```text
/etc/bookstack-dr-backup/                          0700
    config, aws-config, aws-credentials,
    age-recipient.txt                             0600
/var/lib/bookstack-dr-backup/                      0700
/var/lib/bookstack-dr-backup/staging/              0700
/run/bookstack-dr-backup/                          0700
/usr/local/sbin/bookstack-dr-backup                0755
/etc/systemd/system/bookstack-dr-backup.service    0644
```

Parent directories must already exist, be root-owned and not group/other
writable. Nothing unrelated is overwritten or chmodded. The AWS profile is
`bookstack-backup`, with path-style SigV4, two concurrent requests and 1 MB/s
transfer limit. Runtime defaults retain `/var/www/bookstack`, database `bookstack`,
local root MySQL socket authentication (no DB password), 512 MiB staging budget,
2 GiB reserve and the existing conservative service limits. Review those paths
and limits before setup; they are not discovered from the application's `.env`.
The runtime and service are installed byte-for-byte as reviewed. The helper does
not execute the installed runtime. Only `systemctl daemon-reload` changes manager
state; the unit is not started or enabled and no timer is installed.

**Stop on setup failure.** Failure retains any partial root state/evidence for private
review; do not retry blindly or delete it automatically. Success is not readiness
for backup. Before a separately approved service run, confirm a dummy
decrypt with the **vault-retrieved private identity off production**, scoped S3
credential readiness, exact prefix coverage by the reviewed five-day lifecycle
(do not assume it is applied), permissions/capacity and application/service
health. No real backup, restore, timer, monitoring or availability result is
established by setup or by local mocked tests. Logs/output belong only in approved
private channels, never the public repository.

## 03 — After successful setup and verified artifacts

From the complete reviewed release, verify `03` with its independently supplied
SHA-256 (and the release manifest) before executing it. Run as a **normal user**,
not sudo. Requires Bash, AWS CLI and `timeout`; missing tools mean stop, not
installation. Supply exactly three nonsecret arguments: **ENDPOINT REGION BUCKET**,
using reviewed private handoff values. Only arity and the `https://` scheme are
checked locally; AWS CLI handles syntax validation.

There are no credential prompts: both exported `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` must be nonempty, sourced from the trusted private file
as above. Never supply credentials as arguments, record the session, or enter a
private identity, `APP_KEY` or database password. Credentials stay in
the subprocess; session tokens/profiles are unset and AWS config/credentials
paths are `/dev/null`. Nothing is saved. Only `s3api head-bucket` runs, with
5-second connect/10-second read timeouts, one attempt, metadata disabled and a
30-second timeout plus 5-second kill grace. Normal SDK errors remain visible
(no debug); keep output private. Any failure returns nonzero: stop for review.

After `02` succeeds and artifacts are verified, run in this order, **stopping if
either command fails** (do not paste/run subsequent steps after failure):

```bash
bash 03-check-garage-access.sh https://storage.example.invalid test-region example-backup-bucket
```

Only after `03` succeeds:

```bash
sudo /usr/local/sbin/bookstack-dr-backup --preflight
```

`03` checks the **exported credentials/basic bucket access only**. It does not
prove PUT permission or validate the configuration saved by `02`. Preflight
checks the **actual saved configuration**, including bucket access, local
permissions/capacity, bounded DB/source metadata and empty-input encryption;
it does not upload or prove PUT permission either. Neither establishes backup
readiness alone. Stop for private review on any failure; never bypass checks.

Only after both succeed **and** vault-retrieved dummy decryption off production,
current application/service health and all credential/lifecycle/readiness gates
are confirmed, obtain **explicit pilot approval** for ONE supervised invocation:

```bash
sudo systemctl start --no-block bookstack-dr-backup.service
sudo journalctl -u bookstack-dr-backup.service -n 80 --no-pager
systemctl show bookstack-dr-backup.service -p ActiveState -p SubState -p Result -p ExecMainStatus
```

The start returns before the oneshot finishes. Check logs/state again after it
finishes: expect `ActiveState=inactive`, `SubState=dead`, `Result=success` and
`ExecMainStatus=0`. Success/0 before completion is not a completed backup result.
During the pilot, keep the timer **uninstalled/disabled**. Observe BookStack responsiveness and
resources throughout; only if degradation occurs under the approved pilot stop
scope, manually stop **only the backup service** with
`sudo systemctl stop bookstack-dr-backup.service`. Do not stop/restart application,
database or security services, retry automatically or delete failed evidence.

## Optional daily timer — after a successful pilot

The timer runs the existing service daily at **03:00 in the VM’s local time**.
Missed runs are not caught up at startup. An upload is not proof of recovery;
complete the off-production restore test as soon as possible if it is deferred.

On the client VM, from the updated, verified release directory, install and
start the timer (not the backup service):

```bash
sudo install -o root -g root -m 0644 lib/bookstack-dr-backup.timer /etc/systemd/system/bookstack-dr-backup.timer &&
  sudo systemctl daemon-reload &&
  sudo systemctl enable --now bookstack-dr-backup.timer &&
  systemctl list-timers --all bookstack-dr-backup.timer
```

To pause future runs: `sudo systemctl disable --now bookstack-dr-backup.timer`.
This does not stop a backup that is already running.
