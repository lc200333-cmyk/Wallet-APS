FROM mirror.gcr.io/library/ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

ENV FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/root/.pub-cache \
    PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    clang \
    cmake \
    curl \
    dpkg-dev \
    fakeroot \
    file \
    git \
    libgtk-3-dev \
    liblzma-dev \
    libglu1-mesa \
    libwebp-dev \
    ninja-build \
    pkg-config \
    unzip \
    xz-utils \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
  && git config --global --add safe.directory "$FLUTTER_HOME" \
  && flutter config --no-analytics \
  && flutter config --enable-linux-desktop \
  && flutter precache --linux \
  && flutter doctor -v

WORKDIR /workspace

CMD ["bash"]
