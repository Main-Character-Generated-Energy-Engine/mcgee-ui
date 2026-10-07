# Flutter's official Linux SDK archive is x64; Docker emulates it on ARM hosts.
FROM --platform=linux/amd64 node:24.19.0-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git openssh-client unzip xz-utils libglu1-mesa procps sudo \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'node ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

ARG FLUTTER_VERSION=3.47.6
ARG FLUTTER_SHA256=f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675
RUN curl --fail --location --retry 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    --output /tmp/flutter.tar.xz \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum --check \
    && tar -xJf /tmp/flutter.tar.xz -C /home/node \
    && rm /tmp/flutter.tar.xz \
    && chown -R node:node /home/node/flutter

ENV PATH="/home/node/flutter/bin:${PATH}"
USER node
RUN flutter config --enable-web --no-analytics \
    && flutter precache --web \
    && flutter --version

USER root
ARG NETLIFY_CLI_VERSION=27.11.2
RUN npm install --global "netlify-cli@${NETLIFY_CLI_VERSION}" \
    && npm cache clean --force
USER node
