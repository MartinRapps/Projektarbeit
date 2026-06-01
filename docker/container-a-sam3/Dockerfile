# Container A: SAM 3 Pre-processing
# Base image: CUDA/PyTorch runtime for SAM 3.1
FROM pytorch/pytorch:2.7.0-cuda12.6-cudnn9-devel

WORKDIR /app
ENV PYTHONUNBUFFERED=1
ARG SAM3_REF=9f22cb976fb6e38dad5bb34940fad852dd897d0e

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git ffmpeg libsm6 libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies and SAM 3
RUN pip install --no-cache-dir opencv-python pillow huggingface_hub einops torchvision setuptools cython numpy decord nvidia-pytriton
RUN pip install --no-cache-dir pycocotools
RUN git clone https://github.com/facebookresearch/sam3.git /opt/sam3 \
    && cd /opt/sam3 \
    && git checkout ${SAM3_REF} \
    && pip install --no-cache-dir -e .
