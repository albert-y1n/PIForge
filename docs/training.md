# Training and evaluation

PIForge uses one RL training core for the PISmith single-target recipes and the Climbing the Hill target curricula. Run the commands below from the repository root. The default AgentDyn training suite is `github`; PIArena and InjecAgent use their own datasets.

## Setup

```bash
conda create -n piforge python=3.10 -y
conda activate piforge
pip install -r requirements.txt
```

Install [AgentDyn](https://github.com/SaFo-Lab/AgentDyn) for AgentDyn training or evaluation:

```bash
git clone https://github.com/SaFo-Lab/AgentDyn.git
pip install -e AgentDyn --no-deps
```

Set `OPENAI_API_KEY` for OpenAI targets. OpenRouter targets use `OPENROUTER_API_KEY`. Local targets require a GPU and a vLLM server, except where a benchmark launcher starts the server for you.

## Choose a training recipe

| Benchmark | Target | Method | Dataset | Launcher |
|---|---|---|---|---|
| PIArena | Meta-SecAlign or no defense | PISmith single-target RL | PIArena | `scripts/train_piarena.sh` |
| InjecAgent | Meta-SecAlign | PISmith single-target RL | InjecAgent | `scripts/train_injecagent.sh` |
| AgentDojo/AgentDyn | GPT-4o-mini or GPT-5-nano | PISmith single-target RL | AgentDyn `github` | `scripts/train_agentdyn.sh` |
| AgentDojo/AgentDyn | GPT-5.6-Luna or GPT-5.6-Terra | Curriculum RL | AgentDyn `github` | `scripts/train_agentdyn_curriculum.sh` |

The AgentDyn adapter builds on AgentDojo. The recommended `github` subset is an AgentDyn suite, so its commands use the AgentDyn launcher even when the released checkpoint name begins with `agentdojo_`. The native AgentDojo `workspace`, `banking`, `travel`, and `slack` suites remain available through `scripts/train_agentdojo.sh`.

### PIArena

For Meta-SecAlign, first prepare the merged target model with `python merge_meta_secalign.py`. This downloads the Llama 3.1 8B base and Meta-SecAlign adapter into `checkpoints/Meta-SecAlign-8B-merged/`.

```bash
bash scripts/train_piarena.sh secalign
bash scripts/train_piarena.sh none
```

The launcher accepts `[defense] [train_gpus] [target_gpu] [target_port]`. Its defaults are `secalign`, `1,2,3`, `0`, and `8010`. Other supported defenses include `promptguard`, `promptarmor`, `sandwich`, `instructional`, `datasentinel`, `piguard`, and `datafilter`.

```bash
bash scripts/eval_piarena.sh checkpoints/piarena/checkpoint-XXX secalign
```

### InjecAgent

The default launcher starts a local Meta-SecAlign target. It uses `data/injecagent/dataset/train.json` for training.

```bash
bash scripts/train_injecagent.sh vllm
bash scripts/eval_injecagent.sh checkpoints/injecagent/checkpoint-XXX vllm
```

The training launcher accepts `[target_type] [train_gpus] [target_gpu] [target_port]`; `target_type` can also be `gpt4o-mini` or `multi`.

### GPT-4o-mini and GPT-5-nano on AgentDyn

Both single-target recipes use the PISmith trainer and the AgentDyn `github` subset by default. The launcher accepts `[target_type] [suites] [train_gpus]` if you want to override the suite or GPUs.

```bash
bash scripts/train_agentdyn.sh gpt4o-mini
bash scripts/train_agentdyn.sh gpt5-nano

# Explicit suite and GPUs
bash scripts/train_agentdyn.sh gpt5-nano github "0,1,2,3"
```

To run the native AgentDojo benchmark instead, select one of its suites explicitly:

```bash
bash scripts/train_agentdojo.sh gpt4o-mini workspace "0,1,2,3"
```

## Curriculum RL for GPT-5.6 targets

The supplied presets train the same attacker across a sequence of target models. Each stage starts from the numerically last checkpoint of the previous stage; optimizer state does not carry across targets. The scripts execute the chosen sequence and do not automatically select a target based on success rate.

```bash
# GPT-5-nano → GPT-5.6-Luna
TRAIN_GPUS=0,1,2,3 bash scripts/train_agentdyn_curriculum.sh nano-luna

# GPT-5-nano → GPT-5.6-Luna → GPT-5.6-Terra
TRAIN_GPUS=0,1,2,3 bash scripts/train_agentdyn_curriculum.sh nano-luna-terra
```

Other presets are `direct-luna`, `4o-mini-luna`, and `nano-terra`. They all use the AgentDyn `github` subset and train each stage for 10 epochs by default. Override `NUM_TRAIN_EPOCHS`, `LEARNING_RATE`, `TRAIN_GPUS`, or `CURRICULUM_DIR` through environment variables.

For a custom target sequence:

```bash
TRAIN_GPUS=0,1,2,3 TRAIN_SUITES=github \
CURRICULUM_DIR=checkpoints/my_curriculum \
  bash scripts/train_curriculum.sh "gpt-5-nano,gpt-5.6-luna,gpt-5.6-terra"
```

Set `DRY_RUN=1` to print the training commands without launching jobs. For a single stage or a different initial attacker model, call `scripts/train_stage.sh <agentdyn|agentdojo> <target-model> [attacker-init]` directly.

### Continue from a Terra checkpoint

The transfer launcher continues training an attacker from a Terra checkpoint against Muse-Spark-1.2 on the AgentDyn `github` subset:

```bash
TRAIN_GPUS=0,1,2,3 \
  bash scripts/train_agentdyn_transfer.sh \
  checkpoints/agentdyn_curriculum/nano-luna-terra/stage_3_gpt-5.6-terra/checkpoint-XXX
```

Set `MUSE_MODEL` if your provider uses a different model slug.

## Evaluation

Use the same evaluator for AgentDyn and native AgentDojo runs. The target mode can be `openai`, `openrouter`, `compatible`, `vllm`, or `secopd`.

```bash
EVAL_SUITES=github ATTACKER_GPUS=0 NUM_SAMPLES=10 \
  bash scripts/evaluate.sh agentdyn \
  checkpoints/agentdyn/checkpoint-XXX openai gpt-5-nano

EVAL_SUITES=github ATTACKER_GPUS=0 NUM_SAMPLES=10 \
  bash scripts/evaluate.sh agentdyn \
  checkpoints/agentdyn_curriculum/nano-luna-terra/stage_3_gpt-5.6-terra/checkpoint-XXX \
  openai gpt-5.6-terra
```

For native AgentDojo evaluation, pass `agentdojo` and set `EVAL_SUITES` to an AgentDojo suite. OpenRouter and other OpenAI-compatible providers can be selected with `TARGET_API_KEY_ENV` and `TARGET_BASE_URL`. Local vLLM targets can use `TARGET_URL` to point to an existing server.

Results are written to `eval_results/`, including pass@k, sample-level ASR, and per-case records. `EVAL_INJ`, `EVAL_USER`, `NUM_SAMPLES`, `MAX_WORKERS`, and `OUTPUT_DIR` control evaluation scope and output.

The repository also includes [`scripts/train_ipi_arena_os.sh`](../scripts/train_ipi_arena_os.sh) and [`scripts/eval_ipi_arena_os.sh`](../scripts/eval_ipi_arena_os.sh) for IPI Arena OS. Browser behaviors require `playwright install chromium`.
