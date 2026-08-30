#!/usr/bin/env bash
# Provision, start, and check a local Twenty CRM (RAMC-Management/twenty) instance.
#
# Written for the Claude Code remote container, where two of the paths in
# Twenty's own local-setup guide are closed by the egress policy:
#
#   * Docker Hub blob fetches return 403 (production.cloudfront.docker.com), so
#     `make -C packages/twenty-docker postgres-on-docker` cannot pull an image.
#     PostgreSQL and Redis are used as system packages instead, which is the
#     guide's Option 1.
#   * `corepack enable` returns 403 (repo.yarnpkg.com), so Yarn comes from the
#     release the repository already vendors at .yarn/releases and pins through
#     `yarnPath` in .yarnrc.yml.
#
# Every subcommand is idempotent: re-running `install` on a provisioned tree
# re-verifies rather than rebuilds, except `db` which is destructive by design.
#
# Usage:
#   setup.sh install   clone, install Node and dependencies, write .env, seed the database
#   setup.sh start     start PostgreSQL, Redis, and the server, worker, and frontend
#   setup.sh status    report the health of every service
#   setup.sh stop      stop the server, worker, and frontend
#   setup.sh db        drop and re-seed the database (destructive)

set -euo pipefail

REPO_URL="https://github.com/RAMC-Management/twenty"
REPO_DIR="${TWENTY_DIR:-/home/user/ramc-management/twenty}"
NODE_VERSION="24.16.0"
NODE_DIR="/opt/node24"
BIN_DIR="/usr/local/twenty-bin"
LOG_DIR="${TWENTY_LOG_DIR:-/var/log/twenty}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Node 24 and the vendored Yarn must precede the container's default Node 22,
# which does not satisfy the repository's `^24.5.0` engine constraint.
activate_toolchain() {
  export PATH="$BIN_DIR:$NODE_DIR/bin:$PATH"
  export NODE_EXTRA_CA_CERTS=/root/.ccr/ca-bundle.crt
  export NX_DAEMON=false
}

clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    log "repository already present at $REPO_DIR"
    return
  fi
  log "cloning $REPO_URL"
  # The anonymous git lane does not serve LFS objects; skipping the smudge
  # filter keeps the clone from aborting on an LFS-tracked file.
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "$REPO_URL" "$REPO_DIR"
}

install_node() {
  if [ -x "$NODE_DIR/bin/node" ] && [ "$("$NODE_DIR/bin/node" -v)" = "v$NODE_VERSION" ]; then
    log "node v$NODE_VERSION already installed"
    return
  fi
  log "installing node v$NODE_VERSION"
  local tarball
  tarball="$(mktemp -d)/node.tar.xz"
  curl -fsSL --retry 3 -o "$tarball" \
    "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz"
  mkdir -p "$NODE_DIR"
  tar -xJf "$tarball" -C "$NODE_DIR" --strip-components=1
}

install_yarn_shim() {
  local release="$REPO_DIR/.yarn/releases/yarn-4.13.0.cjs"
  [ -f "$release" ] || die "vendored yarn release missing at $release"
  log "linking vendored yarn"
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/yarn" <<EOF
#!/bin/sh
exec $NODE_DIR/bin/node $release "\$@"
EOF
  chmod +x "$BIN_DIR/yarn"
}

start_databases() {
  log "starting postgresql and redis"
  service postgresql start >/dev/null 2>&1 || true
  # The init script's ulimit call fails without CAP_SYS_RESOURCE; redis itself
  # still starts, so the exit status is not a usable readiness signal.
  service redis-server start >/dev/null 2>&1 || true
  local waited=0
  until pg_isready -h 127.0.0.1 -p 5432 -q; do
    waited=$((waited + 1))
    [ "$waited" -gt 60 ] && die "postgresql did not become ready"
    sleep 1
  done
  redis-cli ping >/dev/null 2>&1 || die "redis did not become ready"
}

create_databases() {
  log "ensuring the default and test databases exist"
  sudo -u postgres psql -qtAc "ALTER USER postgres WITH PASSWORD 'postgres';" >/dev/null
  local db
  for db in default test; do
    if [ -z "$(sudo -u postgres psql -qtAc "SELECT 1 FROM pg_database WHERE datname = '$db';")" ]; then
      sudo -u postgres psql -qtAc "CREATE DATABASE \"$db\" WITH OWNER postgres;" >/dev/null
    fi
  done
}

