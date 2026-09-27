#!/usr/bin/env bash
# Unified AgentDyn/AgentDojo evaluator.
# Usage: bash scripts/evaluate.sh <benchmark> <attacker-ckpt> <target-mode> <target-model>
# target-mode: openai | openrouter | compatible | vllm | secopd

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
export PYTHONPATH="${ROOT}:${PYTHONPATH:-}"

BENCHMARK=${1:?Pass agentdyn or agentdojo}
ATTACKER_MODEL=${2:?Pass an attacker checkpoint or model ID}
TARGET_MODE=${3:?Pass openai, openrouter, compatible, vllm, or secopd}
TARGET_MODEL=${4:?Pass the target API model slug or local model ID}

case "${BENCHMARK}" in
  agentdyn)
    EVAL_MODULE=eval.eval_agentdyn
    EVAL_SUITES=${EVAL_SUITES:-github,dailylife,shopping}
    ;;
  agentdojo)
    EVAL_MODULE=eval.eval_agentdojo
    EVAL_SUITES=${EVAL_SUITES:-workspace,banking,travel,slack}
    ;;
  *)
    echo "benchmark must be 'agentdyn' or 'agentdojo'" >&2
    exit 2
    ;;
esac

PYTHON_BIN=${PYTHON_BIN:-python}
VLLM_PYTHON=${VLLM_PYTHON:-python}
TARGET_VLLM_PYTHON=${TARGET_VLLM_PYTHON:-${VLLM_PYTHON}}
NUM_SAMPLES=${NUM_SAMPLES:-10}
MAX_WORKERS=${MAX_WORKERS:-16}
ATTACKER_MAX_TOKENS=${ATTACKER_MAX_TOKENS:-4096}
ATTACKER_MAX_MODEL_LEN=${ATTACKER_MAX_MODEL_LEN:-8192}
ATTACKER_GPUS=${ATTACKER_GPUS:-0}
ATTACKER_PORT=${ATTACKER_PORT:-8001}
ATTACKER_URL=${ATTACKER_URL:-}
ATTACKER_SERVED_MODEL=${ATTACKER_SERVED_MODEL:-attacker}
ATTACKER_TP_SIZE=${ATTACKER_TP_SIZE:-1}
ATTACKER_DP_SIZE=${ATTACKER_DP_SIZE:-1}
TARGET_GPUS=${TARGET_GPUS:-1}
TARGET_PORT=${TARGET_PORT:-8000}
TARGET_URL=${TARGET_URL:-}
TARGET_TP_SIZE=${TARGET_TP_SIZE:-1}
TARGET_DP_SIZE=${TARGET_DP_SIZE:-1}
TARGET_MAX_MODEL_LEN=${TARGET_MAX_MODEL_LEN:-131072}
TARGET_MAX_TOKENS=${TARGET_MAX_TOKENS:-32768}
TARGET_API_KEY_ENV=${TARGET_API_KEY_ENV:-}
TARGET_BASE_URL=${TARGET_BASE_URL:-}
TARGET_DEFENSE=${TARGET_DEFENSE:-}
OUTPUT_DIR=${OUTPUT_DIR:-eval_results/${BENCHMARK}_${TARGET_MODE}_$(basename "${TARGET_MODEL}")_$(basename "${ATTACKER_MODEL}")}
INJECTIONS_CACHE=${INJECTIONS_CACHE:-${OUTPUT_DIR}/injections_cache.json}
RESUME=${RESUME:-true}
EVAL_INJ=${EVAL_INJ:-}
EVAL_USER=${EVAL_USER:-}

mkdir -p logs "${OUTPUT_DIR}"
ulimit -n 65536 2>/dev/null || true

attacker_pid=""
target_pid=""

