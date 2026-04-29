# Repository Guidelines

## Project Structure & Module Organization

This repository defines a Docker Compose WordPress stack. `docker-compose.yml` wires together Nginx, WordPress PHP-FPM, MySQL, and Redis. Nginx configuration lives in `nginx/`, with the virtual host in `nginx/default.conf` and shared headers in `nginx/header.conf`. MySQL configuration is in `db/my.cnf`; `db/` also persists database files. `redis-data/` stores Redis data. `wordpress/` is mounted as `/var/www/html` for WordPress core, themes, plugins, and uploads when present.

## Build, Test, and Development Commands

Use Docker Compose from the repository root:

```sh
docker compose up -d
```

Starts the stack. Nginx publishes the site at `http://localhost:8080`.

```sh
docker compose logs -f nginx wordpress db redis
```

Streams logs for startup, PHP, database, or cache issues.

```sh
docker compose config
```

Validates Compose syntax and expands environment substitutions.

```sh
docker compose down
```

Stops containers without deleting persisted local data.

## Coding Style & Naming Conventions

Use two-space indentation in YAML and four-space indentation in Nginx and MySQL config blocks, matching the existing files. Keep service names lowercase and descriptive, such as `wordpress`, `db`, and `redis`. Prefer explicit mounted paths and read-only flags for configuration mounts, for example `./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro`. Do not commit generated cache, database, or upload artifacts.

## Testing Guidelines

There is no application test suite in this repository. Treat configuration validation as the baseline check: run `docker compose config` before submitting changes. For service changes, start the stack, inspect logs, and confirm the site responds at `localhost:8080`. When editing themes or plugins under `wordpress/`, add tests using that component's tooling.

## Commit & Pull Request Guidelines

This checkout does not include Git history, so no project-specific convention can be inferred. Use concise, imperative subjects such as `Update nginx cache headers` or `Add Redis password configuration`. Pull requests should describe the affected service, list validation commands, link related issues, and include screenshots only for visible WordPress or admin UI changes.

## Security & Configuration Tips

Keep secrets in an untracked `.env` file referenced by Compose variables such as `DB_USER`, `DB_PASSWORD`, `DB_NAME`, and `REDIS_PASSWORD`. Do not hardcode salts or passwords in committed files. After renaming config files, verify that Compose volume paths and Nginx `include` directives still point to existing files.
