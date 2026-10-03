# Infra

Shared services for apps on the VPS. Each service lives in its own folder and is pulled into the root `compose.yml` via `include`, so everything runs from this directory with one `.env`.

| Service | Folder   |
|---------|----------|
| MySQL   | `mysql/` |

## Setup

```bash
docker network create database   # once per VPS
cp .env.example .env              # then set MYSQL_ROOT_PASSWORD
chmod 600 .env
docker compose up -d             # run from this directory
```

Always run `docker compose` from this directory. Running it inside `mysql/` won't find `.env`.

## MySQL

One MySQL 8.4 instance shared by multiple apps. Each app gets its own database and a user that can only access that database.

MySQL listens on `127.0.0.1:3306` only. Apps connect over the `database` Docker network using host `mysql`.

### Access

Root can only log in from inside the container (`MYSQL_ROOT_HOST=localhost`):

```bash
ssh user@your-vps
docker exec -it mysql mysql -uroot -p
```

From your machine, use an SSH tunnel and log in as an app user:

```bash
ssh -N -L 3307:127.0.0.1:3306 user@your-vps
# connect your DB client to 127.0.0.1:3307 as e.g. orders_user
```

Root doesn't work over the tunnel: MySQL sees the connection coming from a Docker bridge IP, not `localhost`.

### Managing app databases

```bash
./mysql/scripts/create-app-db.sh orders                     # db `orders`, user `orders_user`
./mysql/scripts/create-app-db.sh orders --user orders_svc   # custom username
./mysql/scripts/rotate-password.sh orders                   # new password, same user
./mysql/scripts/drop-app-db.sh orders                       # asks for confirmation
```

- The password is generated, printed once, and saved to `.env` as `ORDERS_DB_NAME`, `ORDERS_DB_USER` and `ORDERS_DB_PASSWORD`.
- Use `--env-file PATH` to write to a different file (for example the app's own `.env`), or `--no-env-file` to only print.
- If you created an app with `--user`, pass the same `--user` to `rotate-password.sh` and `drop-app-db.sh`.
- Names: lowercase letters, digits and `_`, starting with a letter. Usernames max 32 characters.
- `create-app-db.sh` refuses to run if the database or user already exists.
- The user gets `ALL PRIVILEGES` on its own database only (Flyway needs DDL), with no global privileges.
- Set `MYSQL_CONTAINER` if the container isn't named `mysql`.
- Stop the app before dropping its database: `DROP USER` doesn't end open sessions.