cleanup() {
  if [[ -n "${attacker_pid}" ]] && kill -0 "${attacker_pid}" 2>/dev/null; then
    kill "${attacker_pid}" 2>/dev/null || true
  fi
  if [[ -n "${target_pid}" ]] && kill -0 "${target_pid}" 2>/dev/null; then
    kill "${target_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_server() {
  local name=$1
  local url=$2
  local pid=$3
  local logfile=$4
  for attempt in $(seq 1 180); do
    if curl -sf "${url}/models" >/dev/null 2>&1; then
      echo "${name} server is ready."
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "${name} server exited; see ${logfile}." >&2
      return 1
    fi
    if (( attempt % 6 == 0 )); then
      echo "Waiting for ${name} server (${attempt}/180)..."
    fi
    sleep 10
  done
  echo "Timed out waiting for ${name} server; see ${logfile}." >&2
  return 1
}

start_attacker() {
  if [[ -n "${ATTACKER_URL}" ]]; then
    echo "Using external attacker server: ${ATTACKER_URL}"
    return
  fi

  local log_file="logs/attacker_$(basename "${ATTACKER_MODEL}")_${ATTACKER_PORT}.log"
  local model_args=(--model "${ATTACKER_MODEL}" --served-model-name "${ATTACKER_SERVED_MODEL}")
  if [[ -f "${ATTACKER_MODEL}/adapter_config.json" ]]; then
    local base_model
    base_model=$(
      "${PYTHON_BIN}" -c 'import json,sys; print(json.load(open(sys.argv[1]))["base_model_name_or_path"])' \
        "${ATTACKER_MODEL}/adapter_config.json"
    )
    model_args=(
      --model "${base_model}"
      --served-model-name "${base_model}"
      --enable-lora
      --lora-modules "${ATTACKER_SERVED_MODEL}=${ATTACKER_MODEL}"
    )
  fi

  echo "Starting attacker server on ${ATTACKER_GPUS}; log: ${log_file}"
  CUDA_VISIBLE_DEVICES="${ATTACKER_GPUS}" "${VLLM_PYTHON}" -m vllm.entrypoints.openai.api_server \
    "${model_args[@]}" \
    --port "${ATTACKER_PORT}" \
    --tensor-parallel-size "${ATTACKER_TP_SIZE}" \
    --data-parallel-size "${ATTACKER_DP_SIZE}" \
    --max-model-len "${ATTACKER_MAX_MODEL_LEN}" \
    --gpu-memory-utilization 0.85 \
    --dtype bfloat16 \
    --trust-remote-code \
    >"${log_file}" 2>&1 &
  attacker_pid=$!
  ATTACKER_URL="http://127.0.0.1:${ATTACKER_PORT}/v1"
  wait_for_server attacker "${ATTACKER_URL}" "${attacker_pid}" "${log_file}"
}

stop_attacker() {
  if [[ -n "${attacker_pid}" ]] && kill -0 "${attacker_pid}" 2>/dev/null; then
    kill "${attacker_pid}" 2>/dev/null || true
    wait "${attacker_pid}" 2>/dev/null || true
  fi
  attacker_pid=""
}

start_target() {
  if [[ -n "${TARGET_URL}" ]]; then
    echo "Using external target server: ${TARGET_URL}"
    return
  fi

  local log_file="logs/target_$(basename "${TARGET_MODEL}")_${TARGET_PORT}.log"
  local extra_args=()
  if [[ "${TARGET_MODE}" == "secopd" ]]; then
    extra_args+=(--default-chat-template-kwargs '{"enable_thinking":true}')
  fi
  echo "Starting target server on ${TARGET_GPUS}; log: ${log_file}"
  CUDA_VISIBLE_DEVICES="${TARGET_GPUS}" "${TARGET_VLLM_PYTHON}" -m vllm.entrypoints.openai.api_server \
    --model "${TARGET_MODEL}" \
    --served-model-name "${TARGET_MODEL}" \
    --port "${TARGET_PORT}" \
    --tensor-parallel-size "${TARGET_TP_SIZE}" \
    --data-parallel-size "${TARGET_DP_SIZE}" \
    --max-model-len "${TARGET_MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_WORKERS}" \
    --gpu-memory-utilization 0.90 \
    --dtype bfloat16 \
    --trust-remote-code \
    "${extra_args[@]}" \
    >"${log_file}" 2>&1 &
  target_pid=$!
  TARGET_URL="http://127.0.0.1:${TARGET_PORT}/v1"
  wait_for_server target "${TARGET_URL}" "${target_pid}" "${log_file}"
}

