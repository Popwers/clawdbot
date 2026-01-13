# syntax=docker/dockerfile:1

FROM node:22-bookworm AS base

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG CLAWDBOT_DOCKER_APT_PACKAGES="bash ca-certificates chromium curl fonts-liberation fonts-noto-color-emoji gh git pandoc python3-pip jq novnc python3 socat websockify x11vnc xvfb ripgrep ffmpeg tmux tar xz-utils git"
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# --- Extra CLIs for skills (persist in image) ---
# Needs: curl, ca-certificates, tar, xz-utils, git, python3 (via CLAWDBOT_DOCKER_APT_PACKAGES)

ARG TARGETARCH
ARG GOGCLI_VERSION=0.6.0
ARG GO_VERSION=1.24.1
ARG WHISPER_CPP_VERSION=v1.8.2

# Node CLIs (via bun): bird, summarize, clawdhub, mcporter, oracle
RUN bun add -g \
  @steipete/bird \
  @steipete/summarize \
  clawdhub \
  mcporter \
  @steipete/oracle

# OpenCode (terminal AI coding agent)
ARG CLAWDBOT_USE_OPENCODE="false"
RUN set -eux; \
  if [ "$CLAWDBOT_USE_OPENCODE" = "true" ]; then \
    curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; \
    install -m 0755 /root/.opencode/bin/opencode /usr/local/bin/opencode; \
    rm -rf /root/.opencode; \
  fi

# gog (gogcli) binary from GitHub releases
RUN set -eux; \
  arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
  case "$arch" in \
    amd64|arm64) ;; \
    *) echo "unsupported arch: $arch" && exit 1 ;; \
  esac; \
  curl -fsSL -o /tmp/gog.tgz "https://github.com/steipete/gogcli/releases/download/v${GOGCLI_VERSION}/gogcli_${GOGCLI_VERSION}_linux_${arch}.tar.gz"; \
  tar -C /tmp -xzf /tmp/gog.tgz; \
  install -m 0755 /tmp/gog /usr/local/bin/gog; \
  rm -f /tmp/gog.tgz

# uv + nano-pdf
RUN curl -fsSL https://astral.sh/uv/install.sh | sh && \
  /root/.local/bin/uv tool install nano-pdf && \
  ln -sf /root/.local/bin/uv /usr/local/bin/uv && \
  ln -sf /root/.local/bin/nano-pdf /usr/local/bin/nano-pdf

# ---- Builder stages (toolchains kept out of final image) ----

FROM base AS blogwatcher-builder
RUN set -eux; \
  arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
  curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz"; \
  tar -C /usr/local -xzf /tmp/go.tgz; \
  rm -f /tmp/go.tgz
ENV PATH="/usr/local/go/bin:${PATH}"
RUN go install github.com/Hyaxia/blogwatcher/cmd/blogwatcher@latest

FROM base AS whispercpp-builder
RUN set -eux; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config; \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
RUN git clone --depth 1 --branch "${WHISPER_CPP_VERSION}" https://github.com/ggerganov/whisper.cpp.git /tmp/whispercpp
RUN cmake -S /tmp/whispercpp -B /tmp/whispercpp/build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build /tmp/whispercpp/build -j

# ---- Final image ----

FROM base AS final

# Install blogwatcher (built in builder stage)
COPY --from=blogwatcher-builder /root/go/bin/blogwatcher /usr/local/bin/blogwatcher

# Install whisper.cpp CLI + shared libraries
COPY --from=whispercpp-builder /tmp/whispercpp/build/bin/whisper-cli /usr/local/bin/whisper-cli
# Runtime deps (built as shared libs by default)
COPY --from=whispercpp-builder /tmp/whispercpp/build/src/libwhisper.so* /usr/local/lib/
COPY --from=whispercpp-builder /tmp/whispercpp/build/ggml/src/libggml.so* /usr/local/lib/
RUN ldconfig

# whisper.cpp model cache (mounted as a volume in docker-compose)
ENV XDG_CACHE_HOME=/opt/whisper-cache
RUN mkdir -p /opt/whisper-cache && chmod 755 /opt/whisper-cache

COPY scripts/docker/whisper.sh /usr/local/bin/whisper
RUN chmod +x /usr/local/bin/whisper

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

# OpenCode default config (from Popwers/dotfiles)
# Note: /home/node/.config is often a persistent mount (Coolify), so we also stage
# a default config in the image and sync it at container start (entrypoint).
RUN set -eux; \
  if [ "$CLAWDBOT_USE_OPENCODE" = "true" ]; then \
    git clone --depth 1 https://github.com/Popwers/dotfiles.git /tmp/dotfiles; \
    rm -rf /opt/default-opencode; \
    cp -a /tmp/dotfiles/opencode /opt/default-opencode; \
    rm -rf /tmp/dotfiles; \
    chmod -R a+rX /opt/default-opencode; \
  fi

COPY scripts/docker/entrypoint.sh /usr/local/bin/clawdbot-entrypoint
ENTRYPOINT ["/usr/local/bin/clawdbot-entrypoint"]

CMD ["node", "dist/index.js"]
