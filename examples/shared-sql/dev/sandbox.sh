#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_SQL_GROUP=example-project-test-sql
export TEST_SQL_STATE_DIR="$HOME/.ai-sandbox/services/$TEST_SQL_GROUP"
umask 077
mkdir -p "$TEST_SQL_STATE_DIR/client"
exec 9>"$TEST_SQL_STATE_DIR/bootstrap.lock"
flock -w 600 9 || { echo 'Timed out waiting for SQL bootstrap.' >&2; exit 1; }

if [[ ! -f "$TEST_SQL_STATE_DIR/server.env" ]]; then
  sa_password="Aa1!$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  test_password="Aa1!$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'MSSQL_SA_PASSWORD=%s\nTEST_SQL_PASSWORD=%s\n' "$sa_password" "$test_password" > "$TEST_SQL_STATE_DIR/server.env.tmp"
  mv "$TEST_SQL_STATE_DIR/server.env.tmp" "$TEST_SQL_STATE_DIR/server.env"
fi
test_password="$(sed -n 's/^TEST_SQL_PASSWORD=//p' "$TEST_SQL_STATE_DIR/server.env")"
[[ "$test_password" =~ ^Aa1![a-f0-9]{48}$ ]] || { echo 'Invalid local test SQL password file.' >&2; exit 1; }
if [[ ! -f "$TEST_SQL_STATE_DIR/client/connection.json" ]]; then
  printf '{"server":"test-sql,1433","user":"sandbox_test","password":"%s"}\n' "$test_password" > "$TEST_SQL_STATE_DIR/client/connection.json.tmp"
  mv "$TEST_SQL_STATE_DIR/client/connection.json.tmp" "$TEST_SQL_STATE_DIR/client/connection.json"
fi

if ! docker network inspect "$TEST_SQL_GROUP" >/dev/null 2>&1; then
  docker network create "$TEST_SQL_GROUP" >/dev/null
fi
compose=(docker compose --project-name "$TEST_SQL_GROUP" --file "$project_root/dev/compose.yaml")
"${compose[@]}" up -d --wait --wait-timeout 150 --no-recreate sql
"${compose[@]}" run --rm -T init

mapping="$project_root/.ai-sandbox/supplemental-folders.config"
temporary="$(mktemp "$mapping.XXXXXX")"
if [[ -f "$mapping" ]]; then
  awk '$0 !~ /\|test-sql(\|(ro|rw))?\r?$/' "$mapping" > "$temporary"
fi
printf '%s|test-sql|ro\n' "$TEST_SQL_STATE_DIR/client" >> "$temporary"
mv "$temporary" "$mapping"
flock -u 9
exec 9>&-
cd "$project_root"
ai-sandbox "$@"
