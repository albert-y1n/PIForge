#!/usr/bin/env bash
# Reproduce the AgentDyn target-curriculum training paths.
# Usage: bash scripts/train_agentdyn_curriculum.sh [nano-luna-terra]

set -euo pipefail

RECIPE=${1:-nano-luna-terra}
case "${RECIPE}" in
  direct-luna) TARGETS="gpt-5.6-luna" ;;
  4o-mini-luna) TARGETS="gpt-4o-mini-2024-07-18,gpt-5.6-luna" ;;
  nano-luna) TARGETS="gpt-5-nano,gpt-5.6-luna" ;;
  nano-terra) TARGETS="gpt-5-nano,gpt-5.6-terra" ;;
  nano-luna-terra) TARGETS="gpt-5-nano,gpt-5.6-luna,gpt-5.6-terra" ;;
  *)
    echo "Unknown recipe '${RECIPE}'." >&2
    echo "Choose: direct-luna, 4o-mini-luna, nano-luna, nano-terra, nano-luna-terra" >&2
    exit 2
    ;;
esac

export BENCHMARK=agentdyn
export TRAIN_SUITES=github
export TARGET_PROVIDER=${TARGET_PROVIDER:-openai}
export NUM_TRAIN_EPOCHS=${NUM_TRAIN_EPOCHS:-10}
export CURRICULUM_DIR=${CURRICULUM_DIR:-checkpoints/agentdyn_curriculum/${RECIPE}}

bash scripts/train_curriculum.sh "${TARGETS}"
