#!/bin/bash
# A script to automate the preprocessing and encoding of a video with HiNeRV.

# --- Configuration ---
# Exit on any error
set -e

# Default parameters
MODEL_SIZE="S" # Can be 'S' for small or 'L' for large
OUTPUT_BASE_DIR="hinerv_output"
BATCH_SIZE=144

# --- Helper Functions ---
function print_usage() {
    echo "Usage: $0 -i <input_path> [-m <S|L>] [-o <output_dir>] [-b <batch_size>]"
    echo "  -i <input_path>: Path to the input video file OR a directory of PNG frames."
    echo "  -m <S|L>:          Model size. 'S' (small) or 'L' (large). Default: S"
    echo "  -o <output_dir>:   Base directory to save results. Default: hinerv_output"
    echo "  -b <batch_size>:   Training batch size. Default: 144"
    exit 1
}

# --- Argument Parsing ---
while getopts "i:m:o:b:" opt; do
  case ${opt} in
    i )
      INPUT_PATH=$OPTARG
      ;;
    m )
      MODEL_SIZE=$OPTARG
      ;;
    o )
      OUTPUT_BASE_DIR=$OPTARG
      ;;
    b )
      BATCH_SIZE=$OPTARG
      ;;
    \? )
      print_usage
      ;;
  esac
done

if [ -z "${INPUT_PATH}" ]; then
    echo "Error: Input path is mandatory."
    print_usage
fi

# --- Main Logic ---
echo "--- Starting HiNeRV Encoding Process ---"

# Convert to absolute path
INPUT_PATH=$(realpath "${INPUT_PATH}")
OUTPUT_BASE_DIR=$(realpath "${OUTPUT_BASE_DIR}")
VIDEO_NAME=$(basename "${INPUT_PATH%.*}")
PROJECT_DIR="${OUTPUT_BASE_DIR}/${VIDEO_NAME}"

# Create project directory
mkdir -p "${PROJECT_DIR}"
echo "Project directory created at: ${PROJECT_DIR}"

# --- Step 1: Preprocessing (Get Frames) ---
if [ -d "${INPUT_PATH}" ]; then
    echo "Input is a directory. Assuming it contains PNG frames."
    FRAMES_DIR="${INPUT_PATH}"
else
    echo "Input is a video file. Converting to PNG frames..."
    FRAMES_DIR="${PROJECT_DIR}/frames"
    mkdir -p "${FRAMES_DIR}"
    ffmpeg -i "${INPUT_PATH}" -y "${FRAMES_DIR}/%04d.png"
    echo "Frames extracted to: ${FRAMES_DIR}"
fi

# --- Step 2: Detect Resolution and Frame Count ---
FIRST_FRAME=$(find "${FRAMES_DIR}" -type f -name "*.png" | head -n 1)
if [ -z "${FIRST_FRAME}" ]; then
    echo "Error: Could not find any frames in ${FRAMES_DIR}."
    exit 1
fi
RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "${FIRST_FRAME}")
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)
NUM_FRAMES=$(find "${FRAMES_DIR}" -type f -name "*.png" | wc -l)

echo "Detected video metadata:"
echo "  - Frame Count: ${NUM_FRAMES}"
echo "  - Resolution:  ${WIDTH}x${HEIGHT}"

# --- Step 3: Find Configuration Files ---
LOWER_MODEL_SIZE=$(echo "$MODEL_SIZE" | tr '[:upper:]' '[:lower:]')
TRAIN_CFG_FILE="cfgs/train/hinerv_${WIDTH}x${HEIGHT}.txt"
MODEL_CFG_FILE="cfgs/models/uvg-hinerv-${LOWER_MODEL_SIZE}_${WIDTH}x${HEIGHT}.txt"

if [ ! -f "$TRAIN_CFG_FILE" ] || [ ! -f "$MODEL_CFG_FILE" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ERROR !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Could not find matching config files for resolution ${WIDTH}x${HEIGHT} and model size ${MODEL_SIZE}."
    echo "Looked for:"
    echo "  - ${TRAIN_CFG_FILE}"
    echo "  - ${MODEL_CFG_FILE}"
    echo "Please create these config files inside the 'cfgs' directory by copying"
    echo "and adapting an existing configuration for a different resolution."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi
echo "Found matching config files:"
echo "  - Training: ${TRAIN_CFG_FILE}"
echo "  - Model:    ${MODEL_CFG_FILE}"

# --- Step 4: Run HiNeRV Training (Encoding) ---
DATASET_DIR=$(dirname "${FRAMES_DIR}")
DATASET_NAME=$(basename "${FRAMES_DIR}")
HINERV_OUTPUT_DIR="${PROJECT_DIR}/model_output"

echo "Starting HiNeRV training... this may take a while."

# MODIFICATION: Removed '--dynamo_backend=inductor' to prevent the cuDNN error.
# MODIFICATION: Added video metadata arguments to be saved in args.yaml.
accelerate launch --mixed_precision="no" hinerv_main.py \
  --dataset "${DATASET_DIR}" \
  --dataset-name "${DATASET_NAME}" \
  --output "${HINERV_OUTPUT_DIR}" \
  $(cat "${TRAIN_CFG_FILE}") \
  $(cat "${MODEL_CFG_FILE}") \
  --batch-size ${BATCH_SIZE} \
  --eval-batch-size 1 \
  --grad-accum 1 \
  --log-eval false \
  --seed 0 \
  --video-num-frames ${NUM_FRAMES} \
  --video-height ${HEIGHT} \
  --video-width ${WIDTH}

echo "--- Encoding Complete! ---"
echo "The trained model and logs are saved in: ${HINERV_OUTPUT_DIR}"