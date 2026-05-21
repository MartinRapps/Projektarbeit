# Container E: Post-processing (DGtal C++ & GDAL / CPU-only)
FROM ubuntu:22.04

# Install basic development and GIS tools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libdgtal-dev \
    libboost-all-dev \
    libeigen3-dev \
    gdal-bin \
    libgdal-dev \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Compile C++ DGtal app and setup Python script requirements
