# Twenty CRM 本地环境

[English](README.md) | 中文

`setup.sh` 在 Claude Code 远程容器内配置并运行 [RAMC-Management/twenty](https://github.com/RAMC-Management/twenty)。

本目录仅承载环境配置。它不参与本仓库的任何构建，也没有任何 harness 包依赖它。

## 命令

```sh
environment/twenty/setup.sh install   # clone, Node, dependencies, .env, seeded database
environment/twenty/setup.sh start     # PostgreSQL, Redis, server, worker, frontend
environment/twenty/setup.sh status    # health of every service
environment/twenty/setup.sh stop      # stop server, worker, frontend
environment/twenty/setup.sh db        # drop and re-seed the database (destructive)
```

从空容器起，先 `install` 再 `start` 约需十分钟，其中大部分耗在 `yarn install` 和前端首次 Vite 构建上。除 `db` 外，每个子命令都可重复执行。

## 启动后的服务

| 服务 | 地址 |
| --- | --- |
| 前端 | http://localhost:3001 |
| GraphQL（core） | http://localhost:3000/graphql |
| GraphQL（metadata 与鉴权） | http://localhost:3000/metadata |
| REST | http://localhost:3000/rest |
| 健康检查 | http://localhost:3000/healthz |

种子数据以 `tim@apple.dev` 登录，密码同为 `tim@apple.dev`，进入的工作区含 599 家公司与 1200 位联系人。

鉴权 mutation 位于 `/metadata` 而非 `/graphql`。调用方先后调用 `getLoginTokenFromCredentials` 与 `getAuthTokensFromLoginToken` 取得令牌，两次都需传入值为 `http://localhost:3001` 的 `origin`。

## 为何使用本脚本而非官方文档的安装步骤

Twenty 的本地安装指南为 PostgreSQL 与 Redis 提供了 Docker 方案，并以 `corepack enable` 安装 Yarn。容器的出口策略把这两条路都堵死了。

Docker Hub 的 blob 请求从 `production.cloudfront.docker.com` 返回 403，因此 `make -C packages/twenty-docker postgres-on-docker` 无法拉取镜像。脚本改用系统的 PostgreSQL 16 与 Redis 7 软件包，也就是指南中的 Option 1。Twenty 只需要 `uuid-ossp`、`unaccent` 和 `citext` 三个扩展，它们都随 `postgresql-contrib` 一同提供。

`corepack enable` 从 `repo.yarnpkg.com` 返回 403。脚本跳过 corepack，直接把 `yarn` 指向仓库自带并通过 `yarnPath` 固定的 `.yarn/releases/yarn-4.13.0.cjs`。

Node 24 安装到 `/opt/node24`，因为容器默认的 Node 22 不满足仓库 `^24.5.0` 的 engine 约束。

## 说明

日志与 PID 文件写入 `/var/log/twenty`，可用 `TWENTY_LOG_DIR` 覆盖。检出目录默认为 `/home/user/ramc-management/twenty`，可用 `TWENTY_DIR` 覆盖。

`APP_SECRET` 在首次运行时由 `openssl rand` 生成。`.env.example` 中的占位值不会被使用，因此令牌不会用公开值签名。

各服务在各自独立的进程组中启动，因此 `stop` 能向整棵 nx、nest 与 Vite 进程树发送信号，而不只是发给 `npx` 父进程。

容器的可写磁盘与进程无法在回收后留存，但检出目录与已安装的工具链可以在重启后留存。重启之后只需执行 `start`；种子数据库保存在系统 PostgreSQL 的数据目录中。
