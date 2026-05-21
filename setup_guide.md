# Step-by-Step Infrastructure Setup Guide

This guide describes the sequence and exact commands to install Docker, GPU drivers, and the NVIDIA Container Toolkit on your GPU machine (supporting both native **Ubuntu 22.04** and **Windows 11 with WSL2**).

---

## Overview of Steps and Privileges

| Step | Task | Target System | Admin Rights Required? |
| :--- | :--- | :--- | :--- |
| **1** | NVIDIA GPU Drivers | Host (Windows or Ubuntu) | **YES** (`sudo` / Windows Admin) |
| **2** | WSL2 Setup | Host (Windows only) | **YES** (Windows Admin) |
| **3** | Docker Installation | Host (Windows or Ubuntu) | **YES** (`sudo` / Windows Admin) |
| **4** | NVIDIA Container Toolkit | Host (Windows WSL2 or Ubuntu) | **YES** (`sudo` / Windows Admin) |
| **5** | Verify GPU in Docker | Host (Windows WSL2 or Ubuntu) | No (if user is in `docker` group) |
| **6** | Pipeline Initialization | Host (Windows WSL2 or Ubuntu) | No |

---

## Detailed Step-by-Step Guide

---

### Step 1: NVIDIA GPU Host Driver
Before Docker or WSL2 can access the GPU, the base driver must be installed on the host OS.

#### A. If using Windows 10/11 Host
1. **[ADMIN RIGHTS REQUIRED]** Download the latest NVIDIA GeForce or NVIDIA RTX Enterprise driver from [NVIDIA Driver Downloads](https://www.nvidia.com/download/index.aspx).
2. Install the driver using the installer. Select the default "NVIDIA Graphics Driver and GeForce Experience" option.
3. Restart your PC.

#### B. If using Native Ubuntu 22.04 Host
1. **[ADMIN RIGHTS REQUIRED]** Update package lists:
   ```bash
   sudo apt-get update
   ```
2. **[ADMIN RIGHTS REQUIRED]** Install the recommended NVIDIA driver:
   ```bash
   sudo ubuntu-drivers install
   ```
   *(Alternatively, install a specific version like `sudo apt-get install nvidia-driver-535`).*
3. **[ADMIN RIGHTS REQUIRED]** Reboot the system:
   ```bash
   sudo reboot
   ```

---

### Step 2: Windows Subsystem for Linux (WSL2) — *Windows Host Only*
If you are running on Windows, you must configure WSL2 to run the Linux-based Docker containers.

1. **[ADMIN RIGHTS REQUIRED]** Open PowerShell or CMD as Administrator and run:
   ```powershell
   wsl --install -d Ubuntu-22.04
   ```
2. Restart your computer if prompted.
3. Upon restart, a terminal will open. Set your Linux username and password.
4. **[ADMIN RIGHTS REQUIRED]** Ensure WSL2 is set to version 2 by default:
   ```powershell
   wsl --set-default-version 2
   ```

---

### Step 3: Docker Installation

#### A. If using Windows Host (with WSL2)
1. Download **Docker Desktop** from the [Docker Website](https://www.docker.com/products/docker-desktop/).
2. **[ADMIN RIGHTS REQUIRED]** Run the installer. Ensure the checkbox **"Use the WSL 2 based engine"** is checked.
3. Restart your computer.
4. Open Docker Desktop, go to **Settings > Resources > WSL Integration**, and enable integration for your Ubuntu-22.04 distribution.

#### B. If using Native Ubuntu 22.04 Host
1. **[ADMIN RIGHTS REQUIRED]** Uninstall any old Docker versions:
   ```bash
   sudo apt-get remove docker docker-engine docker.io containerd runc
   ```
2. **[ADMIN RIGHTS REQUIRED]** Install Docker using the official repository:
   ```bash
   sudo apt-get update
   sudo apt-get install ca-certificates curl gnupg
   sudo install -m 0755 -d /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   sudo chmod a+r /etc/apt/keyrings/docker.gpg

   echo \
     "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
     "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
     sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

   sudo apt-get update
   sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   ```
3. **[ADMIN RIGHTS REQUIRED]** Manage Docker as a non-root user (avoids having to type `sudo` before every docker command):
   ```bash
   sudo groupadd docker
   sudo usermod -aG docker $USER
   ```
   *Note: Log out and log back in (or run `newgrp docker`) for these changes to take effect.*

---

### Step 4: NVIDIA Container Toolkit
This toolkit enables Docker containers to bind-mount the host GPU and run CUDA libraries inside containers.

> [!NOTE]
> - **On Windows:** If you use Docker Desktop with WSL2, the NVIDIA Container Toolkit is **automatically included and pre-configured**. You can skip Step 4 and proceed directly to Step 5.
> - **On native Ubuntu:** You **must** install the toolkit manually using the steps below.

#### Install on native Ubuntu 22.04:
1. **[ADMIN RIGHTS REQUIRED]** Configure the package repository:
   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
     && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
       sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
       sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   ```
2. **[ADMIN RIGHTS REQUIRED]** Install the toolkit:
   ```bash
   sudo apt-get update
   sudo apt-get install -y nvidia-container-toolkit
   ```
3. **[ADMIN RIGHTS REQUIRED]** Configure Docker daemon to use the NVIDIA runtime:
   ```bash
   sudo nvidia-container-toolkit signup
   sudo systemctl restart docker
   ```

---

### Step 5: Verify GPU Access in Docker
Verify that your Docker containers can access the host GPU. Run this command on your target system (inside your WSL2 terminal or Ubuntu terminal):

```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

#### Expected Output:
If successful, you will see the standard NVIDIA System Management Interface table displaying your GPU model (e.g., RTX 3090, RTX 4090) and VRAM details.

---

### Step 6: Clone and Initialize the Pipeline
No admin rights are needed for this step.

1. Clone your Git repository to the target machine.
2. Initialize the local data folders:
   ```bash
   mkdir -p data/01_raw data/02_frames data/03_masks data/04_sfm data/05_3dgs data/06_mesh data/07_centerline data/08_gis data/09_evaluation
   ```
3. Place your `video.mp4` and coordinate files in `data/01_raw/`.
4. Run the pipeline:
   ```bash
   chmod +x run_pipeline.sh
   ./run_pipeline.sh
   ```
