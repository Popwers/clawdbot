FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
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

# Node CLIs (via bun): bird, summarize, clawdhub, mcporter, oracle
RUN bun add -g \
  @steipete/bird \
  @steipete/summarize \
  clawdhub \
  mcporter \
  @steipete/oracle

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

# Go toolchain (for blogwatcher) + install blogwatcher
RUN set -eux; \
  arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
  curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz"; \
  rm -rf /usr/local/go; \
  tar -C /usr/local -xzf /tmp/go.tgz; \
  rm -f /tmp/go.tgz
ENV PATH="/usr/local/go/bin:${PATH}"
RUN go install github.com/Hyaxia/blogwatcher/cmd/blogwatcher@latest && \
  install -m 0755 /root/go/bin/blogwatcher /usr/local/bin/blogwatcher

# uv + nano-pdf
RUN curl -fsSL https://astral.sh/uv/install.sh | sh && \
  /root/.local/bin/uv tool install nano-pdf && \
  ln -sf /root/.local/bin/uv /usr/local/bin/uv && \
  ln -sf /root/.local/bin/nano-pdf /usr/local/bin/nano-pdf

# Local Whisper (speech-to-text, no API key)
# Note: this pulls a CPU PyTorch wheel + Whisper; models download at runtime into ~/.cache/whisper.
# Requires ffmpeg at runtime (install via CLAWDBOT_DOCKER_APT_PACKAGES or apt).
RUN set -eux; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-pip ffmpeg; \
  rm -rf /var/lib/apt/lists/*; \
  python3 -m pip install --no-cache-dir --break-system-packages -U pip setuptools wheel; \
  python3 -m pip install --no-cache-dir --break-system-packages --index-url https://download.pytorch.org/whl/cpu torch; \
  python3 -m pip install --no-cache-dir --break-system-packages openai-whisper; \
  whisper --help >/dev/null

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

CMD ["node", "dist/index.js"]
