#!/usr/bin/env bash
# Train one curriculum stage on AgentDyn or AgentDojo.
# Usage: bash scripts/train_stage.sh <benchmark> <target-model> [attacker-init]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
export PYTHONPATH="${ROOT}:${PYTHONPATH:-}"

BENCHMARK=${1:-agentdyn}
TARGET_MODEL=${2:-gpt-5-nano}
ATTACKER_MODEL=${3:-Qwen/Qwen3-4B-Instruct-2507}
TARGET_PROVIDER=${TARGET_PROVIDER:-openai}
TARGET_API_KEY_ENV=${TARGET_API_KEY_ENV:-}
TARGET_BASE_URL=${TARGET_BASE_URL:-}
TARGET_MODEL_ID=${TARGET_MODEL_ID:-}
TARGET_MODEL_URL=${TARGET_MODEL_URL:-}
TARGET_MAX_TOKENS=${TARGET_MAX_TOKENS:-32768}
TARGET_DEFENSE=${TARGET_DEFENSE:-}
TRAIN_GPUS=${TRAIN_GPUS:-0,1,2,3}
TRAIN_SUITES=${TRAIN_SUITES:-}
OUTPUT_DIR=${OUTPUT_DIR:-checkpoints/${BENCHMARK}}
RUN_NAME=${RUN_NAME:-${BENCHMARK}_${TARGET_MODEL//\//_}}
NUM_TRAIN_EPOCHS=${NUM_TRAIN_EPOCHS:-10}
LEARNING_RATE=${LEARNING_RATE:-1.0e-5}
SAVE_STEPS=${SAVE_STEPS:-100}
SAVE_TOTAL_LIMIT=${SAVE_TOTAL_LIMIT:-2}
TRAIN_INJ=${TRAIN_INJ:-}
TRAIN_USER=${TRAIN_USER:-}
REPORT_TO=${REPORT_TO:-none}
DRY_RUN=${DRY_RUN:-0}

case "${BENCHMARK}" in
  agentdyn)
    CONFIG=configs/agentdyn.yaml
    TRAIN_SUITES=${TRAIN_SUITES:-github}
    ;;
  agentdojo)
    CONFIG=configs/agentdojo.yaml
    TRAIN_SUITES=${TRAIN_SUITES:-workspace}
    ;;
  *)
    echo "benchmark must be 'agentdyn' or 'agentdojo'" >&2
    exit 2
    ;;
esac

if [[ "${TARGET_PROVIDER}" == "vllm" || "${TARGET_MODEL}" == "local" ]]; then
  TARGET_PROVIDER=vllm
  TARGET_MODEL=local
  : "${TARGET_MODEL_ID:?TARGET_MODEL_ID is required for a local target}"
  : "${TARGET_MODEL_URL:?TARGET_MODEL_URL is required for a local target}"
else
  if [[ -z "${TARGET_API_KEY_ENV}" ]]; then
    case "${TARGET_PROVIDER}" in
      openai) TARGET_API_KEY_ENV=OPENAI_API_KEY ;;
      openrouter) TARGET_API_KEY_ENV=OPENROUTER_API_KEY ;;
      *)
        echo "Set TARGET_API_KEY_ENV for provider '${TARGET_PROVIDER}'." >&2
        exit 2
        ;;
    esac
  fi
  if [[ "${DRY_RUN}" != "1" && -z "${!TARGET_API_KEY_ENV:-}" ]]; then
    echo "${TARGET_API_KEY_ENV} is not set." >&2
    exit 2
  fi
fi

IFS=',' read -r -a GPU_LIST <<<"${TRAIN_GPUS}"
NUM_GPUS=${#GPU_LIST[@]}

ARGS=(
  -m train
  --benchmark "${BENCHMARK}"
  --config_file "${CONFIG}"
  --attacker_model_name_or_path "${ATTACKER_MODEL}"
  --target_model "${TARGET_MODEL}"
  --target_provider "${TARGET_PROVIDER}"
  --target_max_tokens "${TARGET_MAX_TOKENS}"
  --train_suites "${TRAIN_SUITES}"
  --output_dir "${OUTPUT_DIR}"
  --run_name "${RUN_NAME}"
  --num_train_epochs "${NUM_TRAIN_EPOCHS}"
  --learning_rate "${LEARNING_RATE}"
  --save_steps "${SAVE_STEPS}"
  --save_total_limit "${SAVE_TOTAL_LIMIT}"
  --report_to "${REPORT_TO}"
)
[[ -n "${TARGET_API_KEY_ENV}" ]] && ARGS+=(--target_api_key_env "${TARGET_API_KEY_ENV}")
[[ -n "${TARGET_BASE_URL}" ]] && ARGS+=(--target_base_url "${TARGET_BASE_URL}")
[[ -n "${TARGET_MODEL_ID}" ]] && ARGS+=(--target_model_id "${TARGET_MODEL_ID}")
[[ -n "${TARGET_MODEL_URL}" ]] && ARGS+=(--target_model_url "${TARGET_MODEL_URL}")
[[ -n "${TARGET_DEFENSE}" ]] && ARGS+=(--target_defense "${TARGET_DEFENSE}")
[[ -n "${TRAIN_INJ}" ]] && ARGS+=(--train_injection_tasks "${TRAIN_INJ}")
[[ -n "${TRAIN_USER}" ]] && ARGS+=(--train_user_tasks "${TRAIN_USER}")

if [[ "${NUM_GPUS}" -eq 1 ]]; then
  COMMAND=(python "${ARGS[@]}")
else
  COMMAND=(
    accelerate launch
    --config_file configs/accelerate.yaml
    --num_processes "${NUM_GPUS}"
    "${ARGS[@]}"
  )
fi

echo "Benchmark: ${BENCHMARK}"
echo "Target: ${TARGET_MODEL} (${TARGET_PROVIDER})"
echo "Attacker initialization: ${ATTACKER_MODEL}"
echo "Suites: ${TRAIN_SUITES}"
echo "Epochs: ${NUM_TRAIN_EPOCHS}"
echo "Output: ${OUTPUT_DIR}"

if [[ "${DRY_RUN}" == "1" ]]; then
  printf 'CUDA_VISIBLE_DEVICES=%q ' "${TRAIN_GPUS}"
  printf '%q ' "${COMMAND[@]}"
  printf '\n'
  exit 0
fi

CUDA_VISIBLE_DEVICES="${TRAIN_GPUS}" "${COMMAND[@]}"
