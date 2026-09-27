#!/usr/bin/env bash
# One training entry point for every benchmark.
# Usage: bash scripts/train.sh <benchmark> <target> [train_gpus] [train.py overrides...]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
export PYTHONPATH="${ROOT}/..:${ROOT}:${PYTHONPATH:-}"

BENCHMARK=${1:?Usage: bash scripts/train.sh <piarena|injecagent|agentdojo|agentdyn|ipi_arena_os> <target> [train_gpus] [overrides...]}
TARGET=${2:?Pass a target model or PIArena defense}
if [[ "${3:-}" == --* ]]; then
  TRAIN_GPUS=${TRAIN_GPUS:-}
  EXTRA_ARGS=("${@:3}")
else
  TRAIN_GPUS=${3:-${TRAIN_GPUS:-}}
  EXTRA_ARGS=("${@:4}")
fi
DRY_RUN=${DRY_RUN:-0}
ATTACKER_MODEL=${ATTACKER_MODEL:-Qwen/Qwen3-4B-Instruct-2507}
TARGET_GPU=${TARGET_GPU:-0}
TARGET_PORT=${TARGET_PORT:-8010}
TARGET_URL=${TARGET_URL:-}
TARGET_MODEL_ID=${TARGET_MODEL_ID:-}
TARGET_PROVIDER=${TARGET_PROVIDER:-}
TARGET_API_KEY_ENV=${TARGET_API_KEY_ENV:-}
TARGET_BASE_URL=${TARGET_BASE_URL:-}
TARGET_MAX_TOKENS=${TARGET_MAX_TOKENS:-32768}
VLLM_PYTHON=${VLLM_PYTHON:-python}
SERVER_PIDS=()

