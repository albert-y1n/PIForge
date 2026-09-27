<h1 align="center">PIForge</h1>

<p align="center"><strong>An Open Framework for RL-based Prompt Injection Red Teaming</strong></p>

<p align="center">
  💻 <a href="https://github.com/albert-y1n/PIForge">Code</a> ·
  🤗 <a href="https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4">Models</a> ·
  📜 <a href="#papers">Papers</a>
</p>

---

PIForge is the shared codebase for **[PISmith](https://arxiv.org/abs/2603.13026)** and **Climbing the Hill**. PISmith addresses the sparse reward problem in prompt injection red teaming, helping RL attackers explore and learn from rare successful attacks. Building on PISmith, Climbing the Hill uses curriculum learning to address the cold start problem when red teaming more robust frontier targets.

## ✨ News

- **2026.07** — [PISmith](https://arxiv.org/abs/2603.13026) was accepted to COLM 2026.

## What's here

| Component | Where | Purpose |
|---|---|---|
| Benchmarks | [`benchmarks/`](benchmarks/) | PIArena, InjecAgent, AgentDojo, AgentDyn, and IPI Arena. |
| Training core | [`train.py`](train.py), [`core/`](core/), [`configs/`](configs/) | Shared RL trainer and benchmark configurations. |
| Entry points | [`scripts/`](scripts/), [`eval/`](eval/) | One training script, one curriculum script, and one evaluation script. |

## Setup

Run commands from the repository root. Training requires Python 3.10 and GPUs.

```bash
git clone https://github.com/albert-y1n/PIForge.git
cd PIForge
conda create -n piforge python=3.10 -y
conda activate piforge
pip install -r requirements.txt
```

The three entry points share a small interface:

```text
bash scripts/train.sh <benchmark> <target> [train_gpus] [train.py overrides...]
bash scripts/train_curriculum.sh [curriculum]
bash scripts/eval.sh <benchmark> <attacker path or HF model ID> <target> [num_samples] [eval.py overrides...]
```

Use environment variables such as `ATTACKER_MODEL`, `TRAIN_SUITES`, `OUTPUT_DIR`, `LEARNING_RATE`, and `NUM_TRAIN_EPOCHS` to change a run. `DRY_RUN=1` prints the commands without launching models.

## AgentDojo / AgentDyn

Install [AgentDyn](https://github.com/SaFo-Lab/AgentDyn) for the AgentDyn `github` subset, which is the default training suite for the AgentDojo/AgentDyn recipes below:

```bash
git clone https://github.com/SaFo-Lab/AgentDyn.git
pip install -e AgentDyn --no-deps
export OPENAI_API_KEY="your-openai-api-key"
```

Train with PISmith against GPT-4o-mini or GPT-5-nano:

```bash
bash scripts/train.sh agentdyn gpt4o-mini
bash scripts/train.sh agentdyn gpt5-nano
```

Train toward GPT-5.6-Luna or GPT-5.6-Terra with curriculum RL. Each stage starts from the preceding stage's attacker checkpoint:

```bash
bash scripts/train_curriculum.sh nano-luna
bash scripts/train_curriculum.sh nano-luna-terra
```

The same single-target entry point continues training from any attacker model or saved checkpoint:

```bash
ATTACKER_MODEL=checkpoints/agentdyn_curriculum/nano-luna-terra/stage_3_gpt-5.6-terra/checkpoint-XXX \
OUTPUT_DIR=checkpoints/muse_spark \
  bash scripts/train.sh agentdyn muse-spark-1.2
```

Evaluate a released Hugging Face model directly.

```bash
bash scripts/eval.sh agentdyn AlbertYin/agentdojo_attacker_qwen3_4b_5_nano gpt5-nano 10
bash scripts/eval.sh agentdyn AlbertYin/agentdojo_attacker_qwen3_4b_5.6_terra gpt-5.6-terra 10
```

For AgentDojo suites, choose `agentdojo` and set `TRAIN_SUITES` or `EVAL_SUITES` to `workspace`, `banking`, `travel`, or `slack`:

```bash
TRAIN_SUITES=workspace bash scripts/train.sh agentdojo gpt4o-mini
EVAL_SUITES=workspace bash scripts/eval.sh agentdojo AlbertYin/agentdojo_attacker_qwen3_4b_4o_mini gpt4o-mini 10
```

## InjecAgent

Prepare the local [Meta-SecAlign](https://github.com/facebookresearch/Meta_SecAlign) target once with `python merge_meta_secalign.py`. Then train and evaluate with the InjecAgent dataset:

```bash
bash scripts/train.sh injecagent secalign
bash scripts/eval.sh injecagent AlbertYin/injecagent_attacker_qwen3_4b_secalign secalign 10
```

The script starts the local target on GPU 0 and uses GPUs 1,2,3 for training by default. Set `TARGET_GPU`, `TRAIN_GPUS`, or `TARGET_URL` to change this setup.

## PIArena

The same Meta-SecAlign preparation applies to the `secalign` defense. PIArena uses its own benchmark dataset:

```bash
bash scripts/train.sh piarena secalign
bash scripts/train.sh piarena none
bash scripts/eval.sh piarena AlbertYin/piarena_attacker_qwen3_4b_secalign secalign 10
```

Other defenses can be selected by their configuration name, such as `promptguard` or `piguard`. Set `TARGET_GPU`, `TRAIN_GPUS`, or `TARGET_URL` to use different GPUs or an existing target server.

## Released attackers

We release our trained attackers in the [PIForge Hugging Face collection](https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4).

## Papers

- [PISmith: Reinforcement Learning-based Red Teaming for Prompt Injection Defenses](https://arxiv.org/abs/2603.13026)
- Climbing the Hill: Prompt Injection Red-Teaming Against Frontier Models with Curriculum Reinforcement Learning

## License

PIForge is released under the [MIT License](LICENSE).
