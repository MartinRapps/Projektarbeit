# Container D: SuGaR (Meshing & Regularization)
# Base Image with CUDA 11.8 & GCC
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

# Avoid interactive prompts and set build variables for C++ / CUDA extensions
ENV DEBIAN_FRONTEND=noninteractive
ENV FORCE_CUDA=1
ENV TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh
ENV PATH=/opt/conda/bin:$PATH

# Accept Anaconda Terms of Service
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Create Conda Environment and configure shell
RUN conda create --name sugar -y python=3.9

# Install PyTorch, CUDA, and PyTorch3D inside 'sugar' environment
RUN conda install -n sugar -y pytorch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 pytorch-cuda=11.8 -c pytorch -c nvidia && \
    conda install -n sugar -y -c fvcore -c iopath -c conda-forge fvcore iopath && \
    conda install -n sugar -y pytorch3d==0.7.4 -c pytorch3d -c conda-forge && \
    conda install -n sugar -y -c plotly plotly && \
    conda install -n sugar -y -c conda-forge rich plyfile==0.8.1

# Enable 'sugar' environment globally as default command path
ENV PATH=/opt/conda/envs/sugar/bin:$PATH

# Clone SuGaR repository and compile submodules
WORKDIR /opt/sugar
RUN git clone https://github.com/Anttwo/SuGaR.git .

RUN pip install open3d PyMCubes && \
    cd /opt/sugar/gaussian_splatting/submodules/diff-gaussian-rasterization/ && \
    pip install -e . --no-build-isolation && \
    cd /opt/sugar/gaussian_splatting/submodules/simple-knn/ && \
    pip install -e . --no-build-isolation