COMMON_ARGS=(
  --attacker_model "${ATTACKER_MODEL}"
  --eval_suites "${EVAL_SUITES}"
  --num_samples "${NUM_SAMPLES}"
  --max_tokens "${ATTACKER_MAX_TOKENS}"
  --max_workers "${MAX_WORKERS}"
  --output_dir "${OUTPUT_DIR}"
)
[[ -n "${EVAL_INJ}" ]] && COMMON_ARGS+=(--eval_injection_tasks "${EVAL_INJ}")
[[ -n "${EVAL_USER}" ]] && COMMON_ARGS+=(--eval_user_tasks "${EVAL_USER}")
[[ "${RESUME}" == "true" ]] && COMMON_ARGS+=(--resume)

if [[ "${TARGET_MODE}" == "secopd" && ! -f "${INJECTIONS_CACHE}" ]]; then
  start_attacker
  "${PYTHON_BIN}" -m "${EVAL_MODULE}" \
    "${COMMON_ARGS[@]}" \
    --attacker_server_url "${ATTACKER_URL}" \
    --attacker_served_model "${ATTACKER_SERVED_MODEL}" \
    --injections_cache "${INJECTIONS_CACHE}" \
    --generate_only
  stop_attacker
fi

TARGET_ARGS=()
case "${TARGET_MODE}" in
  openai|openrouter|compatible)
    if [[ -z "${TARGET_API_KEY_ENV}" ]]; then
      if [[ "${TARGET_MODE}" == "openrouter" ]]; then
        TARGET_API_KEY_ENV=OPENROUTER_API_KEY
      else
        TARGET_API_KEY_ENV=OPENAI_API_KEY
      fi
    fi
    if [[ -z "${!TARGET_API_KEY_ENV:-}" ]]; then
      echo "${TARGET_API_KEY_ENV} is not set." >&2
      exit 2
    fi
    provider=${TARGET_MODE}
    [[ "${TARGET_MODE}" == "compatible" ]] && provider=openai
    [[ "${TARGET_MODE}" == "openrouter" ]] && provider=openrouter
    TARGET_ARGS=(
      --target_model "${TARGET_MODEL}"
      --target_provider "${provider}"
      --target_api_key_env "${TARGET_API_KEY_ENV}"
    )
    [[ -n "${TARGET_BASE_URL}" ]] && TARGET_ARGS+=(--target_base_url "${TARGET_BASE_URL}")
    start_attacker
    ;;
  vllm|secopd)
    start_target
    TARGET_ARGS=(
      --target_model local
      --target_provider vllm
      --target_model_id "${TARGET_MODEL}"
      --target_model_url "${TARGET_URL}"
      --target_max_tokens "${TARGET_MAX_TOKENS}"
    )
    [[ "${TARGET_MODE}" == "secopd" ]] && TARGET_ARGS+=(--target_adapter secopd)
    [[ "${TARGET_MODE}" == "vllm" ]] && start_attacker
    ;;
  *)
    echo "Unknown target mode '${TARGET_MODE}'." >&2
    exit 2
    ;;
esac
[[ -n "${TARGET_DEFENSE}" ]] && TARGET_ARGS+=(--target_defense "${TARGET_DEFENSE}")

ATTACKER_ARGS=()
CACHE_ARGS=()
if [[ "${TARGET_MODE}" == "secopd" ]]; then
  CACHE_ARGS=(--injections_cache "${INJECTIONS_CACHE}")
else
  ATTACKER_ARGS=(
    --attacker_server_url "${ATTACKER_URL}"
    --attacker_served_model "${ATTACKER_SERVED_MODEL}"
  )
fi

"${PYTHON_BIN}" -m "${EVAL_MODULE}" \
  "${COMMON_ARGS[@]}" \
  "${ATTACKER_ARGS[@]}" \
  "${CACHE_ARGS[@]}" \
  "${TARGET_ARGS[@]}"

echo "Results: ${OUTPUT_DIR}/eval_results.json"
