#!/usr/bin/env bash
# Continue a trained AgentDyn attacker against a new target.
# Usage: bash scripts/train_agentdyn_transfer.sh <terra-attacker-checkpoint>

set -euo pipefail

TERRA_ATTACKER=${1:?Pass the final GPT-5.6-Terra attacker checkpoint}
export TARGET_PROVIDER=${TARGET_PROVIDER:-openai}
export TRAIN_SUITES=github
export NUM_TRAIN_EPOCHS=${NUM_TRAIN_EPOCHS:-10}
export OUTPUT_DIR=${OUTPUT_DIR:-checkpoints/agentdyn_transfer/muse-spark-1.2}
export RUN_NAME=${RUN_NAME:-agentdyn_transfer_muse_spark_1_2}
MUSE_MODEL=${MUSE_MODEL:-muse-spark-1.2}

bash scripts/train_stage.sh agentdyn "${MUSE_MODEL}" "${TERRA_ATTACKER}"