print_command() { printf '%q ' "$@"; printf '\n'; }
cleanup() {
  for pid in "${SERVER_PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT

resolve_api_target() {
  case "${TARGET}" in
    gpt4o-mini) TARGET_MODEL=gpt-4o-mini-2024-07-18 ;;
    gpt4o) TARGET_MODEL=gpt-4o-2024-05-13 ;;
    gpt5-nano) TARGET_MODEL=gpt-5-nano ;;
    gpt5.6-luna) TARGET_MODEL=gpt-5.6-luna ;;
    gpt5.6-terra) TARGET_MODEL=gpt-5.6-terra ;;
    *) TARGET_MODEL=${TARGET} ;;
  esac
  if [[ -z "${TARGET_PROVIDER}" ]]; then
    if [[ "${TARGET_MODEL}" == */* ]]; then TARGET_PROVIDER=openrouter
    else TARGET_PROVIDER=openai; fi
  fi
  if [[ -z "${TARGET_API_KEY_ENV}" ]]; then
    if [[ "${TARGET_PROVIDER}" == openrouter ]]; then TARGET_API_KEY_ENV=OPENROUTER_API_KEY
    else TARGET_API_KEY_ENV=OPENAI_API_KEY; fi
  fi
}

require_key() {
  local key_name=$1
  if [[ "${DRY_RUN}" != 1 && -z "${!key_name:-}" ]]; then
    echo "Set ${key_name} before training." >&2
    exit 2
  fi
}

start_target() {
  local model=$1 port=$2 gpu=$3 max_len=$4 memory=$5
  local url="http://127.0.0.1:${port}/v1"
  local log="logs/target_${port}.log"
  local command=("${VLLM_PYTHON}" -m vllm.entrypoints.openai.api_server
    --model "${model}" --port "${port}" --max-model-len "${max_len}"
    --gpu-memory-utilization "${memory}" --dtype bfloat16 --trust-remote-code)
  if [[ "${DRY_RUN}" == 1 ]]; then
    print_command env "CUDA_VISIBLE_DEVICES=${gpu}" "${command[@]}"
    return
  fi
  mkdir -p logs
  CUDA_VISIBLE_DEVICES="${gpu}" "${command[@]}" >"${log}" 2>&1 &
  local pid=$!
  SERVER_PIDS+=("${pid}")
  for attempt in $(seq 1 120); do
    if curl -sf "${url}/models" >/dev/null 2>&1; then return; fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "Target vLLM exited; see ${log}." >&2
      exit 1
    fi
    sleep 10
  done
  echo "Target vLLM timed out; see ${log}." >&2
  exit 1
}

ARGS=(-m train --benchmark "${BENCHMARK}")
case "${BENCHMARK}" in
  agentdyn|agentdojo)
    resolve_api_target
    CONFIG_FILE=${CONFIG_FILE:-configs/${BENCHMARK}.yaml}
    if [[ "${TARGET}" == local ]]; then
      TARGET_MODEL=local
      TARGET_PROVIDER=vllm
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-meta-llama/Llama-3.1-8B-Instruct}
      TARGET_PORT=${TARGET_PORT:-8000}
      if [[ -z "${TARGET_URL}" ]]; then
        TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
        start_target "${TARGET_MODEL_ID}" "${TARGET_PORT}" "${TARGET_GPU}" "${TARGET_MAX_MODEL_LEN:-131072}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.8}"
      fi
      [[ -n "${3:-${TRAIN_GPUS}}" ]] || TRAIN_GPUS=1,2,3,4
    else
      require_key "${TARGET_API_KEY_ENV}"
    fi
    if [[ "${BENCHMARK}" == agentdyn ]]; then TRAIN_SUITES=${TRAIN_SUITES:-github}
    else TRAIN_SUITES=${TRAIN_SUITES:-workspace}; fi
    ARGS+=(--config_file "${CONFIG_FILE}" --train_suites "${TRAIN_SUITES}"
      --target_model "${TARGET_MODEL}" --target_provider "${TARGET_PROVIDER}")
    [[ "${TARGET_PROVIDER}" == vllm ]] && ARGS+=(--target_model_id "${TARGET_MODEL_ID}" --target_model_url "${TARGET_URL}" --target_max_tokens "${TARGET_MAX_TOKENS}")
    [[ "${TARGET_PROVIDER}" != vllm ]] && ARGS+=(--target_api_key_env "${TARGET_API_KEY_ENV}")
    [[ -n "${TARGET_BASE_URL}" ]] && ARGS+=(--target_base_url "${TARGET_BASE_URL}")
    [[ -n "${TARGET_DEFENSE:-}" ]] && ARGS+=(--target_defense "${TARGET_DEFENSE}")
    [[ -n "${TRAIN_INJ:-}" ]] && ARGS+=(--train_injection_tasks "${TRAIN_INJ}")
    [[ -n "${TRAIN_USER:-}" ]] && ARGS+=(--train_user_tasks "${TRAIN_USER}")
    [[ -n "${EVAL_SUITES:-}" ]] && ARGS+=(--eval_suites "${EVAL_SUITES}")
    [[ -n "${EVAL_INJ:-}" ]] && ARGS+=(--eval_injection_tasks "${EVAL_INJ}")
    [[ -n "${EVAL_USER:-}" ]] && ARGS+=(--eval_user_tasks "${EVAL_USER}")
    ;;
  piarena)
    local_defense=${TARGET}
    if [[ "${local_defense}" == secalign ]]; then
      CONFIG_FILE=${CONFIG_FILE:-configs/piarena.yaml}
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-checkpoints/Meta-SecAlign-8B-merged}
    elif [[ "${local_defense}" == joint ]]; then
      CONFIG_FILE=${CONFIG_FILE:-configs/piarena_joint.yaml}
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-checkpoints/Meta-SecAlign-8B-merged}
    elif [[ -f "configs/piarena_${local_defense}.yaml" ]]; then
      CONFIG_FILE=${CONFIG_FILE:-configs/piarena_${local_defense}.yaml}
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-Qwen/Qwen3-4B-Instruct-2507}
    else
      echo "Unknown PIArena defense: ${local_defense}" >&2; exit 2
    fi
    if [[ -z "${TARGET_URL}" ]]; then
      TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
      start_target "${TARGET_MODEL_ID}" "${TARGET_PORT}" "${TARGET_GPU}" "${TARGET_MAX_MODEL_LEN:-8192}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.35}"
    fi
    [[ -n "${3:-${TRAIN_GPUS}}" ]] || TRAIN_GPUS=1,2,3
    ARGS+=(--config_file "${CONFIG_FILE}" --target_model_name_or_path "${TARGET_MODEL_ID}" --target_model_url "${TARGET_URL}")
    if [[ "${local_defense}" == joint ]]; then
      TARGET_PORT_2=${TARGET_PORT_2:-8011}
      TARGET_MODEL_ID_2=${TARGET_MODEL_ID_2:-meta-llama/Llama-3.1-8B-Instruct}
      if [[ -z "${TARGET_URL_2:-}" ]]; then
        TARGET_URL_2="http://127.0.0.1:${TARGET_PORT_2}/v1"
        start_target "${TARGET_MODEL_ID_2}" "${TARGET_PORT_2}" "${TARGET_GPU}" "${TARGET_MAX_MODEL_LEN:-8192}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.35}"
      fi
      ARGS+=(--target_model_name_or_path_2 "${TARGET_MODEL_ID_2}" --target_model_url_2 "${TARGET_URL_2}")
    else
      ARGS+=(--defense_method "${local_defense}")
    fi
    ;;
  injecagent)
    CONFIG_FILE=${CONFIG_FILE:-configs/injecagent.yaml}
    if [[ "${TARGET}" == secalign || "${TARGET}" == vllm || "${TARGET}" == multi ]]; then
      if [[ "${TARGET}" == multi ]]; then
        TARGET_MODEL_ID=${TARGET_MODEL_ID:-meta-llama/Llama-3.1-8B-Instruct}
      else
        TARGET_MODEL_ID=${TARGET_MODEL_ID:-checkpoints/Meta-SecAlign-8B-merged}
      fi
      if [[ -z "${TARGET_URL}" ]]; then
        TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
        start_target "${TARGET_MODEL_ID}" "${TARGET_PORT}" "${TARGET_GPU}" "${TARGET_MAX_MODEL_LEN:-8192}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.8}"
      fi
      [[ -n "${3:-${TRAIN_GPUS}}" ]] || TRAIN_GPUS=1,2,3
      if [[ "${TARGET}" == multi ]]; then
        TARGET_MODEL_ID="${TARGET_MODEL_ID};gpt-4o-mini-2024-07-18"
        TARGET_URL="${TARGET_URL};${TARGET_URL}"
      fi
    else
      resolve_api_target
      TARGET_MODEL_ID=${TARGET_MODEL}
      TARGET_URL=${TARGET_URL:-http://127.0.0.1:${TARGET_PORT}/v1}
    fi
    ARGS+=(--config_file "${CONFIG_FILE}" --dataset "${DATASET:-data/injecagent/dataset/train.json}"
      --target_model_name_or_path "${TARGET_MODEL_ID}" --target_model_url "${TARGET_URL}")
    ;;
  ipi_arena_os)
    resolve_api_target
    CONFIG_FILE=${CONFIG_FILE:-configs/ipi_arena_os.yaml}
    if [[ "${TARGET_PROVIDER}" == vllm ]]; then
      TARGET_BASE_URL=${TARGET_BASE_URL:-${TARGET_URL}}
      [[ -n "${TARGET_BASE_URL}" ]] || { echo "Set TARGET_BASE_URL for a local IPI Arena OS target." >&2; exit 2; }
    fi
    [[ "${TARGET_PROVIDER}" == vllm ]] || require_key "${TARGET_API_KEY_ENV}"
    JUDGE_MODEL=${JUDGE_MODEL:-gpt-5.6-luna}
    WORLDSIM_MODEL=${WORLDSIM_MODEL:-gpt-5.6-luna}
    JUDGE_PROVIDER=${JUDGE_PROVIDER:-$([[ "${JUDGE_MODEL}" == */* ]] && echo openrouter || echo openai)}
    WORLDSIM_PROVIDER=${WORLDSIM_PROVIDER:-$([[ "${WORLDSIM_MODEL}" == */* ]] && echo openrouter || echo openai)}
    JUDGE_API_KEY_ENV=${JUDGE_API_KEY_ENV:-$([[ "${JUDGE_PROVIDER}" == openrouter ]] && echo OPENROUTER_API_KEY || echo OPENAI_API_KEY)}
    WORLDSIM_API_KEY_ENV=${WORLDSIM_API_KEY_ENV:-$([[ "${WORLDSIM_PROVIDER}" == openrouter ]] && echo OPENROUTER_API_KEY || echo OPENAI_API_KEY)}
    [[ "${JUDGE_PROVIDER}" == vllm ]] || require_key "${JUDGE_API_KEY_ENV}"
    [[ "${WORLDSIM_PROVIDER}" == vllm ]] || require_key "${WORLDSIM_API_KEY_ENV}"
    ARGS+=(--config_file "${CONFIG_FILE}" --categories "${CATEGORIES:-tool,coding,browser}"
      --target_model "${TARGET_MODEL}" --target_provider "${TARGET_PROVIDER}" --target_api_key_env "${TARGET_API_KEY_ENV}"
      --judge_model "${JUDGE_MODEL}" --judge_provider "${JUDGE_PROVIDER}" --judge_api_key_env "${JUDGE_API_KEY_ENV}"
      --worldsim_model "${WORLDSIM_MODEL}" --worldsim_provider "${WORLDSIM_PROVIDER}" --worldsim_api_key_env "${WORLDSIM_API_KEY_ENV}")
    for prefix in TARGET JUDGE WORLDSIM; do
      base_var="${prefix}_BASE_URL"; effort_var="${prefix}_REASONING_EFFORT"
      [[ -n "${!base_var:-}" ]] && ARGS+=("--${prefix,,}_base_url" "${!base_var}")
      [[ -n "${!effort_var:-}" ]] && ARGS+=("--${prefix,,}_reasoning_effort" "${!effort_var}")
    done
    [[ -n "${BEHAVIOR_IDS:-}" ]] && ARGS+=(--behavior_ids "${BEHAVIOR_IDS}")
    [[ -n "${WAVES:-}" ]] && ARGS+=(--waves "${WAVES}")
    [[ -n "${MAX_WORKERS:-}" ]] && ARGS+=(--eval_max_workers "${MAX_WORKERS}")
    ;;
  *) echo "Unknown benchmark: ${BENCHMARK}" >&2; exit 2 ;;
esac

TRAIN_GPUS=${TRAIN_GPUS:-0,1,2,3}
tag=$(printf '%s' "${TARGET}" | tr '/: ' '___')
ARGS+=(--attacker_model_name_or_path "${ATTACKER_MODEL}")
for pair in OUTPUT_DIR:output_dir RUN_NAME:run_name NUM_TRAIN_EPOCHS:num_train_epochs LEARNING_RATE:learning_rate SAVE_STEPS:save_steps SAVE_TOTAL_LIMIT:save_total_limit REPORT_TO:report_to RESUME_FROM_CHECKPOINT:resume_from_checkpoint; do
  var=${pair%%:*}; flag=${pair#*:}
  [[ -n "${!var:-}" ]] && ARGS+=("--${flag}" "${!var}")
done
[[ -n "${RUN_NAME:-}" ]] || ARGS+=(--run_name "${BENCHMARK}_${tag}")
ARGS+=("${EXTRA_ARGS[@]}")
IFS=',' read -r -a GPU_LIST <<<"${TRAIN_GPUS}"
if (( ${#GPU_LIST[@]} == 1 )); then
  COMMAND=(python "${ARGS[@]}")
else
  COMMAND=(accelerate launch --config_file configs/accelerate.yaml --num_processes "${#GPU_LIST[@]}" "${ARGS[@]}")
fi

echo "Benchmark=${BENCHMARK}; target=${TARGET}; attacker=${ATTACKER_MODEL}; GPUs=${TRAIN_GPUS}"
if [[ "${DRY_RUN}" == 1 ]]; then
  print_command env "CUDA_VISIBLE_DEVICES=${TRAIN_GPUS}" "${COMMAND[@]}"
else
  CUDA_VISIBLE_DEVICES="${TRAIN_GPUS}" "${COMMAND[@]}"
fi
