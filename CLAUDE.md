# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

A self-hosted WordPress stack defined entirely as a Docker Compose deployment. There is no application code in this repo — only infrastructure configuration. WordPress core/themes/plugins are expected to populate `wordpress/` at runtime (the directory is empty in source control and is bind-mounted into the `wordpress` container as `/var/www/html`).

## Common commands

Run from the repository root:

```sh
docker compose up -d                              # start the stack (site at http://localhost:8080)
docker compose down                               # stop, preserving ./db, ./redis-data, ./wordpress
docker compose logs -f nginx wordpress db redis   # tail logs
docker compose config                             # validate compose syntax + env substitution
docker compose exec wordpress bash                # shell into WP container (for wp-cli, etc.)
docker compose exec db mysql -u${DB_USER} -p ${DB_NAME}
```

There is no application test suite. The baseline check before submitting changes is `docker compose config` plus a smoke test against `localhost:8080`.

## Architecture

Four services on a shared bridge network `wp-network`:

- **nginx** (`nginx:alpine`, port `8080→80`) — public entry point. Mounts `wordpress/` read-only and proxies `*.php` to `wordpress:9000` via FastCGI. WordPress is **not** directly exposed.
- **wordpress** (`wordpress:php8.5-fpm`) — PHP-FPM only, no built-in web server. Reads DB credentials and WP salts from `.env` via Compose env vars. `WORDPRESS_CONFIG_EXTRA` injects Redis object-cache constants and rewrites `REMOTE_ADDR` from `X-Forwarded-For` so plugins see the real client IP.
- **db** (`mysql:lts`) — uses `mysql_native_password` auth (required for older WP installs / some plugins). Data persists at `./db/`.
- **redis** (`redis/redis-stack:7.4.0-v8`) — used as WP object cache. Ports `6379` (data) and `8001` (RedisInsight UI) are exposed to the host. Password comes from `REDIS_PASSWORD` via `REDIS_ARGS`.

### Request flow and caching

Nginx serves a `try_files` chain that looks for **W3 Total Cache** page-cache HTML (`/wp-content/cache/page_enhanced/...`) before falling through to PHP. The `$w3tc_rewrite` flag disables cache hits for POST requests, non-empty query strings, and logged-in / WooCommerce / commenting cookies. If you change caching plugins, this `try_files` chain in `nginx/default.conf` must be updated to match — otherwise Nginx will serve stale or missing cache files.

`set_real_ip_from 172.16.0.0/12` covers Docker's default bridge range; if Compose is reconfigured to use a different subnet, update this directive.

## Configuration files and known inconsistencies

Be aware before editing:

- **`nginx/header.conf` is not mounted.** `docker-compose.yml` only mounts `nginx/default.conf`. However, `default.conf` does `include /etc/nginx/conf.d/headers.conf` (note the plural filename). Currently neither the file nor the include path resolves inside the container. To enable security headers, mount `nginx/header.conf` as `/etc/nginx/conf.d/headers.conf` in the `nginx` service.
- **`db/my.cnf` mount path is wrong.** Compose mounts `./mysql/my.cnf` but the file actually lives at `./db/my.cnf`. The custom MySQL tuning is therefore not in effect.
- **`${CORS_ORIGIN}` is referenced literally in nginx config** but Nginx does not expand env vars in config by default. To use it, switch to the `nginx` image's `templates/` mechanism (envsubst on `*.template` files) or hardcode the origin.

These three issues are pre-existing — flag them when relevant but don't silently rewrite without checking with the user, since they may be intentional WIP.

## Secrets and `.env`

`.env` is the single source of truth for `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `REDIS_PASSWORD`, and the eight `WP_*_KEY` / `WP_*_SALT` values. WordPress salts must be regenerated (e.g. via https://api.wordpress.org/secret-key/1.1/salt/) per environment — never reuse them across deployments. Never hardcode salts/passwords in committed files.

## Style

- YAML: 2-space indent. Nginx and MySQL config: 4-space indent. Match existing files.
- Mount configuration files read-only (`:ro`) wherever the container does not need to write them.
- Service names stay lowercase and descriptive (`wordpress`, `db`, `redis`, `nginx`).
- Don't commit anything under `db/` (other than `my.cnf`), `redis-data/`, or `wordpress/wp-content/cache|uploads`.
