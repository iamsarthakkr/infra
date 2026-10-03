#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <app_name> [--user NAME] [--env-file PATH | --no-env-file]

Creates database <app_name> and a user with privileges on that database only.
The generated password is printed once and appended to the env file.

Options:
  --user NAME       Username (default: <app_name>_user)
  --env-file PATH   Env file to write credentials to (default: $DEFAULT_ENV_FILE, if it exists)
  --no-env-file     Only print the credentials
EOF
}

app=""
user=""
env_file=""
env_file_explicit=false
write_env=true

while [ $# -gt 0 ]; do
  case "$1" in
    --user)        user="${2:?--user needs a value}"; shift 2 ;;
    --env-file)    env_file="${2:?--env-file needs a value}"; env_file_explicit=true; shift 2 ;;
    --no-env-file) write_env=false; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            usage >&2; die "unknown option $1" ;;
    *)
      [ -z "$app" ] || die "unexpected argument $1"
      app="$1"; shift ;;
  esac
done

[ -n "$app" ] || { usage >&2; exit 1; }
user="${user:-${app}_user}"
env_file="${env_file:-$DEFAULT_ENV_FILE}"

validate_identifier "database name" "$app" "$MAX_DB_NAME_LEN"
validate_identifier "username" "$user" "$MAX_USER_NAME_LEN"

if [ "$write_env" = true ] && [ ! -f "$env_file" ]; then
  if [ "$env_file_explicit" = true ]; then
    die "env file $env_file does not exist"
  fi
  echo "note: no env file at $env_file, credentials will only be printed"
  write_env=false
fi

require_container_running

# Refuse rather than overwrite: silently resetting a live app's password
# would break it. Use rotate-password.sh for that.
database_exists "$app" && die "database '$app' already exists"
user_exists "$user" && die "user '$user' already exists"

password="$(generate_password)"

# The mysql client stops at the first failing statement.
run_sql <<SQL
CREATE DATABASE \`$app\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER '$user'@'%' IDENTIFIED BY '$password';
GRANT ALL PRIVILEGES ON \`$app\`.* TO '$user'@'%';
SQL

echo "Created database '$app' and user '$user'."
# Printed before writing the env file, so the password is never lost if that write fails
print_credentials "$app" "$user" "$password"

if [ "$write_env" = true ]; then
  write_env_block "$env_file" "$app" "$app" "$user" "$password"
  echo "Saved to $env_file as $(env_prefix "$app")_DB_*"
fi
