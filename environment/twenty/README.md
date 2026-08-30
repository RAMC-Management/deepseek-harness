# Twenty CRM local environment

English | [中文](README.zh.md)

`setup.sh` provisions and runs [RAMC-Management/twenty](https://github.com/RAMC-Management/twenty) inside a Claude Code remote container.

This directory holds environment provisioning only. It builds nothing in this repository and no harness package depends on it.

## Commands

```sh
environment/twenty/setup.sh install   # clone, Node, dependencies, .env, seeded database
environment/twenty/setup.sh start     # PostgreSQL, Redis, server, worker, frontend
environment/twenty/setup.sh status    # health of every service
environment/twenty/setup.sh stop      # stop server, worker, frontend
environment/twenty/setup.sh db        # drop and re-seed the database (destructive)
```

`install` then `start` takes roughly ten minutes from an empty container, most of it in `yarn install` and the frontend's first Vite build. Every subcommand except `db` is idempotent.

## What comes up

| Service | Address |
| --- | --- |
| Frontend | http://localhost:3001 |
| GraphQL (core) | http://localhost:3000/graphql |
| GraphQL (metadata and auth) | http://localhost:3000/metadata |
| REST | http://localhost:3000/rest |
| Health | http://localhost:3000/healthz |

The seed data signs in as `tim@apple.dev` with password `tim@apple.dev`, landing in a workspace of 599 companies and 1200 people.

Auth mutations live on `/metadata`, not `/graphql`. A caller obtains a token with `getLoginTokenFromCredentials` followed by `getAuthTokensFromLoginToken`, sending an `origin` of `http://localhost:3001` on both.

## Why this script exists rather than the documented setup

Twenty's local-setup guide offers Docker for PostgreSQL and Redis, and `corepack enable` for Yarn. The container's egress policy closes both.

Docker Hub blob fetches return 403 from `production.cloudfront.docker.com`, so `make -C packages/twenty-docker postgres-on-docker` cannot pull an image. The script uses the system PostgreSQL 16 and Redis 7 packages instead, which is the guide's Option 1. Twenty needs only the `uuid-ossp`, `unaccent`, and `citext` extensions, all of which ship in `postgresql-contrib`.

`corepack enable` returns 403 from `repo.yarnpkg.com`. The script skips corepack and shims `yarn` onto the release the repository already vendors at `.yarn/releases/yarn-4.13.0.cjs` and pins through `yarnPath`.

Node 24 is installed to `/opt/node24` because the container's default Node 22 does not satisfy the repository's `^24.5.0` engine constraint.

## Notes

Logs and PID files are written to `/var/log/twenty`, overridable with `TWENTY_LOG_DIR`. The checkout defaults to `/home/user/ramc-management/twenty`, overridable with `TWENTY_DIR`.

`APP_SECRET` is generated with `openssl rand` on first run. The `.env.example` placeholder is never used, so tokens are not signed with a published value.

Services are launched into their own process groups so `stop` signals the whole nx, nest, and Vite tree rather than only the `npx` parent.

The container's writable disk and processes do not survive reclamation, but the checkout and installed toolchain do survive a restart. After a restart, `start` alone is enough; the seeded database persists in the system PostgreSQL data directory.
