#!/usr/bin/env bash
# Shared helpers for the app-db scripts. Sourced, not executed.

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql}"
DEFAULT_ENV_FILE="$INFRA_ROOT/.env"

# Identifiers can't be bound as parameters in DDL, so they are interpolated
# into SQL directly. This whitelist is what makes that safe.
NAME_PATTERN='^[a-z][a-z0-9_]*$'
MAX_DB_NAME_LEN=64
MAX_USER_NAME_LEN=32

die() {
  echo "error: $*" >&2
  exit 1
}

validate_identifier() {
  local kind="$1" value="$2" max_len="$3"
  if ! [[ "$value" =~ $NAME_PATTERN ]]; then
    die "$kind '$value' is invalid: use lowercase letters, digits and underscores, starting with a letter"
  fi
  if [ "${#value}" -gt "$max_len" ]; then
    die "$kind '$value' is ${#value} characters, max is $max_len"
  fi
}

require_container_running() {
  if ! docker inspect -f '{{.State.Running}}' "$MYSQL_CONTAINER" 2>/dev/null | grep -q true; then
    die "container '$MYSQL_CONTAINER' is not running"
  fi
}

# Runs SQL from stdin as root. The root password is read from the container's
# own environment, so it never appears in host process args or shell history.
run_sql() {
  docker exec -i "$MYSQL_CONTAINER" \
    sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --batch --skip-column-names'
}

database_exists() {
  local result
  result="$(echo "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$1';" | run_sql)"
  [ "$result" != "0" ]
}

user_exists() {
  local result
  result="$(echo "SELECT COUNT(*) FROM mysql.user WHERE User = '$1';" | run_sql)"
  [ "$result" != "0" ]
}

generate_password() {
  # Alphanumeric only, so it never needs quoting or URL-encoding
  local raw
  raw="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')"
  [ "${#raw}" -ge 32 ] || die "password generation failed"
  echo "${raw:0:32}"
}

env_prefix() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Each app's credentials live between marker lines so they can be replaced
# or removed later without touching anything else in the file.
remove_env_block() {
  local env_file="$1" app="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v start="# >>> app-db: $app" -v end="# <<< app-db: $app" '
    $0 == start { skipping = 1; next }
    $0 == end   { skipping = 0; next }
    !skipping
  ' "$env_file" > "$tmp"
  # cat (not mv) keeps the original file's owner and permissions
  cat "$tmp" > "$env_file"
  rm -f "$tmp"
}

write_env_block() {
  local env_file="$1" app="$2" db="$3" user="$4" password="$5"
  local prefix
  prefix="$(env_prefix "$app")"
  remove_env_block "$env_file" "$app"
  {
    echo "# >>> app-db: $app"
    echo "${prefix}_DB_NAME=$db"
    echo "${prefix}_DB_USER=$user"
    echo "${prefix}_DB_PASSWORD=$password"
    echo "# <<< app-db: $app"
  } >> "$env_file"
}

print_credentials() {
  local db="$1" user="$2" password="$3"
  cat <<EOF

  Database : $db
  User     : $user
  Password : $password

  From containers on the 'database' network:
    jdbc:mysql://mysql:3306/$db
  From the VPS host:
    jdbc:mysql://127.0.0.1:3306/$db

EOF
}
