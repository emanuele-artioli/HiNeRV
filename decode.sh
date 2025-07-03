#!/bin/bash
# A script to automate the decoding of a video with HiNeRV by using hinerv_main.py.

# --- Configuration ---
# Exit on any error
set -e

# --- Helper Functions ---
function print_usage() {
    echo "Usage: $0 -i <model_dir> -q <quant_level> -o <output_dir> -f <frames_dir>"
    echo "  -i <model_dir>:  Path to the specific trained model directory (with timestamp)."
    echo "                   (e.g., hinerv_output/Jockey/model_output/Jockey-HiNeRV-2025...)"
    echo "  -q <quant_level>: Quantization level to decode (e.g., 8)."
    echo "  -o <output_dir>:  Directory to save the decoded PNG frames."
    echo "  -f <frames_dir>:  Path to the directory containing the original PNG frames."
    exit 1
}

# --- Argument Parsing ---
while getopts "i:q:o:f:" opt; do
  case ${opt} in
    i )
      MODEL_DIR=$OPTARG
      ;;
    q )
      QUANT_LEVEL=$OPTARG
      ;;
    o )
      OUTPUT_DIR=$OPTARG
      ;;
    f )
      FRAMES_DIR=$OPTARG
      ;;
    \? )
      print_usage
      ;;
  esac
done

if [ -z "${MODEL_DIR}" ] || [ -z "${QUANT_LEVEL}" ] || [ -z "${OUTPUT_DIR}" ] || [ -z "${FRAMES_DIR}" ]; then
    echo "Error: All arguments (-i, -q, -o, -f) are mandatory."
    print_usage
fi

# --- Main Logic ---
echo "--- Starting HiNeRV Decoding Process ---"

# --- Step 1: Set Dataset Path from Parameter ---
# The main script requires the original dataset path to initialize its DataLoader.
if [ ! -d "${FRAMES_DIR}" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ERROR !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "The provided frames directory does not exist: ${FRAMES_DIR}"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi
echo "Using frames for metadata from: ${FRAMES_DIR}"

DATASET_DIR=$(dirname "${FRAMES_DIR}")
DATASET_NAME=$(basename "${FRAMES_DIR}")

# --- Step 2: Run HiNeRV Decoding via hinerv_main.py ---
# We use hinerv_main.py with --eval-only and --log-eval true.
# This ensures the model state is identical to training.
# The --output flag tells hinerv_main where to save the decoded frames.
echo "Starting frame generation... this may take a while."
mkdir -p "${OUTPUT_DIR}"

# We need to pass all the original arguments from the config files.
# The `args.yaml` inside the model directory contains the original input size and channel count.
WIDTH=$(grep 'video_width' "${MODEL_DIR}/args.yaml" | awk '{print $2}')
HEIGHT=$(grep 'video_height' "${MODEL_DIR}/args.yaml" | awk '{print $2}')

# MODIFICATION: Robustly determine model size based on channel count from args.yaml
CHANNELS=$(grep 'channels:' "${MODEL_DIR}/args.yaml" | awk '{print $2}')
MODEL_SIZE_CHAR=""
if [ "$CHANNELS" -eq 280 ]; then
    MODEL_SIZE_CHAR="s"
# This value may need to be adjusted if you create custom Large models.
elif [ "$CHANNELS" -eq 560 ]; then
    MODEL_SIZE_CHAR="l"
else
    echo "Error: Could not determine model size from channels value: ${CHANNELS}"
    exit 1
fi
echo "Determined model size: '${MODEL_SIZE_CHAR}' from channel count: ${CHANNELS}"

TRAIN_CFG_FILE="cfgs/train/hinerv_${WIDTH}x${HEIGHT}.txt"
MODEL_CFG_FILE="cfgs/models/uvg-hinerv-${MODEL_SIZE_CHAR}_${WIDTH}x${HEIGHT}.txt"

if [ ! -f "$TRAIN_CFG_FILE" ] || [ ! -f "$MODEL_CFG_FILE" ]; then
    echo "Error: Could not find config files for resolution ${WIDTH}x${HEIGHT} and model size '${MODEL_SIZE_CHAR}'."
    exit 1
fi

accelerate launch --mixed_precision="no" hinerv_main.py \
  --dataset "${DATASET_DIR}" \
  --dataset-name "${DATASET_NAME}" \
  --output "${OUTPUT_DIR}" \
  $(cat "${TRAIN_CFG_FILE}") \
  $(cat "${MODEL_CFG_FILE}") \
  --eval-only \
  --log-eval true \
  --bitstream "${MODEL_DIR}" \
  --bitstream-q ${QUANT_LEVEL}

echo "--- Decoding Complete! ---"
echo "The decoded frames are saved in the 'eval_output' subdirectory of: ${OUTPUT_DIR}"