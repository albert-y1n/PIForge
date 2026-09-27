#!/usr/bin/env bash
# Sequential target curriculum. Each stage initializes from the previous stage's
# numerically last checkpoint (or the saved stage directory if no checkpoint-* exists).
# Usage: bash scripts/train_curriculum.sh "gpt-5-nano,gpt-5.6-luna,gpt-5.6-terra"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TARGETS=${1:?Pass a comma-separated target curriculum}
BENCHMARK=${BENCHMARK:-agentdyn}
ATTACKER_MODEL=${ATTACKER_MODEL:-Qwen/Qwen3-4B-Instruct-2507}
CURRICULUM_DIR=${CURRICULUM_DIR:-checkpoints/curriculum}
NUM_TRAIN_EPOCHS=${NUM_TRAIN_EPOCHS:-10}
START_STAGE=${START_STAGE:-1}
DRY_RUN=${DRY_RUN:-0}

latest_checkpoint() {
  local stage_dir=$1
  local latest
  latest=$(find "${stage_dir}" -maxdepth 1 -type d -name 'checkpoint-*' -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
  if [[ -n "${latest}" ]]; then
    printf '%s/%s\n' "${stage_dir}" "${latest}"
  else
    printf '%s\n' "${stage_dir}"
  fi
}

IFS=',' read -r -a TARGET_LIST <<<"${TARGETS}"
if [[ "${#TARGET_LIST[@]}" -eq 0 ]]; then
  echo "Curriculum is empty." >&2
  exit 2
fi

for index in "${!TARGET_LIST[@]}"; do
  stage=$((index + 1))
  target="${TARGET_LIST[index]}"
  target="${target#${target%%[![:space:]]*}}"
  target="${target%${target##*[![:space:]]}}"
  tag=$(printf '%s' "${target}" | tr '/: ' '___')
  stage_dir="${CURRICULUM_DIR}/stage_${stage}_${tag}"

  if (( stage < START_STAGE )); then
    ATTACKER_MODEL=$(latest_checkpoint "${stage_dir}")
    continue
  fi

  echo ""
  echo "=== Curriculum stage ${stage}/${#TARGET_LIST[@]}: ${target} ==="
  BENCHMARK="${BENCHMARK}" \
  OUTPUT_DIR="${stage_dir}" \
  RUN_NAME="curriculum_stage${stage}_${tag}" \
  NUM_TRAIN_EPOCHS="${NUM_TRAIN_EPOCHS}" \
  DRY_RUN="${DRY_RUN}" \
    bash scripts/train_stage.sh "${BENCHMARK}" "${target}" "${ATTACKER_MODEL}"

  ATTACKER_MODEL=$(latest_checkpoint "${stage_dir}")
  echo "Next-stage attacker: ${ATTACKER_MODEL}"
done

echo "Final attacker: ${ATTACKER_MODEL}"
