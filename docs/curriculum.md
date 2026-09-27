# Climbing the Hill: curriculum RL for prompt injection red teaming

The Climbing the Hill paper studies a cold-start
problem in prompt injection RL: an initial attacker can receive no successful
attacks against a frontier target. The method trains one attacker across a
sequence of targets, using each checkpoint to initialize the next stage. A
candidate next target should yield nonzero attack success before starting the
new RL stage, so the attacker has a learning signal.

This guide covers the supplied AgentDyn and AgentDojo curriculum and transfer
scripts. The preset recipes implement the studied target sequences. For a custom
sequence, assess candidate targets before choosing the next stage; the scripts
run the sequence you specify and do not select targets automatically.

## Environment Setup

The code has been tested with Python 3.10 and CUDA 12.x.

```bash
conda create -n piforge python=3.10 -y
conda activate piforge
pip install -r requirements.txt
```

Install AgentDyn separately:

```bash
git clone https://github.com/SaFo-Lab/AgentDyn.git
pip install -e AgentDyn --no-deps
```

Set the API key used by the target models:

```bash
export OPENAI_API_KEY=<your-openai-api-key>
```

For OpenRouter or another OpenAI-compatible provider, use:

```bash
export OPENROUTER_API_KEY=<your-openrouter-api-key>
export TARGET_PROVIDER=openrouter
```

## Training

### AgentDyn Target Curriculum

Train a Qwen3-4B attacker against GPT-5-nano, GPT-5.6-Luna, and GPT-5.6-Terra in sequence:

```bash
TRAIN_GPUS=0,1,2,3 \
bash scripts/train_agentdyn_curriculum.sh nano-luna-terra
```

Each target is trained for 10 epochs by default. After a stage finishes, the numerically last `checkpoint-*` is used to initialize the attacker for the next target. Optimizer state is not carried between targets.

The following training paths are available:

```bash
bash scripts/train_agentdyn_curriculum.sh direct-luna
bash scripts/train_agentdyn_curriculum.sh 4o-mini-luna
bash scripts/train_agentdyn_curriculum.sh nano-luna
bash scripts/train_agentdyn_curriculum.sh nano-terra
bash scripts/train_agentdyn_curriculum.sh nano-luna-terra
```

To train on a custom sequence of target models:

```bash
TRAIN_GPUS=0,1,2,3 \
CURRICULUM_DIR=checkpoints/my_curriculum \
bash scripts/train_curriculum.sh "target-a,target-b,target-c"
```

Common overrides:

```bash
ATTACKER_MODEL=Qwen/Qwen3-4B-Instruct-2507
NUM_TRAIN_EPOCHS=10
LEARNING_RATE=1.0e-5
TRAIN_SUITES=github
REPORT_TO=none
```

Use `DRY_RUN=1` to print the complete training command without launching a job.

### Continued Training on a New Target

Continue training the final GPT-5.6-Terra attacker against Muse-Spark-1.2 on the AgentDyn GitHub subset:

```bash
TRAIN_GPUS=0,1,2,3 \
bash scripts/train_agentdyn_transfer.sh \
  checkpoints/agentdyn_curriculum/nano-luna-terra/stage_3_gpt-5.6-terra/checkpoint-XXX
```

If the provider uses a different model slug, override it with `MUSE_MODEL`:

```bash
MUSE_MODEL=<model-slug> \
bash scripts/train_agentdyn_transfer.sh <terra-attacker-checkpoint>
```

### Single-Target Training

```bash
TRAIN_GPUS=0,1,2,3 \
OUTPUT_DIR=checkpoints/agentdyn_nano \
bash scripts/train_stage.sh agentdyn gpt-5-nano \
  Qwen/Qwen3-4B-Instruct-2507
```

For a local target, start an OpenAI-compatible vLLM server first:

```bash
TARGET_PROVIDER=vllm \
TARGET_MODEL_ID=<local-model-id> \
TARGET_MODEL_URL=http://127.0.0.1:8000/v1 \
bash scripts/train_stage.sh agentdyn local \
  Qwen/Qwen3-4B-Instruct-2507
```

## Evaluation

The same evaluator supports AgentDyn and AgentDojo, arbitrary attacker checkpoints, and API or local targets:

```text
bash scripts/evaluate.sh <agentdyn|agentdojo> <attacker-checkpoint> \
  <openai|openrouter|compatible|vllm|secopd> <target-model>
```

### OpenAI Target on AgentDyn

```bash
ATTACKER_GPUS=0 NUM_SAMPLES=10 \
bash scripts/evaluate.sh agentdyn \
  checkpoints/attacker/checkpoint-XXX \
  openai gpt-5.6-terra
```

### OpenAI Target on AgentDojo

```bash
ATTACKER_GPUS=0 NUM_SAMPLES=10 \
bash scripts/evaluate.sh agentdojo \
  checkpoints/attacker/checkpoint-XXX \
  openai gpt-5.6-terra
```

### OpenRouter or OpenAI-Compatible Target

```bash
TARGET_API_KEY_ENV=OPENROUTER_API_KEY \
bash scripts/evaluate.sh agentdyn \
  checkpoints/attacker/checkpoint-XXX \
  openrouter google/gemini-3.7-flash
```

For another OpenAI-compatible service, select `compatible` and provide `TARGET_BASE_URL` and `TARGET_API_KEY_ENV`.

### Local SecOPD Target

```bash
ATTACKER_GPUS=0 \
TARGET_GPUS=0,1,2,3 \
TARGET_TP_SIZE=2 TARGET_DP_SIZE=2 \
TARGET_MAX_MODEL_LEN=131072 TARGET_MAX_TOKENS=32768 \
bash scripts/evaluate.sh agentdyn \
  checkpoints/attacker/checkpoint-XXX \
  secopd pybbb/Qwen3.6-27B-SecOPD
```

For SecOPD, attacker generations are cached before loading the target, allowing the same GPUs to be reused. Set `ATTACKER_URL` or `TARGET_URL` to use an already-running vLLM server.

Evaluation outputs are saved under `eval_results/` and include:

- `eval_results.json`: pass@k, sample-level ASR, and utility.
- `eval_detailed.jsonl`: representative per-case results.
- `eval_partial.jsonl`: resumable evaluation state.
- `injections_cache.json`: reusable attacker generations when caching is enabled.

Useful evaluation overrides include `EVAL_SUITES`, `EVAL_INJ`, `EVAL_USER`, `NUM_SAMPLES`, `MAX_WORKERS`, `OUTPUT_DIR`, and `INJECTIONS_CACHE`.
