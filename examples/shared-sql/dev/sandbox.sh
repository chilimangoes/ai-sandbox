#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_SQL_GROUP=example-project-test-sql
export TEST_SQL_STATE_DIR="$project_root/.local/test-sql"
image=mcr.microsoft.com/mssql/server:2022-CU22-GDR1-ubuntu-22.04

docker_checked() {
  local output
  if ! output="$(docker "$@" 2>&1)"; then
    echo "Docker $1 failed. Check Docker Engine and the test service status." >&2
    return 1
  fi
  printf '%s' "$output"
}

sql_container() {
  local id
  id="$(docker_checked container ls -aq --filter "label=com.docker.compose.project=$TEST_SQL_GROUP" --filter label=com.docker.compose.service=sql)" || return
  [[ "$id" != *$'\n'* ]] || { echo 'Multiple SQL containers found for the service group.' >&2; return 1; }
  printf '%s' "$id"
}

container="$(sql_container)"
if [[ -n "$container" ]]; then
  lock_image="$(docker_checked container inspect --format '{{.Image}}' "$container")"
else
  if [[ -z "$(docker_checked image ls -q "$image")" ]]; then docker_checked pull "$image" >/dev/null; fi
  lock_image="$image"
fi

# A daemon-wide helper coordinates every checkout and expires after ten minutes.
lock_id=''
cleanup() { if [[ -n "$lock_id" ]]; then docker rm -f "$lock_id" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
deadline=$((SECONDS + 660))
missing_holder_failures=0
until lock_id="$(docker run -d --rm --name "$TEST_SQL_GROUP-bootstrap-lock" --label "ai-sandbox.shared-sql=$TEST_SQL_GROUP" --entrypoint /bin/sleep "$lock_image" 600 2>/dev/null)"; do
  lock_id=''
  holder="$(docker_checked container ls -aq --filter "name=^/$TEST_SQL_GROUP-bootstrap-lock$")"
  if [[ -n "$holder" ]]; then
    # The holder can finish between listing and inspecting its helper.
    if owner="$(docker container inspect --format '{{index .Config.Labels "ai-sandbox.shared-sql"}}' "$holder" 2>/dev/null)"; then
      [[ "$owner" == "$TEST_SQL_GROUP" ]] || { echo 'Bootstrap lock name belongs to another service.' >&2; exit 1; }
    else
      remaining="$(docker_checked container ls -aq --filter "name=^/$TEST_SQL_GROUP-bootstrap-lock$")"
      [[ "$remaining" != "$holder" ]] || { echo 'Could not inspect the SQL bootstrap lock.' >&2; exit 1; }
    fi
    missing_holder_failures=0
  else
    missing_holder_failures=$((missing_holder_failures + 1))
    ((missing_holder_failures < 2)) || { echo 'Could not acquire the SQL bootstrap lock.' >&2; exit 1; }
  fi
  ((SECONDS < deadline)) || { echo 'Timed out waiting for SQL bootstrap.' >&2; exit 1; }
  sleep 1
done

container="$(sql_container)"
umask 077
if [[ -n "$container" ]]; then
  credentials="$(docker_checked container inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container")"
elif [[ -f "$TEST_SQL_STATE_DIR/server.env" ]]; then
  credentials="$(cat "$TEST_SQL_STATE_DIR/server.env")"
else
  sa_password="Aa1!$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  test_password="Aa1!$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  credentials="$(printf 'MSSQL_SA_PASSWORD=%s\nTEST_SQL_PASSWORD=%s\n' "$sa_password" "$test_password")"
fi
# Read credentials as data; never execute an environment file or Docker output.
sa_password='' test_password=''
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "$line" in
    MSSQL_SA_PASSWORD=*) [[ -z "$sa_password" ]] || exit 1; sa_password="${line#*=}" ;;
    TEST_SQL_PASSWORD=*) [[ -z "$test_password" ]] || exit 1; test_password="${line#*=}" ;;
  esac
done <<< "$credentials"
[[ "$sa_password" =~ ^Aa1![a-f0-9]{48}$ && "$test_password" =~ ^Aa1![a-f0-9]{48}$ ]] || {
  echo 'Invalid generated test SQL credentials. Local state was not updated.' >&2; exit 1;
}
mkdir -p "$TEST_SQL_STATE_DIR/client"
printf 'MSSQL_SA_PASSWORD=%s\nTEST_SQL_PASSWORD=%s\n' "$sa_password" "$test_password" > "$TEST_SQL_STATE_DIR/server.env.tmp"
mv -f "$TEST_SQL_STATE_DIR/server.env.tmp" "$TEST_SQL_STATE_DIR/server.env"
printf '{"server":"test-sql,1433","user":"sandbox_test","password":"%s"}\n' "$test_password" > "$TEST_SQL_STATE_DIR/client/connection.json.tmp"
mv -f "$TEST_SQL_STATE_DIR/client/connection.json.tmp" "$TEST_SQL_STATE_DIR/client/connection.json"

if [[ -z "$(docker_checked network ls -q --filter "name=^$TEST_SQL_GROUP$")" ]]; then
  docker_checked network create "$TEST_SQL_GROUP" >/dev/null
fi
compose=(compose --project-name "$TEST_SQL_GROUP" --file "$project_root/dev/compose.yaml")
echo "Waiting for $TEST_SQL_GROUP and verifying the test login..."
docker_checked "${compose[@]}" up -d --wait --wait-timeout 150 --no-recreate sql >/dev/null
docker_checked "${compose[@]}" run --rm -T init >/dev/null
docker_checked rm -f "$lock_id" >/dev/null
lock_id=''
cd "$project_root"
ai-sandbox "$@"
