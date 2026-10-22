FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      clang \
      cmake \
      curl \
      git \
      libgtk-3-dev \
      liblzma-dev \
      libsecret-1-dev \
      libsqlite3-dev \
      ninja-build \
      pkg-config \
      unzip \
      xz-utils \
      zip \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.44.7

RUN git init /opt/flutter \
    && git -C /opt/flutter remote add origin https://github.com/flutter/flutter.git \
    && git -C /opt/flutter fetch --depth 1 origin "refs/tags/${FLUTTER_VERSION}:refs/tags/${FLUTTER_VERSION}" \
    && git -C /opt/flutter checkout --detach "${FLUTTER_VERSION}" \
    && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}" \
    PUB_CACHE=/root/.pub-cache

RUN flutter config --enable-linux-desktop \
    && flutter precache --linux \
    && flutter --version

WORKDIR /workspace/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get --enforce-lockfile

COPY app/ ./
RUN flutter pub get --enforce-lockfile \
    && flutter build linux --release --no-pub

FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      dbus-x11 \
      fluxbox \
      libegl-mesa0 \
      libegl1 \
      libgl1 \
      libgl1-mesa-dri \
      libgles2 \
      libgtk-3-0t64 \
      liblzma5 \
      libsecret-1-0 \
      libsqlite3-0 \
      novnc \
      websockify \
      x11vnc \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

ENV DISPLAY=:99 \
    HOME=/data \
    LIBGL_ALWAYS_SOFTWARE=1 \
    XDG_CONFIG_HOME=/data/.config \
    XDG_DATA_HOME=/data/.local/share

COPY --from=build /workspace/app/build/linux/x64/release/bundle /opt/wallet-aps
COPY docker/web/index.html /usr/share/novnc/index.html
COPY docker/web/start-web.sh /usr/local/bin/start-wallet-aps-web

RUN chmod +x /usr/local/bin/start-wallet-aps-web \
    && mkdir -p /data

EXPOSE 80

CMD ["/usr/local/bin/start-wallet-aps-web"]
