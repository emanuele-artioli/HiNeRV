#!/bin/bash
# This script correctly installs the hinerv environment by separating Conda and Pip steps.

# Exit immediately if a command exits with a non-zero status.
set -e

ENV_NAME="hinerv"

echo "--- Starting HiNeRV Environment Setup ---"

echo ">>> Step 1: Creating Conda environment '$ENV_NAME' with Conda packages..."
conda env create -f environment.yml

# Source the main conda script to make 'conda activate' available in this script
source $(conda info --base)/etc/profile.d/conda.sh

echo ">>> Step 2: Activating environment to install Pip packages..."
conda activate $ENV_NAME

# Now that the environment is active, install pip packages with CUDA_HOME correctly set.
echo ">>> Step 3: Installing Pip packages from requirements.txt..."
CUDA_HOME=$CONDA_PREFIX pip install -r requirements.txt

echo ""
echo "--- Installation Complete! ---"
echo "To activate your new environment in a new terminal, run: conda activate $ENV_NAME"
