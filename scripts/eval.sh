#!/usr/bin/env bash
# One evaluation entry point; attacker can be a local path or Hugging Face model ID.
# Usage: bash scripts/eval.sh <benchmark> <attacker> <target> [num_samples] [eval.py overrides...]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
export PYTHONPATH="${ROOT}/..:${ROOT}:${PYTHONPATH:-}"

BENCHMARK=${1:?Usage: bash scripts/eval.sh <piarena|injecagent|agentdojo|agentdyn|ipi_arena_os> <attacker> <target> [num_samples]}
ATTACKER=${2:?Pass a local checkpoint or Hugging Face model ID}
TARGET=${3:?Pass a target model or PIArena defense}
if [[ "${4:-}" == --* ]]; then
  NUM_SAMPLES=${NUM_SAMPLES:-10}
  EXTRA_ARGS=("${@:4}")
else
  NUM_SAMPLES=${4:-${NUM_SAMPLES:-10}}
  EXTRA_ARGS=("${@:5}")
fi
DRY_RUN=${DRY_RUN:-0}
TARGET_GPU=${TARGET_GPU:-0}
TARGET_PORT=${TARGET_PORT:-8010}
TARGET_URL=${TARGET_URL:-}
TARGET_MODEL_ID=${TARGET_MODEL_ID:-}
TARGET_PROVIDER=${TARGET_PROVIDER:-}
TARGET_API_KEY_ENV=${TARGET_API_KEY_ENV:-}
TARGET_BASE_URL=${TARGET_BASE_URL:-}
TARGET_MAX_TOKENS=${TARGET_MAX_TOKENS:-32768}
ATTACKER_URL=${ATTACKER_URL:-}
ATTACKER_PORT=${ATTACKER_PORT:-8001}
ATTACKER_MAX_TOKENS=${ATTACKER_MAX_TOKENS:-4096}
VLLM_PYTHON=${VLLM_PYTHON:-python}
EVAL_PYTHON=${EVAL_PYTHON:-python}
SERVER_PIDS=()
LOCAL_TARGET=0

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
    echo "Set ${key_name} before evaluation." >&2
    exit 2
  fi
}

start_vllm() {
  local name=$1 model=$2 port=$3 gpus=$4 max_len=$5 memory=$6
  local url="http://127.0.0.1:${port}/v1" log="logs/${name}_${port}.log"
  local command=("${VLLM_PYTHON}" -m vllm.entrypoints.openai.api_server
    --model "${model}" --port "${port}" --max-model-len "${max_len}"
    --gpu-memory-utilization "${memory}" --dtype bfloat16 --trust-remote-code)
  if [[ "${name}" == attacker ]]; then
    [[ "${ATTACKER_DP_SIZE:-1}" == 1 ]] || command+=(--data-parallel-size "${ATTACKER_DP_SIZE}")
    [[ "${ATTACKER_TP_SIZE:-1}" == 1 ]] || command+=(--tensor-parallel-size "${ATTACKER_TP_SIZE}")
  else
    [[ "${TARGET_DP_SIZE:-1}" == 1 ]] || command+=(--data-parallel-size "${TARGET_DP_SIZE}")
    [[ "${TARGET_TP_SIZE:-1}" == 1 ]] || command+=(--tensor-parallel-size "${TARGET_TP_SIZE}")
    [[ -z "${TARGET_CHAT_TEMPLATE_KWARGS:-}" ]] || command+=(--default-chat-template-kwargs "${TARGET_CHAT_TEMPLATE_KWARGS}")
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    print_command env "CUDA_VISIBLE_DEVICES=${gpus}" "${command[@]}"
    return
  fi
  mkdir -p logs
  CUDA_VISIBLE_DEVICES="${gpus}" "${command[@]}" >"${log}" 2>&1 &
  local pid=$!
  SERVER_PIDS+=("${pid}")
  for attempt in $(seq 1 120); do
    if curl -sf "${url}/models" >/dev/null 2>&1; then return; fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "${name} vLLM exited; see ${log}." >&2
      exit 1
    fi
    sleep 10
  done
  echo "${name} vLLM timed out; see ${log}." >&2
  exit 1
}

