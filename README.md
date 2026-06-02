# MCSManager-lsio

基于 [LinuxServer.io](https://linuxserver.io) 基础镜像构建的 [MCSManager](https://github.com/MCSManager/MCSManager) Docker 镜像——一个现代化、分布式的 Minecraft 和 Steam 游戏服务器管理面板。

## 关于 MCSManager

MCSManager（简称 MCSM）是一款快速部署、分布式架构、多用户、基于 Web 的游戏服务器管理面板，支持 **Minecraft**、**Steam** 游戏（如帕鲁、泰拉瑞亚、僵尸毁灭工程等）以及自定义命令程序。它支持在一台面板上管理多台物理或虚拟服务器，并提供安全、精细的多用户权限系统。

- 官网：[mcsmanager.com](https://mcsmanager.com)
- 源码：[github.com/MCSManager/MCSManager](https://github.com/MCSManager/MCSManager)

---

## 本项目提供什么

本项目将 MCSManager 的容器化方案迁移到 **LinuxServer.io 基础镜像**之上，复用 LinuxServer 社区多年打磨的容器最佳实践。两个核心组件分别使用不同的基础镜像以兼顾稳定性和轻量化：

| 组件 | 基础镜像 | 说明 |
|------|----------|------|
| **Web 面板** (`mcsm-web`) | `ghcr.io/linuxserver/baseimage-alpine:edge` | 基于 Alpine Linux，极致轻量 |
| **Daemon 守护进程** (`mcsm-daemon`) | `ghcr.io/linuxserver/baseimage-debian:trixie` | 基于 Debian，兼容性更好（内置 JDK 支持） |

---

## LinuxServer Base Image 提供的功能

LinuxServer.io 的基础镜像围绕 **s6-overlay** 进程管理系统精心构建，为本项目提供了以下开箱即用的能力：

### 1. s6-overlay 进程监督系统

s6-overlay 是一个专为容器设计的**轻量级 init 系统**。在传统 Docker 容器中，应用进程直接以 PID 1 运行；而使用 s6-overlay 后，s6-svscan 作为 PID 1 运行，提供：

- **僵尸进程回收**：自动回收所有孤儿进程，避免进程表污染
- **服务依赖管理**：通过 `dependencies.d/` 声明服务启动顺序（例如：先完成配置初始化 → 再启动 MCSM 服务）
- **优雅终止**：`docker stop` 时向所有 s6 管理下的服务进程发送 `SIGTERM`，等待进程完成清理后退出
- **自动重启**：服务异常退出后 s6 自动重新拉起，保持高可用
- **就绪通知**：通过 `notification-fd` 文件描述符，服务可以在就绪后主动通知 s6，实现精确的就绪探测

本仓库中，s6-overlay 的配置位于：
- `daemon/etc/s6-overlay/s6-rc.d/` — Daemon 端的 init / service 脚本
- `web/etc/s6-overlay/s6-rc.d/` — Web 端的 init / service 脚本

### 2. PUID / PGID 用户映射

默认情况下，Docker 容器的所有进程以 **root** 运行，容器内创建的所有文件（日志、配置、数据）在宿主机上属于 root 用户。LinuxServer 基础镜像内置了用户映射机制：启动容器时指定 `PUID=1000` 和 `PGID=1000`（宿主机用户的 uid/gid），容器内的应用就会以**宿主机普通用户身份**运行。读写挂载卷时，文件的所有者自动匹配宿主机用户。

这是 LinuxServer 社区经过大量生产验证的最佳实践。

### 3. TZ 时区环境变量

通过 `TZ=Asia/Shanghai` 环境变量即可设定容器时区，确保日志时间戳与宿主机一致。无需额外挂载 `/etc/localtime` 文件。

### 4. 自定义脚本（Custom Scripts）

挂载一个目录到 `/custom-cont-init.d`，将其中的可执行脚本放入即可在**容器每次启动时、所有服务启动前**执行。典型场景：

- 安装额外系统包（如 `ffmpeg`、`jq` 等工具）
- 从外部拉取配置文件
- 执行数据库迁移

```bash
# 示例：自定义启动脚本 /custom-cont-init.d/install-tools
#!/bin/bash
echo "**** 安装额外依赖 ****"
apk add --no-cache curl jq
```

### 5. 自定义服务（Custom Services）

挂载目录到 `/custom-services.d`，放入可执行脚本即可作为**独立服务**与 MCSManager 并行运行。s6-overlay 会监督这些服务，异常退出时自动重启。典型场景：

- 运行 Sidecar 代理（如 Cloudflare Tunnel）
- 启动监控守护进程
- 运行定时备份脚本

### 6. Docker Mods 扩展生态

通过 `DOCKER_MODS` 环境变量，可以引用 LinuxServer 社区发布的**通用扩展层**。这些 Mod 以 Docker 镜像 Layer 的形式提供，在容器启动时动态拉取并应用。例如：

```yaml
environment:
  - DOCKER_MODS=linuxserver/mods:universal-cloudflared
```

这在不修改 Dockerfile、不重新构建镜像的情况下，为容器添加 Cloudflare Tunnel 支持。社区贡献了大量 Mod 可供使用。

### 7. 标准化的 /config 路径

虽然 MCSManager 本身不使用 `/config` 目录（数据分别存储在 `data/` 和 `logs/` 中），但 LinuxServer 基础镜像内置了对 `/config` 卷的标准化支持。如果你通过 Custom Scripts 生成额外配置，可以将它们输出到 `/config` 并挂载持久化。

### 8. 持续的安全更新

LinuxServer 团队将基础镜像的构建完全自动化。每当底层 Alpine/Debian 发行版发布安全补丁或系统包更新时，CI 系统会自动重新构建基础镜像。下游镜像（包括本项目）可以基于最新的基础层重建，确保运行环境始终包含最新的安全修复。

### 9. 共享基础镜像层

如果你同时运行了多个基于 LinuxServer 基础镜像的容器（例如 Jellyfin、Plex、Sonarr 等），Docker 的镜像分层机制会让这些容器共享同一基础层，减少磁盘占用和拉取带宽。

---

## 与官方 MCSManager Docker 镜像的对比

MCSManager 官方提供 Docker 镜像，源自主仓库 `dockerfile/` 目录下的 Dockerfile，发布在 Docker Hub（`githubyumao/mcsmanager-web`、`githubyumao/mcsmanager-daemon`）和 GitHub Packages（`ghcr.io/mcsmanager/`）。

以下从技术维度对比两种构建方案。

### 基础镜像对比

| 方面 | 本项目（MCSManager-lsio） | 官方 Docker 镜像 |
|------|---------------------------|-------------------|
| **Web 基础镜像** | `ghcr.io/linuxserver/baseimage-alpine:edge` | `node:lts-alpine` |
| **Daemon 基础镜像** | `ghcr.io/linuxserver/baseimage-debian:trixie` | `eclipse-temurin:${VER}-jdk`（Debian 系） |
| **内置 init 系统** | ✅ s6-overlay | 无（直接 `CMD node app.js`） |
| **镜像来源** | LSIO 官方维护、持续更新 | Docker 官方 & Eclipse Temurin 官方 |

官方镜像采用 Docker 生态中最直接的方案——在语言运行时镜像之上直接 `CMD` 启动应用，构建过程直观，Web 端镜像因 Alpine 而体积紧凑。本项目选择了功能更丰富的 LSIO 基础层，在此基础上增加了进程管理和用户映射能力。

### 进程管理方式对比

| | 本项目 | 官方镜像 |
|--|--------|----------|
| **PID 1** | s6-svscan 进程管理器 | Node.js 应用进程 |
| **僵尸进程回收** | ✅ s6 自动回收 | 依赖应用自行处理 |
| **服务守护/自动重启** | ✅ s6 管理，异常退出自动拉取 | 依赖 Docker 的 `restart` 策略 |
| **启动依赖管理** | ✅ dependencies.d 声明式编排 | 无内置依赖管理 |
| **就绪通知** | ✅ notification-fd 机制 | 无内置机制 |

两种方案各有侧重。s6-overlay 提供更完整的进程生命周期管理能力，对于 MCSManager Daemon 这类需要管理大量子进程（游戏服务器实例）的应用尤为契合。官方方案的直接 CMD 模式更简单、更贴近 Docker "一个容器一个进程" 的哲学。

### 用户权限模型对比

| | 本项目 | 官方镜像 |
|--|--------|----------|
| **默认运行用户** | `abc`（非 root，通过 PUID/PGID 自定义） | `root` |
| **用户映射方式** | PUID / PGID 环境变量 | 无内置映射（可通过 Docker `--user` 参数） |
| **卷文件所有权** | 自动归属宿主机用户 | 默认归属 root |

两种方案都可以实现非 root 运行——官方镜像可通过 `docker run --user` 实现，本项目通过 PUID/PGID 实现，只是途径不同。PUID/PGID 的优势在于无需用户了解 Linux UID/GID 映射的底层细节。

### Java / JDK 支持对比

MCSManager Daemon 可以管理 Minecraft 服务器，而 Minecraft 服务端需要 Java 运行环境。两种方案都内置了 Eclipse Temurin JDK，且都提供了不同 JDK 版本的变体。

| | 本项目 | 官方镜像 |
|--|--------|----------|
| **内置 JDK** | ✅ Eclipse Temurin | ✅ Eclipse Temurin |
| **JDK 版本变体** | 5 种（无 JDK / 8 / 11 / 17 / 21 / 25） | 提供多版本（含 jdk8 变体等） |
| **无 JDK 选项** | ✅ `SKIP_JAVA=true` 构建参数 | — |
| **镜像标签示例** | `latest`, `latest-jdk8`, `latest-jdk17` 等 | 通过不同 tag 区分版本 |

本项目提供 5 种变体（含无 JDK 精简版），可灵活适配不同 Minecraft 版本需求。官方镜像同样支持通过不同标签选择 JDK 版本。

### Docker 容器管理能力

MCSManager Daemon 可以通过 Docker 来创建和管理游戏服务器实例。两种方案都需要将宿主机的 Docker socket 挂载到容器中：

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

这一点上两种方案完全一致。如果使用 rootless Docker，则需挂载用户级 socket（`/run/user/<uid>/docker.sock`）并设置 `DOCKER_HOST` 环境变量。

### 扩展性对比

| | 本项目 | 官方镜像 |
|--|--------|----------|
| **添加系统包** | Custom Scripts（挂载脚本目录，无需重建） | 修改 Dockerfile + 重建镜像 |
| **添加 Sidecar 服务** | Custom Services（挂载服务目录） | 额外的 docker-compose 服务 |
| **社区扩展** | Docker Mods 生态 | 无对等机制 |

LinuxServer 的三层扩展体系（Scripts → Services → Mods）使得在不重新构建镜像的前提下即可添加额外功能。官方方案则需要 fork 仓库、修改 Dockerfile、维护自己的构建流水线。

### 多架构与发布策略

| | 本项目 | 官方镜像 |
|--|--------|----------|
| **amd64 (x86_64)** | ✅ | ✅ |
| **arm64 (aarch64)** | ✅ | ✅ |
| **镜像仓库** | GitHub Container Registry (`ghcr.io`) | Docker Hub + GitHub Packages |

---

## 优缺点总结

### 本项目（MCSManager-lsio）的优点

1. **完整的进程生命周期管理**：s6-overlay 提供僵尸进程回收、服务守护、启动依赖编排和就绪通知，对管理大量游戏服务器子进程的场景非常契合。

2. **非 root 运行更便捷**：PUID/PGID 一键配置，卷文件自动归属正确用户，无需额外了解 Linux 用户映射细节。

3. **高度可扩展**：三层扩展体系（Custom Scripts / Custom Services / Docker Mods）使用户无需重新构建镜像即可添加系统包、伴生服务和社区扩展。

4. **多 JDK 变体选择**：5 种 JDK 选项覆盖所有 Minecraft 版本需求，且提供无 JDK 的精简版本用于纯 Steam 游戏管理场景。

5. **生态一致性**：如果你已使用其他 LinuxServer 容器（Plex、Jellyfin、Sonarr 等），本镜像遵循相同的 PUID/PGID/TZ 惯例，切换成本极低。

6. **持续基础更新**：基础镜像跟随 Alpine/Debian 安全更新自动重建，运维负担小。

7. **CI/CD 自动化**：GitHub Actions 工作流支持 Release 触发自动构建多架构、多 JDK 变体。

### 本项目（MCSManager-lsio）的缺点

1. **镜像体积较大**：LinuxServer 基础镜像比 `node:lts-alpine` 多出数十 MB 的 init 系统和工具集。Daemon 端因基于 Debian 差异更明显。

2. **增加学习成本**：用户需要理解 PUID/PGID 的概念。相比官方 "pull & run" 的路径，多了一个概念需要了解。

3. **非官方维护**：本项目不是 MCSManager 官方团队维护，版本跟进可能存在延迟。

4. **基础镜像使用 testing 分支**：Daemon 端依赖 LSIO 的 `trixie`（Debian testing），其包版本稳定性不如稳定版。

5. **首次冷启动较慢**：需要额外拉取 LSIO 基础镜像层。

6. **/config 惯例部分不适用**：MCSManager 不使用 `/config` 路径（数据在 `data/` 和 `logs/` 下），LSIO 的 `/config` 标准化理念在本项目中未被完全利用。

---

## 快速开始

### Web 面板

```yaml
services:
  mcsm-web:
    image: ghcr.io/snowmoonss/mcsm-web:latest
    container_name: mcsm-web
    environment:
      - PUID=1000       # 宿主机用户 UID
      - PGID=1000       # 宿主机用户 GID
      - TZ=Asia/Shanghai
    ports:
      - "23333:23333"
    volumes:
      - ./web/data:/opt/mcsmanager/web/data
      - ./web/logs:/opt/mcsmanager/web/logs
    restart: unless-stopped
```

### Daemon 守护进程

```yaml
services:
  mcsm-daemon:
    image: ghcr.io/snowmoonss/mcsm-daemon:latest          # 不内置 JDK
    # image: ghcr.io/snowmoonss/mcsm-daemon:latest-jdk17  # 内置 JDK 17
    # image: ghcr.io/snowmoonss/mcsm-daemon:latest-jdk8   # 内置 JDK 8
    container_name: mcsm-daemon
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - MCSM_INSTANCES_BASE_PATH=/opt/mcsmanager/daemon/data/InstanceData
    ports:
      - "24444:24444"
    volumes:
      - ./daemon/data:/opt/mcsmanager/daemon/data
      - ./daemon/logs:/opt/mcsmanager/daemon/logs
      - /var/run/docker.sock:/var/run/docker.sock  # Docker 容器管理所需
    restart: unless-stopped
```

> 启动后请在 Web 面板中手动添加 Daemon 节点进行连接（Docker 环境下不会自动连接）。

### 自定义扩展示例

```yaml
services:
  mcsm-daemon:
    image: ghcr.io/snowmoonss/mcsm-daemon:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - DOCKER_MODS=linuxserver/mods:universal-cloudflared
    volumes:
      - ./daemon/data:/opt/mcsmanager/daemon/data
      - ./daemon/logs:/opt/mcsmanager/daemon/logs
      - /var/run/docker.sock:/var/run/docker.sock
      - ./custom-scripts:/custom-cont-init.d:ro    # 自定义启动脚本
      - ./custom-services:/custom-services.d:ro    # 自定义伴生服务
```

---

## 可用的 JDK 变体标签

| 标签 | JDK 版本 | 适用场景 |
|------|----------|----------|
| `latest` | 无 JDK | Minecraft 实例将以 Docker 容器的方式运行 |
| `latest-jdk25` | JDK 25 | Minecraft 26.1+ 及最新版本 |
| `latest-jdk21` | JDK 21 | Minecraft 1.20 - 1.21 |
| `latest-jdk17` | JDK 17 | Minecraft 1.17 - 1.20 |
| `latest-jdk11` | JDK 11 | Minecraft 1.8 - 1.17 |
| `latest-jdk8` | JDK 8 | Minecraft 1.16 及更早、Forge 旧版本 |

---

## 开发与构建

```bash
# Web 镜像
docker build -f web.dockerfile \
  --build-arg MCSM_VERSION=v10.16.1 \
  -t mcsm-web:local .

# Daemon 镜像（默认 JDK 21）
docker build -f daemon.dockerfile \
  --build-arg MCSM_VERSION=v10.16.1 \
  -t mcsm-daemon:local .

# Daemon 镜像（无 JDK）
docker build -f daemon.dockerfile \
  --build-arg MCSM_VERSION=v10.16.1 \
  --build-arg SKIP_JAVA=true \
  -t mcsm-daemon:local-nojdk .
```

---

## 许可证

本项目（Docker 构建文件与配置）基于 [GPL-3.0](LICENSE) 发布。

MCSManager 本体基于 [Apache License 2.0](https://github.com/MCSManager/MCSManager/blob/master/LICENSE)。

LinuxServer 基础镜像基于 [GPL-3.0](https://github.com/linuxserver/docker-baseimage-alpine/blob/main/LICENSE)。

---

## 致谢

- [MCSManager](https://github.com/MCSManager/MCSManager) — 优秀的游戏服务器管理面板
- [LinuxServer.io](https://linuxserver.io) — 业界领先的 Docker 基础镜像与运维实践
- [s6-overlay](https://github.com/just-containers/s6-overlay) — 为容器设计的轻量 init 系统
