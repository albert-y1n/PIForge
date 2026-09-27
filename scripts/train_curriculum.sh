#!/usr/bin/env bash
# AgentDyn target curriculum. Each stage calls scripts/train.sh.
# Usage: bash scripts/train_curriculum.sh [nano-luna-terra]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

RECIPE=${1:-nano-luna-terra}
case "${RECIPE}" in
  direct-luna) PRESET=gpt-5.6-luna ;;
  4o-mini-luna) PRESET=gpt-4o-mini-2024-07-18,gpt-5.6-luna ;;
  nano-luna) PRESET=gpt-5-nano,gpt-5.6-luna ;;
  nano-terra) PRESET=gpt-5-nano,gpt-5.6-terra ;;
  nano-luna-terra) PRESET=gpt-5-nano,gpt-5.6-luna,gpt-5.6-terra ;;
  *) echo "Unknown curriculum: ${RECIPE}" >&2; exit 2 ;;
esac

TARGETS=${TARGETS:-${PRESET}}
TRAIN_GPUS=${TRAIN_GPUS:-0,1,2,3}
TRAIN_SUITES=${TRAIN_SUITES:-github}
CURRICULUM_DIR=${CURRICULUM_DIR:-checkpoints/agentdyn_curriculum/${RECIPE}}
START_STAGE=${START_STAGE:-1}
attacker=${ATTACKER_MODEL:-Qwen/Qwen3-4B-Instruct-2507}
export NUM_TRAIN_EPOCHS=${NUM_TRAIN_EPOCHS:-10}
export REPORT_TO=${REPORT_TO:-none}
export DRY_RUN=${DRY_RUN:-0}

latest_checkpoint() {
  local stage_dir=$1 latest
  latest=$(find "${stage_dir}" -maxdepth 1 -type d -name 'checkpoint-*' -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
  if [[ -n "${latest}" ]]; then
    printf '%s/%s\n' "${stage_dir}" "${latest}"
  elif [[ "${DRY_RUN}" == 1 || -f "${stage_dir}/config.json" || -f "${stage_dir}/adapter_config.json" ]]; then
    printf '%s\n' "${stage_dir}"
  else
    echo "No saved attacker found in ${stage_dir}" >&2
    return 1
  fi
}

IFS=',' read -r -a stages <<<"${TARGETS}"
for index in "${!stages[@]}"; do
  number=$((index + 1))
  target=${stages[index]}
  tag=$(printf '%s' "${target}" | tr '/: ' '___')
  stage_dir="${CURRICULUM_DIR}/stage_${number}_${tag}"
  if (( number < START_STAGE )); then
    attacker=$(latest_checkpoint "${stage_dir}")
    continue
  fi
  echo "Stage ${number}/${#stages[@]}: ${target}"
  ATTACKER_MODEL="${attacker}" OUTPUT_DIR="${stage_dir}" \
  RUN_NAME="curriculum_stage${number}_${tag}" TRAIN_SUITES="${TRAIN_SUITES}" \
    bash scripts/train.sh agentdyn "${target}" "${TRAIN_GPUS}"
  attacker=$(latest_checkpoint "${stage_dir}")
done
echo "Final attacker: ${attacker}"
