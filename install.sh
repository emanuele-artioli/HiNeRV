#!/bin/bash
# This script automates the robust two-step installation of the hinerv environment.

# Exit immediately if a command exits with a non-zero status.
set -e

# Define the environment name from the YAML file
ENV_NAME=$(grep 'name:' environment.yml | cut -d ' ' -f 2)

echo "--- Starting Streamlined HiNeRV Environment Setup for '$ENV_NAME' ---"

# Step 1: Create the Conda environment.
# This may fail if a broken environment with the same name exists.
# We attempt to create, and if that fails, we try to update.
echo ">>> Step 1: Creating/Updating Conda environment from environment.yml..."
if ! conda env create -f environment.yml; then
    echo "Initial 'conda env create' failed. This might be because the environment already exists."
    echo "Attempting to update the existing environment..."
    conda env update -f environment.yml --prune
fi

# Step 2: Activate the environment and correctly install pip dependencies.
echo ">>> Step 2: Activating '$ENV_NAME' and installing pip packages..."

# Source the main conda script to make 'conda activate' available in this script
source $(conda info --base)/etc/profile.d/conda.sh
conda activate $ENV_NAME

# Install pip packages with CUDA_HOME correctly set. This is the crucial fix.
# We parse the requirements from the environment.yml file to ensure consistency.
echo "Installing pip dependencies with CUDA_HOME set to $CONDA_PREFIX..."
CUDA_HOME=$CONDA_PREFIX pip install --no-deps -r <(grep -A 100 ".*- pip:" environment.yml | tail -n +2 | sed 's/    - //')


echo ""
echo "--- Installation Complete! ---"
echo "To activate your new environment in a new terminal, run: conda activate $ENV_NAME"
