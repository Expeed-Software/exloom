FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash git python3 python-is-python3 python3-yaml jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*
