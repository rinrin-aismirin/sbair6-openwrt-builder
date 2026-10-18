# Build environment of the Air 6 kit on Ubuntu 22.04: OpenWrt build dependencies, Python 3.10 for the MTK signing
# tool (its pyc files are compiled for 3.10), openssl and squashfs-tools for the image checks.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang flex bison g++ gawk gcc-multilib gettext git libncurses-dev libssl-dev \
      python3 python3-distutils python3-setuptools python3-dev rsync unzip zlib1g-dev file wget curl swig jq \
      xsltproc libelf-dev ca-certificates time zstd xz-utils bzip2 patch perl diffutils less \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1000 -s /bin/bash build
# Image checks (scripts/check_image.sh): openssl for the signature check, squashfs-tools for the rootfs listing.
RUN apt-get update && apt-get install -y --no-install-recommends openssl squashfs-tools \
 && rm -rf /var/lib/apt/lists/*
USER build
WORKDIR /home/build
