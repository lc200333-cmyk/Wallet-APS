FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/root/.pub-cache \
    GRADLE_USER_HOME=/root/.gradle \
    PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
    ninja-build \
    nodejs \
    npm \
    openjdk-17-jdk \
    pkg-config \
    unzip \
    xz-utils \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
  && git config --global --add safe.directory "$FLUTTER_HOME" \
  && flutter config --no-analytics

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
  && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" -o /tmp/android-commandline-tools.zip \
  && unzip -q /tmp/android-commandline-tools.zip -d /tmp/android-commandline-tools \
  && mv /tmp/android-commandline-tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
  && rm -rf /tmp/android-commandline-tools /tmp/android-commandline-tools.zip \
  && yes | sdkmanager --licenses >/dev/null \
  && sdkmanager \
    "platform-tools" \
    "platforms;android-35" \
    "platforms;android-36" \
    "build-tools;36.0.0" \
    "ndk;28.2.13676358" \
    "cmake;3.22.1" \
  && flutter config --android-sdk "$ANDROID_HOME" \
  && yes | flutter doctor --android-licenses >/dev/null

RUN flutter precache --linux --android \
  && flutter doctor -v

WORKDIR /workspace

CMD ["bash"]
