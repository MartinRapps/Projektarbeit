# Container E: Post-processing (DGtal C++ & GDAL / CPU-only)
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install basic development and GIS tools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libboost-all-dev \
    libeigen3-dev \
    gdal-bin \
    libgdal-dev \
    python3-pip \
    libgmp-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Build and install DGtal from source
RUN git clone https://github.com/DGtal-team/DGtal.git /tmp/DGtal && \
    cd /tmp/DGtal && \
    mkdir build && cd build && \
    cmake .. -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/DGtal

WORKDIR /app
# Compile C++ DGtal app and setup Python script requirements
