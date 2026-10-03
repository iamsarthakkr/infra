#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <app_name> [--user NAME] [--env-file PATH | --no-env-file]

Generates a new password for an app's database user. The app keeps working
on open connections but needs the new password for new connections.

Options:
  --user NAME       Username (default: <app_name>_user)
  --env-file PATH   Env file to update (default: $DEFAULT_ENV_FILE, if it exists)
  --no-env-file     Only print the new credentials
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
user_exists "$user" || die "user '$user' does not exist"

password="$(generate_password)"

echo "ALTER USER '$user'@'%' IDENTIFIED BY '$password';" | run_sql

echo "Rotated password for '$user'."
print_credentials "$app" "$user" "$password"

if [ "$write_env" = true ]; then
  write_env_block "$env_file" "$app" "$app" "$user" "$password"
  echo "Updated $env_file"
fi
