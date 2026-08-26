# Build Docker.
FROM debian:bookworm-slim AS build

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git && \
  rm -rf /var/lib/apt/lists/*

RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    curl -fsSL \
      -o /usr/local/bin/nimby \
https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-X64; \
  elif [ "$(dpkg --print-architecture)" = "arm64" ]; then \
    curl -fsSL \
      -o /usr/local/bin/nimby \
https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-ARM64; \
  else \
    echo "unsupported arch: $(dpkg --print-architecture)" && exit 1; \
  fi && \
  chmod +x /usr/local/bin/nimby && \
  nimby use 2.2.4

ENV PATH="/root/.nimby/nim/bin:$PATH"

WORKDIR /workspace/heartleaf
COPY nimby.lock .
RUN nimby sync nimby.lock -g

COPY . .
RUN nimby sync nimby.lock -g

ARG NimFlags="-d:release -d:useMalloc --opt:speed --stackTrace:on"
RUN nim c \
  $NimFlags \
  --nimcache:/tmp/heartleaf-soul_player-nimcache \
  --out:soul_player \
  players/soul_player/soul_player.nim

# Run Docker. The player only uploads its soul file and keeps the socket
# alive; the game plays the gnome.
FROM debian:bookworm-slim

RUN apt-get update && \
  apt-get install -y --no-install-recommends ca-certificates && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/heartleaf
COPY --from=build /workspace/heartleaf/soul_player /bin/soul_player
COPY --from=build /workspace/heartleaf/players/poet_villager/soul.md /soul.md
ENV HEARTLEAF_SOUL_PATH=/soul.md

CMD ["/bin/soul_player"]
