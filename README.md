<h1 align="center">PIForge</h1>

<p align="center"><strong>An Open Framework for RL-based Prompt Injection Red Teaming</strong></p>

<p align="center">
  💻 <a href="https://github.com/albert-y1n/PIForge">Code</a> ·
  🤗 <a href="https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4">Models &amp; Checkpoints</a> ·
  📜 <a href="https://arxiv.org/abs/2603.13026">Paper</a> ·
  📖 <a href="docs/curriculum.md">Curriculum Guide</a>
</p>

PIForge brings the [PISmith](https://github.com/albert-y1n/PISmith/tree/dev) RL prompt-injection framework and the [Climbing the Hill curriculum and transfer workflows](docs/curriculum.md) into one repository. It covers attacker training and evaluation on PIArena, AgentDojo, AgentDyn, InjecAgent, and IPI Arena OS. See the [PISmith paper](https://arxiv.org/abs/2603.13026) for research results.

## News

- **2026.07** — [PISmith](https://arxiv.org/abs/2603.13026) was accepted to [COLM 2026](https://colm.eventhosts.cc/Conferences/2026/AcceptedPapers).

## What's here

| Area | Entry point | Purpose |
|---|---|---|
| Training | `train.py`, `core/`, `configs/` | RL attacker training |
| Benchmarks | `benchmarks/`, `defenses/` | Task adapters and target defenses |
| Evaluation | `eval/`, `scripts/eval_*.sh` | Benchmark evaluation |

## Released attacker checkpoints

All public attacker models are grouped in the [PIForge collection](https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4). The GitHub [checkpoint catalog](checkpoints/README.md) and [machine-readable manifest](checkpoints/models.json) list every model. Full weights are hosted on Hugging Face; the repository provides direct links and a download tool.

| Benchmark | Target | Hugging Face model |
|---|---|---|
| PIArena | Meta-SecAlign | [piarena_attacker_qwen3_4b_secalign](https://huggingface.co/AlbertYin/piarena_attacker_qwen3_4b_secalign) |
| PIArena | No defense | [piarena_attacker_qwen3_4b_none](https://huggingface.co/AlbertYin/piarena_attacker_qwen3_4b_none) |
| AgentDojo | GPT-4o-mini | [agentdojo_attacker_qwen3_4b_4o_mini](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_4o_mini) |
| AgentDojo | GPT-5-nano | [agentdojo_attacker_qwen3_4b_5_nano](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5_nano) |
| InjecAgent | Meta-SecAlign | [injecagent_attacker_qwen3_4b_secalign](https://huggingface.co/AlbertYin/injecagent_attacker_qwen3_4b_secalign) |
| AgentDojo | GPT-5.6-Luna | [agentdojo_attacker_qwen3_4b_5.6_luna](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_luna) |
| AgentDojo | GPT-5.6-Terra | [agentdojo_attacker_qwen3_4b_5.6_terra](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_terra) |
| AgentDojo | GPT-5.6-Terra (dev) | [agentdojo_attacker_qwen3_4b_5.6_terra_dev](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_terra_dev) |
| AgentDojo | Muse-Spark | [agentdojo_attacker_qwen3_4b_muse_spark](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_muse_spark) |

Download one model, or use `--all` for the full catalog:

```bash
python -m pip install huggingface_hub
python scripts/download_attacker.py agentdojo_attacker_qwen3_4b_muse_spark
python scripts/download_attacker.py --list
```

## Curriculum training and unified evaluation

```bash
# AgentDyn: GPT-5-nano → GPT-5.6-Luna → GPT-5.6-Terra
TRAIN_GPUS=0,1,2,3 bash scripts/train_agentdyn_curriculum.sh nano-luna-terra

# Train another stage from the final Terra checkpoint
bash scripts/train_agentdyn_transfer.sh \
  checkpoints/agentdyn_curriculum/nano-luna-terra/stage_3_gpt-5.6-terra/checkpoint-XXX

# Evaluate a released attacker against an API target
bash scripts/evaluate.sh agentdojo \
  AlbertYin/agentdojo_attacker_qwen3_4b_muse_spark openai muse-spark-1.2
```

Set `OPENAI_API_KEY` for OpenAI-compatible targets, or use `TARGET_PROVIDER=openrouter` with `OPENROUTER_API_KEY` when training through OpenRouter. See [the curriculum guide](docs/curriculum.md) for recipes, overrides, local targets, and evaluation modes.

---

## Environment Setup

The PISmith training environment has been tested with Python 3.10 and CUDA 12.9.

**1. Create a Python 3.10 conda environment**

```bash
conda create -n piforge python=3.10 -y
conda activate piforge
```

**2. Install dependencies** 

```bash
pip install -r requirements.txt
```

**3. (Optional) Prepare the [Meta-SecAlign](https://github.com/facebookresearch/Meta_SecAlign) model checkpoint**

For experiments targeting the `secalign` defense, run the provided merge script to download and merge the base model with the SecAlign adapter:

```bash
python merge_meta_secalign.py
```

This downloads `meta-llama/Llama-3.1-8B-Instruct` and `facebook/Meta-SecAlign-8B` from HuggingFace, merges them, and saves the result to `checkpoints/Meta-SecAlign-8B-merged/`.

---

## Scripts

### [PIArena](https://github.com/sleeepeer/PIArena)

[PIArena](https://github.com/sleeepeer/PIArena) supports training and evaluation against a range of prompt injection defenses. Use the `defense` argument to select the target defense.

**Supported defenses:**
`secalign`, `none`, `promptguard`, `promptarmor`, `sandwich`, `instructional`, `datasentinel`, `piguard`, `datafilter`

#### Training

```bash
bash scripts/train_piarena.sh <defense> [train_gpus] [target_gpu] [target_port]
```

| Argument | Default | Description |
|---|---|---|
| `defense` | `secalign` | Defense to train against |
| `train_gpus` | `"1,2,3"` | GPU indices for RL training |
| `target_gpu` | `0` | GPU for the target vLLM server |
| `target_port` | `8010` | Port for the target vLLM server |

Examples:

```bash
# Train against SecAlign defense
bash scripts/train_piarena.sh secalign

# Train against no defense (plain LLM)
bash scripts/train_piarena.sh none
```

#### Evaluation

```bash
bash scripts/eval_piarena.sh <checkpoint> <defense> [target_port] [target_gpu] [attacker_gpu] [attacker_port] [num_samples]
```

| Argument | Default | Description |
|---|---|---|
| `checkpoint` | — | Path to trained attacker checkpoint |
| `defense` | `secalign` | Defense to evaluate against |
| `target_port` | `8000` | Port for the target vLLM server |
| `target_gpu` | `0` | GPU for the target vLLM server |
| `attacker_gpu` | `1` | GPU for the attacker vLLM server |
| `attacker_port` | `8001` | Port for the attacker vLLM server |
| `num_samples` | `10` | Pass@k: number of samples per test case |

Examples:

```bash
# Evaluate against SecAlign (default settings)
bash scripts/eval_piarena.sh checkpoints/piarena/checkpoint-500 secalign

# Evaluate against no piguard, pass@10
bash scripts/eval_piarena.sh checkpoints/piarena_none/checkpoint-500 piguard
```
---

### [AgentDojo](https://github.com/ethz-spylab/agentdojo)

Supports OpenAI, OpenRouter, and local vLLM targets. OpenRouter uses the
OpenAI-compatible endpoint and reads credentials from `OPENROUTER_API_KEY`.

```bash
bash scripts/train_agentdojo.sh [target_type] [suites] [train_gpus]
```

```bash
# Default: GPT-4o-mini target on the firsr 7 injected task of workspace suite
bash scripts/train_agentdojo.sh

# Train on all suites (workspace, banking, travel, slack)
bash scripts/train_agentdojo.sh gpt4o-mini all

# OpenRouter example: Gemini 3.7 Flash
export OPENROUTER_API_KEY=<your-key>
bash scripts/train_agentdojo.sh gemini-3.7-flash workspace "0,1,2,3"
```

Evaluation:

```bash
bash scripts/eval_agentdojo.sh <checkpoint> [target_type] [eval_suites] [num_samples] [target_defense]

# Example
bash scripts/eval_agentdojo.sh checkpoints/agentdojo/checkpoint-500 gpt4o-mini

# OpenRouter example
export OPENROUTER_API_KEY=<your-key>
bash scripts/eval_agentdojo.sh checkpoints/agentdojo/checkpoint-500 \
    gemini-3.7-flash workspace 10
```

---

### [AgentDyn](https://github.com/SaFo-Lab/AgentDyn)

AgentDyn is built on top of AgentDojo. Install it separately before running AgentDyn experiments:

```bash
git clone https://github.com/SaFo-Lab/AgentDyn.git
cd AgentDyn
pip install -e . --no-deps
```

Training supports AgentDyn suites such as `github`, `dailylife`, and `shopping`.

```bash
bash scripts/train_agentdyn.sh [target_type] [suites] [train_gpus]

# Example
bash scripts/train_agentdyn.sh gpt5-nano github "0,1,2,3"

# OpenRouter example: Gemini 3.7 Flash
export OPENROUTER_API_KEY=<your-key>
bash scripts/train_agentdyn.sh gemini-3.7-flash github "0,1,2,3"
```

Evaluation reports both pass@k and sample-level average ASR, and supports data-parallel attacker vLLM serving:

```bash
ATTACKER_GPUS=0,1,2,3 ATTACKER_DP_SIZE=4 \
bash scripts/eval_agentdyn.sh checkpoints/agentdyn/checkpoint-500 gpt5-nano "github,dailylife,shopping" 5

# Use another OpenRouter model by overriding the model slug
export OPENROUTER_API_KEY=<your-key>
OPENROUTER_MODEL=google/gemini-3.7-flash \
bash scripts/eval_agentdyn.sh checkpoints/agentdyn/checkpoint-500 openrouter github 10
```

---

### [InjecAgent](https://github.com/uiuc-kang-lab/InjecAgent)

Supports a local vLLM target, GPT-4o-mini, or multi-target mode.

```bash
bash scripts/train_injecagent.sh [target_type] [train_gpus] [target_gpu] [target_port]
```

```bash
# Default: local vLLM target (Meta-SecAlign-8B)
bash scripts/train_injecagent.sh

# GPT-4o-mini API target
bash scripts/train_injecagent.sh gpt4o-mini
```

Evaluation:

```bash
bash scripts/eval_injecagent.sh <checkpoint> [target_type] [target_gpu] [target_port] [eval_gpu] [num_samples]

# Example
bash scripts/eval_injecagent.sh checkpoints/injecagent/checkpoint-500
```

---

### [IPI Arena OS](https://github.com/GraySwanAI/ipi_arena_os)

IPI Arena OS contains 41 indirect prompt-injection behaviors across `tool`,
`coding`, and `browser`. The target model is configurable; the LLM judge and
WorldSim both default to `gpt-5.6-luna`. GPT-5.6 target, judge, and WorldSim
requests use `reasoning_effort=medium` and do not set a completion-token cap.

AgentDojo/AgentDyn local-target evaluation launchers and the SecOPD launcher use
a 131,072 token context window and a 32,768 token per-response output cap by
default. Local-target training uses an external vLLM server: start it with
`--max-model-len 131072`; PISmith still enforces the 32,768-token response cap.

Install Chromium once before running browser behaviors:

```bash
playwright install chromium
```

Training:

```bash
bash scripts/train_ipi_arena_os.sh [target_model] [categories] [train_gpus]

# Example: all 41 behaviors with a GPT-5.6 Luna target
bash scripts/train_ipi_arena_os.sh gpt-5.6-luna "tool,coding,browser" "0,1,2,3"

# Use Gemini for target, judge, and WorldSim through OpenRouter
export OPENROUTER_API_KEY=<your-key>
JUDGE_MODEL=google/gemini-3.7-flash \
WORLDSIM_MODEL=google/gemini-3.7-flash \
bash scripts/train_ipi_arena_os.sh google/gemini-3.7-flash \
    "tool,coding,browser" "0,1,2,3"
```

Evaluation reports behavior-level ASR@k and sample-level average ASR:

```bash
bash scripts/eval_ipi_arena_os.sh <checkpoint> [target_model] [categories] [num_samples]

# Example: pass@10 on all categories
bash scripts/eval_ipi_arena_os.sh checkpoints/ipi_arena_os/checkpoint-500 \
    gpt-5.6-luna "tool,coding,browser" 10

# Use Gemini for target, judge, and WorldSim through OpenRouter
export OPENROUTER_API_KEY=<your-key>
JUDGE_MODEL=google/gemini-3.7-flash \
WORLDSIM_MODEL=google/gemini-3.7-flash \
bash scripts/eval_ipi_arena_os.sh checkpoints/ipi_arena_os/checkpoint-500 \
    google/gemini-3.7-flash "tool,coding,browser" 10
```

Use `BEHAVIOR_IDS`, `WAVES`, `TARGET_PROVIDER`, `TARGET_BASE_URL`, and the
corresponding `JUDGE_*` / `WORLDSIM_*` environment variables for finer control.
Optional OpenRouter attribution headers can be configured with
`OPENROUTER_HTTP_REFERER` and `OPENROUTER_APP_NAME`.