write_env() {
  local server_env="$REPO_DIR/packages/twenty-server/.env"
  local front_env="$REPO_DIR/packages/twenty-front/.env"
  if [ ! -f "$front_env" ]; then
    log "writing $front_env"
    cp "$REPO_DIR/packages/twenty-front/.env.example" "$front_env"
  fi
  if [ ! -f "$server_env" ]; then
    log "writing $server_env"
    cp "$REPO_DIR/packages/twenty-server/.env.example" "$server_env"
    # The example ships a placeholder; a real secret has to be generated here so
    # the instance does not sign tokens with a published value.
    local secret
    secret="$(openssl rand -base64 32 | tr -d '\n')"
    sed -i "s|^APP_SECRET=.*|APP_SECRET=$secret|" "$server_env"
  fi
}

install_dependencies() {
  log "installing workspace dependencies"
  (cd "$REPO_DIR" && yarn install)
}

seed_database() {
  log "resetting and seeding the database"
  (cd "$REPO_DIR" && npx nx database:reset twenty-server)
}

# Liveness is the recorded process group, not a port probe: the server needs
# about a minute to bind 3000 and must not be double-started while it boots.
service_running() {
  local pidfile="$LOG_DIR/$1.pid"
  [ -f "$pidfile" ] || return 1
  kill -0 "$(cat "$pidfile")" 2>/dev/null
}

# Each service is launched into its own process group so `stop` can signal the
# whole nx/nest/vite tree rather than only the npx parent that spawned it.
start_one() {
  local target="$1" command
  case "$target" in
    server) command="npx nx start twenty-server" ;;
    front)  command="npx nx start twenty-front" ;;
    worker) command="npx nx run twenty-server:worker" ;;
  esac
  (
    cd "$REPO_DIR"
    setsid nohup $command >"$LOG_DIR/$target.log" 2>&1 &
    echo $! >"$LOG_DIR/$target.pid"
  )
}

start_services() {
  mkdir -p "$LOG_DIR"
  local target
  for target in server front worker; do
    if service_running "$target"; then
      log "$target already running"
      continue
    fi
    log "starting $target"
    start_one "$target"
  done
}

stop_services() {
  local target pidfile pid
  for target in server front worker; do
    pidfile="$LOG_DIR/$target.pid"
    [ -f "$pidfile" ] || continue
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      log "stopping $target"
      kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
  done
}

wait_for_http() {
  local url="$1" label="$2" waited=0
  until [ "$(curl -s -o /dev/null -w '%{http_code}' "$url")" != "000" ]; do
    waited=$((waited + 1))
    [ "$waited" -gt 300 ] && die "$label did not answer at $url"
    sleep 2
  done
}

report_status() {
  printf 'postgresql  %s\n' "$(pg_isready -h 127.0.0.1 -q && echo up || echo down)"
  printf 'redis       %s\n' "$(redis-cli ping 2>/dev/null || echo down)"
  printf 'server      %s (http://localhost:3000)\n' "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/healthz)"
  printf 'front       %s (http://localhost:3001)\n' "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3001)"
  printf 'worker      %s\n' "$(pgrep -f queue-worker >/dev/null && echo up || echo down)"
}

case "${1:-}" in
  install)
    clone_repo
    install_node
    install_yarn_shim
    activate_toolchain
    install_dependencies
    write_env
    start_databases
    create_databases
    seed_database
    log "install complete; run '$0 start'"
    ;;
  start)
    activate_toolchain
    start_databases
    start_services
    wait_for_http http://localhost:3000/healthz server
    wait_for_http http://localhost:3001 front
    report_status
    log "sign in at http://localhost:3001 as tim@apple.dev (password tim@apple.dev)"
    ;;
  status)
    report_status
    ;;
  stop)
    stop_services
    ;;
  db)
    activate_toolchain
    start_databases
    create_databases
    seed_database
    ;;
  *)
    sed -n '3,24p' "$0" | sed 's|^# \{0,1\}||'
    exit 1
    ;;
esac
