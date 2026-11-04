#!/usr/bin/env bash
# Runs the deploy blocks extracted from deploy-render.yml against the fake server,
# in workflow order and stopping at the first failure, as the job would.
# Usage from the repo root: bash fixtures/fake-render/cases.sh
set -euo pipefail

wf=.github/workflows/deploy-render.yml
tmp=$(mktemp -d)
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

for block in check-secret validate trigger poll; do
  sed -n "/# >>> $block\$/,/# <<< $block\$/p" "$wf" | sed '1d;$d' > "$tmp/$block.sh"
  [ -s "$tmp/$block.sh" ] || { echo "::error::$block block not found"; exit 1; }
done

# The tested blocks must be what the workflow runs, in the order tested here.
structure_fail() { echo "::error::$1"; exit 1; }
order=$(sed -nE 's/^ *# >>> ([a-z-]+)$/\1/p' "$wf" | paste -sd ' ' -)
[ "$order" = "check-secret validate trigger poll" ] || structure_fail "blocks are out of order: $order"
grep -qF "environment: \${{ inputs.environment }}" "$wf" || structure_fail "job has no environment"
grep -qF "attempts=\${POLL_ATTEMPTS:-30}" "$wf" || structure_fail "default attempts changed"
grep -qF "delay=\${POLL_DELAY:-10}" "$wf" || structure_fail "default delay changed"
# The poll settings stay internal: nothing in the workflow may set them.
if grep -Eq '^ *POLL_(ATTEMPTS|DELAY):' "$wf"; then structure_fail "workflow sets a poll override"; fi
if grep -Eq '^ *set -[a-z]*x' "$wf"; then structure_fail "set -x would print the hook URL"; fi
echo "ok   workflow structure"

# A fake key, used to prove that no block prints the hook URL.
key=fakekey-do-not-print
old=1111111111111111111111111111111111111111
new=2222222222222222222222222222222222222222
digest_hex=$(printf 'ab%.0s' $(seq 1 32))
image="ghcr.io/abhiman-erla/helios-backend@sha256:$digest_hex"
fails=0
log="$tmp/requests.log"
port=""

start_server() { # KEY=value ... for the server
  : > "$log"
  rm -f "$tmp/port"
  env LOG_FILE="$log" PORT_FILE="$tmp/port" OLD_VERSION="$old" NEW_VERSION="$new" "$@" node fixtures/fake-render/server.js &
  server_pid=$!
  for _ in $(seq 1 50); do
    [ -s "$tmp/port" ] && break
    sleep 0.1
  done
  [ -s "$tmp/port" ] || { echo "::error::fake server did not start"; exit 1; }
  port=$(cat "$tmp/port")
}

stop_server() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  server_pid=""
}

deploy() { # runs the blocks; takes its values from the caller's variables
  (
    export RENDER_DEPLOY_HOOK="$hook" IN_ENVIRONMENT="$environment" IMAGE_DIGEST="$digest"
    export HEALTH_URL="$health" EXPECTED_VERSION="$version"
    for block in check-secret validate trigger poll; do
      bash "$tmp/$block.sh" || exit $?
    done
  )
}

reset_values() {
  hook="http://127.0.0.1:$port/deploy/srv-fake?key=$key"
  environment=production
  digest=$image
  health="http://127.0.0.1:$port/health"
  version=$new
}

# label ok|bad expected-output-regex
check() {
  local label=$1 want=$2 re=$3 rc=0 out
  out=$(deploy 2>&1) || rc=$?
  if { [ "$want" = ok ] && [ "$rc" -ne 0 ]; } || { [ "$want" = bad ] && [ "$rc" -eq 0 ]; }; then
    echo "::error::$label: expected $want, rc=$rc"
    fails=1
  elif ! grep -Eq -- "$re" <<<"$out"; then
    echo "::error::$label: output does not match '$re'"
    fails=1
  elif grep -v '^::add-mask::' <<<"$out" | grep -q "$key"; then
    # add-mask lines are consumed by the runner and never shown.
    echo "::error::$label: the hook key was printed"
    fails=1
  else
    echo "ok   $label (rc=$rc)"
  fi
}

requests() { # number of requests the fake server has seen
  wc -l < "$log" | tr -d ' '
}

no_network() { # label
  if [ "$(requests)" -ne 0 ]; then
    echo "::error::$1: made a network call"
    fails=1
  fi
}

# --- Masking ---
start_server REPORT_AFTER=0
reset_values
masks=$(RENDER_DEPLOY_HOOK=$hook bash "$tmp/check-secret.sh")
if grep -qxF "::add-mask::$hook" <<<"$masks" && grep -qxF "::add-mask::$key" <<<"$masks"; then
  echo "ok   the hook URL and its key are masked"
else
  echo "::error::the hook URL or its key is not masked"
  fails=1
fi

# --- Rejected before any network call ---
hook=""
check "empty secret" bad 'RENDER_DEPLOY_HOOK is empty'
no_network "empty secret"

bad_input() { # label variable value expected-regex
  reset_values
  printf -v "$2" '%s' "$3"
  check "$1" bad "$4"
  no_network "$1"
}

