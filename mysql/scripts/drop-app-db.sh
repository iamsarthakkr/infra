#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <app_name> [--user NAME] [--env-file PATH]

PERMANENTLY drops database <app_name> and its user, and removes the
credentials block from the env file. Asks for confirmation first.

Options:
  --user NAME       Username (default: <app_name>_user)
  --env-file PATH   Env file to clean up (default: $DEFAULT_ENV_FILE)
EOF
}

app=""
user=""
env_file="$DEFAULT_ENV_FILE"

while [ $# -gt 0 ]; do
  case "$1" in
    --user)     user="${2:?--user needs a value}"; shift 2 ;;
    --env-file) env_file="${2:?--env-file needs a value}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         usage >&2; die "unknown option $1" ;;
    *)
      [ -z "$app" ] || die "unexpected argument $1"
      app="$1"; shift ;;
  esac
done

[ -n "$app" ] || { usage >&2; exit 1; }
user="${user:-${app}_user}"

validate_identifier "database name" "$app" "$MAX_DB_NAME_LEN"
validate_identifier "username" "$user" "$MAX_USER_NAME_LEN"

require_container_running

db_found=false
user_found=false
database_exists "$app" && db_found=true
user_exists "$user" && user_found=true

if [ "$db_found" = false ] && [ "$user_found" = false ]; then
  die "neither database '$app' nor user '$user' exists"
fi

echo "This will PERMANENTLY delete:"
[ "$db_found" = true ]   && echo "  - database '$app' and all its data"
[ "$user_found" = true ] && echo "  - user '$user'"
echo
read -r -p "Type the app name ($app) to confirm: " confirmation
[ "$confirmation" = "$app" ] || die "confirmation did not match, nothing was dropped"

# DROP USER does not end existing sessions; the app should be stopped first.
run_sql <<SQL
DROP DATABASE IF EXISTS \`$app\`;
DROP USER IF EXISTS '$user'@'%';
SQL

echo "Dropped database '$app' and user '$user'."

if [ -f "$env_file" ]; then
  remove_env_block "$env_file" "$app"
  echo "Removed credentials for '$app' from $env_file"
fi