tag=$(printf '%s' "${TARGET}" | tr '/: ' '___')
OUTPUT_DIR=${OUTPUT_DIR:-eval_results/${BENCHMARK}_${tag}_pass${NUM_SAMPLES}_$(basename "${ATTACKER}")}
ARGS=(-m "eval.eval_${BENCHMARK}" --attacker_model "${ATTACKER}" --num_samples "${NUM_SAMPLES}" --output_dir "${OUTPUT_DIR}")

case "${BENCHMARK}" in
  piarena)
    if [[ "${TARGET}" == secalign ]]; then
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-checkpoints/Meta-SecAlign-8B-merged}
    elif [[ "${TARGET}" == joint ]]; then
      echo "PIArena joint training is evaluated one defense at a time." >&2; exit 2
    elif [[ -f "configs/piarena_${TARGET}.yaml" ]]; then
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-Qwen/Qwen3-4B-Instruct-2507}
    else
      echo "Unknown PIArena defense: ${TARGET}" >&2; exit 2
    fi
    LOCAL_TARGET=1
    if [[ -z "${TARGET_URL}" ]]; then
      TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
      start_vllm target "${TARGET_MODEL_ID}" "${TARGET_PORT}" "${TARGET_GPUS:-${TARGET_GPU}}" "${TARGET_MAX_MODEL_LEN:-32768}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.4}"
    fi
    ARGS+=(--target_model_url "${TARGET_URL}" --target_model_name_or_path "${TARGET_MODEL_ID}"
      --defense_method "${TARGET}" --judge_model_config "${JUDGE_CONFIG:-configs/judge.yaml}"
      --data_path "${DATA_PATH:-data/piarena}" --max_new_tokens "${ATTACKER_MAX_TOKENS}")
    ;;
  injecagent)
    if [[ "${TARGET}" == secalign || "${TARGET}" == vllm ]]; then
      LOCAL_TARGET=1
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-checkpoints/Meta-SecAlign-8B-merged}
      if [[ -z "${TARGET_URL}" ]]; then
        TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
        start_vllm target "${TARGET_MODEL_ID}" "${TARGET_PORT}" "${TARGET_GPUS:-${TARGET_GPU}}" "${TARGET_MAX_MODEL_LEN:-8192}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.8}"
      fi
      ARGS+=(--target_model_url "${TARGET_URL}" --target_model_name_or_path "${TARGET_MODEL_ID}")
    else
      resolve_api_target
      TARGET_MODEL_ID=${TARGET_MODEL}
      ARGS+=(--target_model_name_or_path "${TARGET_MODEL_ID}" --use_openai_target)
    fi
    ARGS+=(--data_path "${DATA_PATH:-data/injecagent/dataset/test.json}" --max_new_tokens "${ATTACKER_MAX_TOKENS}")
    ;;
  agentdyn|agentdojo)
    resolve_api_target
    if [[ "${TARGET}" == local || "${TARGET_PROVIDER}" == vllm ]]; then
      LOCAL_TARGET=1
      TARGET_MODEL_ID=${TARGET_MODEL_ID:-${TARGET_MODEL}}
      [[ "${TARGET_MODEL_ID}" == local ]] && TARGET_MODEL_ID=meta-llama/Llama-3.1-8B-Instruct
      TARGET_MODEL=local
      TARGET_PROVIDER=vllm
      if [[ -z "${TARGET_URL}" ]]; then
        TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
        start_vllm target "${TARGET_MODEL_ID}" "${TARGET_PORT}" "${TARGET_GPUS:-${TARGET_GPU}}" "${TARGET_MAX_MODEL_LEN:-131072}" "${TARGET_GPU_MEMORY_UTILIZATION:-0.8}"
      fi
    else
      require_key "${TARGET_API_KEY_ENV}"
    fi
    if [[ "${BENCHMARK}" == agentdyn ]]; then EVAL_SUITES=${EVAL_SUITES:-github}
    else EVAL_SUITES=${EVAL_SUITES:-workspace,banking,travel,slack}; fi
    ARGS+=(--target_model "${TARGET_MODEL}" --target_provider "${TARGET_PROVIDER}"
      --eval_suites "${EVAL_SUITES}" --max_tokens "${ATTACKER_MAX_TOKENS}"
      --max_workers "${MAX_WORKERS:-16}")
    if [[ "${TARGET_PROVIDER}" == vllm ]]; then
      ARGS+=(--target_model_id "${TARGET_MODEL_ID}" --target_model_url "${TARGET_URL}" --target_max_tokens "${TARGET_MAX_TOKENS}")
    else
      ARGS+=(--target_api_key_env "${TARGET_API_KEY_ENV}")
    fi
    [[ -z "${TARGET_BASE_URL}" ]] || ARGS+=(--target_base_url "${TARGET_BASE_URL}")
    [[ -z "${TARGET_DEFENSE:-}" ]] || ARGS+=(--target_defense "${TARGET_DEFENSE}")
    [[ -z "${TARGET_ADAPTER:-}" ]] || ARGS+=(--target_adapter "${TARGET_ADAPTER}")
    [[ -z "${EVAL_INJ:-}" ]] || ARGS+=(--eval_injection_tasks "${EVAL_INJ}")
    [[ -z "${EVAL_USER:-}" ]] || ARGS+=(--eval_user_tasks "${EVAL_USER}")
    [[ -z "${INJECTIONS_CACHE:-}" ]] || ARGS+=(--injections_cache "${INJECTIONS_CACHE}")
    [[ "${GENERATE_ONLY:-0}" != 1 ]] || ARGS+=(--generate_only)
    [[ "${RESUME:-0}" != 1 ]] || ARGS+=(--resume)
    ;;
  ipi_arena_os)
    resolve_api_target
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
    ARGS+=(--categories "${CATEGORIES:-tool,coding,browser}" --max_tokens "${ATTACKER_MAX_TOKENS}"
      --max_workers "${MAX_WORKERS:-8}" --generation_workers "${GENERATION_WORKERS:-32}"
      --max_steps "${MAX_STEPS:-5}"
      --target_model "${TARGET_MODEL}" --target_provider "${TARGET_PROVIDER}" --target_api_key_env "${TARGET_API_KEY_ENV}"
      --judge_model "${JUDGE_MODEL}" --judge_provider "${JUDGE_PROVIDER}" --judge_api_key_env "${JUDGE_API_KEY_ENV}"
      --worldsim_model "${WORLDSIM_MODEL}" --worldsim_provider "${WORLDSIM_PROVIDER}" --worldsim_api_key_env "${WORLDSIM_API_KEY_ENV}")
    for prefix in TARGET JUDGE WORLDSIM; do
      base_var="${prefix}_BASE_URL"; effort_var="${prefix}_REASONING_EFFORT"
      [[ -z "${!base_var:-}" ]] || ARGS+=("--${prefix,,}_base_url" "${!base_var}")
      [[ -z "${!effort_var:-}" ]] || ARGS+=("--${prefix,,}_reasoning_effort" "${!effort_var}")
    done
    [[ -z "${BEHAVIOR_IDS:-}" ]] || ARGS+=(--behavior_ids "${BEHAVIOR_IDS}")
    [[ -z "${WAVES:-}" ]] || ARGS+=(--waves "${WAVES}")
    ;;
  *) echo "Unknown benchmark: ${BENCHMARK}" >&2; exit 2 ;;
esac

if [[ -z "${ATTACKER_URL}" ]]; then
  if [[ -z "${ATTACKER_GPUS:-}" ]]; then
    if [[ "${LOCAL_TARGET}" == 1 ]]; then ATTACKER_GPUS=1
    else ATTACKER_GPUS=0; fi
  fi
  ATTACKER_URL="http://127.0.0.1:${ATTACKER_PORT}/v1"
  start_vllm attacker "${ATTACKER}" "${ATTACKER_PORT}" "${ATTACKER_GPUS}" "${ATTACKER_MAX_MODEL_LEN:-8192}" "${ATTACKER_GPU_MEMORY_UTILIZATION:-0.8}"
fi
ARGS+=(--attacker_server_url "${ATTACKER_URL}")
ARGS+=("${EXTRA_ARGS[@]}")

echo "Benchmark=${BENCHMARK}; attacker=${ATTACKER}; target=${TARGET}; output=${OUTPUT_DIR}"
if [[ "${DRY_RUN}" == 1 ]]; then
  print_command "${EVAL_PYTHON}" "${ARGS[@]}"
else
  "${EVAL_PYTHON}" "${ARGS[@]}"
fi
