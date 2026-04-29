<p align="center">
  <img src="./assets/logo.svg" alt="WordPress Splendid logo" width="160" height="160"/>
</p>

<h1 align="center">WordPress Splendid</h1>
<p align="center"><sub><code>wp-splendid</code></sub></p>

<p align="center">

[![License: WTFPL](https://img.shields.io/badge/License-WTFPL-brightgreen.svg)](http://www.wtfpl.net/)
[![WordPress](https://img.shields.io/badge/WordPress-latest-21759B?logo=wordpress&logoColor=white)](https://wordpress.org/)
[![PHP](https://img.shields.io/badge/PHP-8.5--FPM-777BB4?logo=php&logoColor=white)](https://www.php.net/)
[![Nginx](https://img.shields.io/badge/Nginx-alpine-009639?logo=nginx&logoColor=white)](https://nginx.org/)
[![MySQL](https://img.shields.io/badge/MySQL-LTS-4479A1?logo=mysql&logoColor=white)](https://www.mysql.com/)
[![Redis](https://img.shields.io/badge/Redis-8--alpine-DC382D?logo=redis&logoColor=white)](https://redis.io/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Podman](https://img.shields.io/badge/Podman-Compose-892CA0?logo=podman&logoColor=white)](https://podman.io/)

</p>

<p align="center">
Self-hosted WordPress stack defined entirely as a Compose deployment (Docker or Podman).<br/>
No application code lives in this repository — only the infrastructure configuration.
</p>

---

## Architecture

```
Internet → Nginx :8080 → PHP-FPM (wordpress:9000)
                              ↓              ↓
                           MySQL          Redis
```

| Service     | Image                  | Role                                                      |
|-------------|------------------------|-----------------------------------------------------------|
| `nginx`     | `nginx:alpine`         | Reverse proxy, static cache, security headers, rate-limit |
| `wordpress` | `wordpress:php8.5-fpm` | PHP-FPM only, never exposed to the host                   |
| `db`        | `mysql:lts`            | Database, persisted under `./db/`                         |
| `redis`     | `redis:8-alpine`       | WordPress object cache (W3TC / Redis Object Cache)        |

All services share the internal bridge network `wp-network`. Redis and MySQL are **not** published on the host.

---

## Requirements

- [Podman](https://podman.io/) + [podman-compose](https://github.com/containers/podman-compose)
- *or* [Docker](https://docs.docker.com/get-docker/) + [Docker Compose](https://docs.docker.com/compose/)

On Fedora / RHEL with SELinux enforcing, the volume mounts in `docker-compose.yml` use `:Z` / `:z` labels — no extra configuration is required.

---

## Quick start

```sh
# 1. Clone and enter the directory
git clone <url> wp-splendid && cd wp-splendid

# 2. Create the secrets file
cp .env.example .env

# Generate WordPress salts:
curl -s https://api.wordpress.org/secret-key/1.1/salt/

# Generate strong passwords:
openssl rand -base64 32

# 3. Start the stack
podman compose up -d        # or: docker compose up -d

# 4. Open the site
xdg-open http://localhost:8080
```

---

## Common commands

```sh
# Tail logs
podman compose logs -f nginx wordpress db redis

# Validate Compose syntax
podman compose config --quiet

# Shell into the WordPress container (for wp-cli, etc.)
podman compose exec wordpress bash

# MySQL client
podman compose exec db mysql -u${DB_USER} -p ${DB_NAME}

# Stop without deleting data
podman compose down
```

---

## Repository layout

```
.
├── docker-compose.yml       # Service definitions, hardening, healthchecks
├── .env.example             # Environment variable template
├── assets/
│   └── logo.svg             # Project logo
├── nginx/
│   ├── default.conf         # Virtual host (FastCGI, W3TC cache, rate-limit)
│   └── header.conf          # Security headers (CSP, HSTS, frame, …)
├── db/
│   └── my.cnf               # InnoDB / MySQL tuning
├── redis-data/              # Persisted Redis data (gitignored)
└── wordpress/               # WordPress core + plugins + themes (gitignored)
```

---

## Configuration

### Environment variables (`.env`)

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `DB_NAME`                 | MySQL database name                           |
| `DB_USER`                 | MySQL user                                    |
| `DB_PASSWORD`             | MySQL password (plaintext, hashed by MySQL)   |
| `REDIS_PASSWORD`          | Redis `requirepass` value                     |
| `WP_*_KEY` / `WP_*_SALT`  | 8 WordPress salts (see `.env.example`)        |

Never commit `.env` — it is excluded via `.gitignore`.

### Page cache (W3 Total Cache)

Nginx looks for pre-rendered HTML files under `wp-content/cache/page_enhanced/` before passing the request to PHP. The cache is bypassed for:

- POST requests
- non-empty query strings
- WordPress / WooCommerce / comment-author cookies

If you swap caching plugins, update the `try_files` chain in `nginx/default.conf`.

### Security headers

`nginx/header.conf` is mounted at `/etc/nginx/conf.d/headers.conf` and re-included in every `location` block. It provides:

- `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`, `X-Download-Options`, `X-Permitted-Cross-Domain-Policies`
- `Content-Security-Policy` (tighten per your third-party domains)
- HSTS — commented; enable only after HTTPS is in place
- CORS — disabled by default; enable per origin if needed

### SSL / HTTPS

Not configured in this repository (HTTP only on port 8080). To enable HTTPS:

1. Mount your certificates into the `nginx` container.
2. Add a `listen 443 ssl http2` block in `nginx/default.conf`.
3. Uncomment the `Strict-Transport-Security` header in `nginx/header.conf`.
4. Review the CSP if you add third-party HTTPS resources.

---

## Hardening

Container layer:

- `security_opt: no-new-privileges:true` on every service
- `cap_drop: [ALL]` on `nginx` and `redis`, with a minimal `cap_add` set
- `mem_limit` set per service (nginx 128m, wordpress 512m, db 1g, redis 256m)
- `logging` driver capped at 10 MB × 3 files to prevent log-disk fill
- Healthchecks on `db` and `redis`; `wordpress` waits on both via `service_healthy`

Application layer:

- PHP-FPM never exposed to the host — only reachable by Nginx on the internal network
- Redis and MySQL never exposed to the host
- `wp-login.php` rate-limited to 5 req/min per IP (burst 3)
- Author enumeration blocked (`?author=N` → 403)
- `xmlrpc.php` and `wp-config.php` denied at the Nginx layer
- `server_tokens off` — Nginx version hidden
- `MYSQL_RANDOM_ROOT_PASSWORD=1` — root password is randomized and unknown
- WordPress hardening constants: `DISALLOW_FILE_EDIT`, `WP_AUTO_UPDATE_CORE='minor'`, `WP_DEBUG=false`, `WP_DEBUG_DISPLAY=false`

---

## License

This project is released under the [WTFPL](http://www.wtfpl.net/) — see [`LICENSE`](./LICENSE).
Do What The Fuck You Want To Public License.
