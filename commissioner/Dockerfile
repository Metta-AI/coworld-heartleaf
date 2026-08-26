# Heartleaf commissioner: the current coworld-tools ruleset_strategy
# commissioner with Heartleaf's YAML baked in (shuffled_window seating,
# 30-minute rounds, champion-only competition). Built self-contained from
# a pinned coworld-tools commit so `docker compose build --pull` works
# with no local base image. Do NOT base this on the old
# ghcr.io/metta-ai/commissioners-default digest (75d77cf9, June): that
# image only accepts baseline_window / rolling_window, so shuffled_window
# would fail config parse, and it never stamps a per-episode seed.
FROM python:3.13-slim

ARG COWORLD_TOOLS_REF=00617660423c05cbc48b0f8aa326f4c9419eb364

ENV COMMISSIONER_KEY=config_driven \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git clone https://github.com/Metta-AI/coworld-tools /tmp/coworld-tools \
    && git -C /tmp/coworld-tools checkout "${COWORLD_TOOLS_REF}" \
    && cp -r /tmp/coworld-tools/commissioners /app \
    && rm -rf /tmp/coworld-tools

WORKDIR /app
RUN pip install --no-cache-dir .

COPY commissioner/heartleaf.yaml /heartleaf.yaml
ENV RULESET_STRATEGY_CONFIG_PATH=/heartleaf.yaml

EXPOSE 8080
CMD ["uvicorn", "commissioners.common.app:app", "--host", "0.0.0.0", "--port", "8080"]
