# Container B: COLMAP (Structure from Motion)
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

# Vermeide interaktive Prompts während apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Installiere COLMAP via apt
RUN apt-get update && apt-get install -y colmap && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Add your SfM setup commands here
