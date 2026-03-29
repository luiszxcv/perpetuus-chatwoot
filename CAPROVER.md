# CapRover deploy

This repository is deployed to CapRover from source, not from `chatwoot/chatwoot`.

## Apps

Create two CapRover apps that both point to this repository and the `main` branch:

- `chatwoot-web`
- `chatwoot-worker`

Use a different captain-definition path for each app:

- web: `./captain-definition-web`
- worker: `./captain-definition-worker`

Both files build the same image from `./Dockerfile.captain`. The runtime role is selected through `CW_RUNTIME_COMMAND`.

## Web app

Recommended settings:

- Exposed as web app: `yes`
- Container HTTP Port: `3000`
- `CW_RUNTIME_COMMAND=bundle exec rails s -p 3000 -b 0.0.0.0`

## Worker app

Recommended settings:

- Exposed as web app: `no`
- `CW_RUNTIME_COMMAND=bundle exec sidekiq -C config/sidekiq.yml`

## Shared environment

Set the same runtime environment variables on both apps, for example:

- `RAILS_ENV=production`
- `NODE_ENV=production`
- `INSTALLATION_ENV=docker`
- `FRONTEND_URL`
- `SECRET_KEY_BASE`
- `DATABASE_URL`
- `REDIS_URL`
- `REDIS_PASSWORD` if you use password-based Redis setup
- Active Storage / S3 variables if uploads are enabled
- Mailer / SMTP variables
- WhatsApp / provider variables you use in production

## Databases

Recommended supporting services:

- PostgreSQL 16
- Redis 7

Both `chatwoot-web` and `chatwoot-worker` must point to the same PostgreSQL and Redis instances.

## Deploy flow

1. CapRover pulls this repository.
2. It builds `Dockerfile.captain` from the repo contents.
3. `chatwoot-web` starts Rails with `CW_RUNTIME_COMMAND`.
4. `chatwoot-worker` starts Sidekiq with `CW_RUNTIME_COMMAND`.

## Upgrades

To upgrade later:

1. Merge the desired upstream Chatwoot version into this repository.
2. Keep or adapt local custom patches.
3. Push to `main`.
4. Redeploy both CapRover apps.

Because both apps build from this repository, your custom WhatsApp tracking changes are included automatically.