bad_input "hook is not a URL" hook "not-a-url" 'not a valid https URL'
bad_input "hook is plain http" hook "http://api.render.com/deploy/x?key=$key" 'not a valid https URL'
bad_input "hook has a line break" hook "https://api.render.com/deploy/x?key=$key"$'\n' 'not a valid https URL'
bad_input "hook has a quote" hook "https://api.render.com/deploy/x?key=$key\"" 'not a valid https URL'
bad_input "hook already sets imgURL" hook "http://127.0.0.1:$port/deploy/x?key=$key&imgURL=a" 'already sets imgURL'
bad_input "empty environment" environment "" 'environment must name'
bad_input "image with a tag" digest "ghcr.io/o/n:latest" 'image-digest must be'
bad_input "image with no registry" digest "alpine@sha256:$digest_hex" 'image-digest must be'
bad_input "bare digest" digest "sha256:$digest_hex" 'image-digest must be'
bad_input "short digest" digest "ghcr.io/o/n@sha256:abc" 'image-digest must be'
bad_input "upper-case digest" digest "ghcr.io/o/n@sha256:${digest_hex^^}" 'image-digest must be'
bad_input "digest with a trailing line" digest "$image"$'\nx' 'image-digest must be'
bad_input "image with a query" digest "ghcr.io/o/n@sha256:$digest_hex&x=1" 'image-digest must be'
bad_input "empty digest" digest "" 'image-digest must be'
bad_input "empty expected-version" version "" 'expected-version must be'
bad_input "short expected-version" version "abc123" 'expected-version must be'
bad_input "39-character expected-version" version "${new:0:39}" 'expected-version must be'
bad_input "upper-case expected-version" version "ABCDEF${new:6}" 'expected-version must be'
bad_input "health-url is plain http" health "http://example.com/health" 'health-url must be'
bad_input "health-url with credentials" health "https://u:p@example.com/health" 'health-url must be'
stop_server

# --- The hook's answer ---
export POLL_ATTEMPTS=5 POLL_DELAY=1
hook_status() { # status expected-regex
  start_server HOOK_STATUS="$1" REPORT_AFTER=0
  reset_values
  check "hook returns $1" bad "$2"
  if grep -q health "$log"; then
    echo "::error::hook returns $1: polled after a failed hook"
    fails=1
  fi
  stop_server
}
hook_status 202 'returned 202: another deploy of this service is in progress'
hook_status 400 'returned HTTP 400'
hook_status 401 'returned HTTP 401'
hook_status 404 'returned HTTP 404'
hook_status 409 'returned HTTP 409'
hook_status 500 'returned HTTP 500'
hook_status 204 'returned HTTP 204' # Render documents only 200 and 202 as success
hook_status 302 'returned HTTP 302'

# Nothing is listening: curl fails, and its error must not carry the URL.
start_server
reset_values
stop_server
check "hook unreachable" bad 'curl exit code'

# --- Polling ---
export POLL_ATTEMPTS=3 POLL_DELAY=0
start_server
reset_values
check "server never reports the version" bad "did not report $new after 3 attempts"
if [ "$(grep -c '^GET /health' "$log")" -ne 3 ]; then
  echo "::error::expected exactly 3 polls"
  fails=1
fi
stop_server

start_server REPORT_AFTER=0 HEALTH_STATUS=500
reset_values
check "version only in a 500 answer" bad "did not report $new"
stop_server

export POLL_ATTEMPTS=5 POLL_DELAY=1
start_server REPORT_AFTER=2
reset_values
check "server reports the version after a delay" ok "reports $new \(attempt 3,"

# The hook received the image, URL-encoded, once, by POST and before any poll.
want_query="key=$key&imgURL=ghcr.io%2Fabhiman-erla%2Fhelios-backend%40sha256%3A$digest_hex"
first=$(head -n 1 "$log")
if [ "$first" != "POST /deploy/srv-fake?$want_query" ]; then
  echo "::error::hook request was not as expected"
  fails=1
else
  echo "ok   hook request is POST with the URL-encoded image, before any poll"
fi
if [ "$(grep -c '^POST' "$log")" -ne 1 ]; then
  echo "::error::expected exactly one hook call"
  fails=1
fi
stop_server

# A hook URL with no query string gets ? rather than &.
start_server REPORT_AFTER=0
reset_values
hook="http://127.0.0.1:$port/deploy/srv-fake"
check "hook with no query string" ok "reports $new"
if ! grep -q "^POST /deploy/srv-fake?imgURL=ghcr.io%2F" "$log"; then
  echo "::error::hook with no query string got a malformed URL"
  fails=1
fi
stop_server

# --- Defaults: no override means 30 attempts, 10 seconds apart ---
unset POLL_ATTEMPTS POLL_DELAY
start_server REPORT_AFTER=0
reset_values
check "default poll settings" ok "up to 30 attempts, 10 seconds apart"
stop_server

# A bad override is refused rather than treated as no polling.
start_server REPORT_AFTER=0
reset_values
POLL_ATTEMPTS=0 check "POLL_ATTEMPTS of 0" bad 'POLL_ATTEMPTS must be'
stop_server

if [ "$fails" -ne 0 ]; then
  echo "::error::deploy-render cases failed"
  exit 1
fi
echo "all deploy-render cases passed"
