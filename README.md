<h1 align="center">PIForge</h1>

<p align="center"><strong>An Open Framework for RL-based Prompt Injection Red Teaming</strong></p>

<p align="center">
  💻 <a href="https://github.com/albert-y1n/PIForge">Code</a> ·
  📜 <a href="https://arxiv.org/abs/2603.13026">PISmith Paper</a> ·
  📖 <a href="docs/curriculum.md">Climbing the Hill Guide</a> ·
  🤗 <a href="https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4">Models</a>
</p>

PIForge is the shared codebase for **[PISmith](https://arxiv.org/abs/2603.13026)** and **Climbing the Hill**. It trains attacker language models to discover prompt injection failures through black-box feedback, and provides benchmark adapters, evaluation scripts, curriculum training workflows, and released checkpoints.

## ✨ News

- **2026.07** — [PISmith](https://arxiv.org/abs/2603.13026) was accepted to [COLM 2026](https://colm.eventhosts.cc/Conferences/2026/AcceptedPapers).

## 💡 Overview

The two works address different training regimes. **PISmith** learns from rare successful attacks against prompt injection defenses by maintaining exploration and weighting scarce successes. **Climbing the Hill** addresses a harder cold start: when an initial attacker succeeds against a frontier target so rarely that direct RL yields no useful reward. It trains the same attacker across a sequence of target models, using each stage to warm-start the next.

Both works use the same training core in [`train.py`](train.py) and [`core/`](core/). The repository also includes benchmark integrations for PIArena, InjecAgent, AgentDojo, AgentDyn, and IPI Arena OS.

## 🛡️ PISmith

**[PISmith: Reinforcement Learning-based Red Teaming for Prompt Injection Defenses](https://arxiv.org/abs/2603.13026)** trains an attacker against a black-box target using reinforcement learning. Its adaptive entropy regularization sustains exploration when rewards are sparse, while dynamic advantage weighting helps the attacker learn from rare successful injections.

- Training and evaluation recipes: [`scripts/`](scripts/) and the [PISmith guide](docs/pismith.md)
- Shared RL implementation: [`train.py`](train.py), [`core/trainer.py`](core/trainer.py), and [`benchmarks/`](benchmarks/)

## 🧗 Climbing the Hill

**Climbing the Hill: Prompt Injection Red-Teaming Against Frontier Models with Curriculum Reinforcement Learning** builds on PISmith to tackle the zero-reward cold start against frontier targets. It trains a single attacker across progressively stronger target models, initializing each stage from the preceding checkpoint. The paper uses nonzero pre-stage attack success as the criterion for choosing a target that can provide a learning signal; the supplied scripts include its target curriculum and transfer workflows.

- Stage and curriculum launchers: [`scripts/train_stage.sh`](scripts/train_stage.sh), [`scripts/train_curriculum.sh`](scripts/train_curriculum.sh), and [`scripts/train_agentdyn_curriculum.sh`](scripts/train_agentdyn_curriculum.sh)
- Transfer and evaluation: [`scripts/train_agentdyn_transfer.sh`](scripts/train_agentdyn_transfer.sh) and [`scripts/evaluate.sh`](scripts/evaluate.sh)
- Reproduction instructions: [curriculum guide](docs/curriculum.md)

## 🤗 Released Attackers

The [PIForge Hugging Face collection](https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4) groups all released attacker checkpoints. The [model catalog](checkpoints/models.json) and [download guide](checkpoints/README.md) provide direct links. Full weights are hosted on Hugging Face.

| Benchmark | Target | Attacker checkpoint |
|---|---|---|
| PIArena | Meta-SecAlign | [piarena_attacker_qwen3_4b_secalign](https://huggingface.co/AlbertYin/piarena_attacker_qwen3_4b_secalign) |
| PIArena | Qwen3-4B | [piarena_attacker_qwen3_4b_none](https://huggingface.co/AlbertYin/piarena_attacker_qwen3_4b_none) |
| InjecAgent | Meta-SecAlign | [injecagent_attacker_qwen3_4b_secalign](https://huggingface.co/AlbertYin/injecagent_attacker_qwen3_4b_secalign) |
| AgentDojo/AgentDyn  | GPT-4o-mini | [agentdojo_attacker_qwen3_4b_4o_mini](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_4o_mini) |
| AgentDojo/AgentDyn  | GPT-5-nano | [agentdojo_attacker_qwen3_4b_5_nano](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5_nano) |
| AgentDojo/AgentDyn  | GPT-5.6-Luna | [agentdojo_attacker_qwen3_4b_5.6_luna](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_luna) |
| AgentDojo/AgentDyn  | GPT-5.6-Terra | [agentdojo_attacker_qwen3_4b_5.6_terra](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_terra) |
| AgentDojo/AgentDyn  | Muse-Spark | [agentdojo_attacker_qwen3_4b_muse_spark](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_muse_spark) |

## 🚀 Getting Started

Create a Python 3.10 environment and install the dependencies:

```bash
git clone https://github.com/albert-y1n/PIForge.git
cd PIForge
conda create -n piforge python=3.10 -y
conda activate piforge
pip install -r requirements.txt
```

Choose the workflow for the paper you want to reproduce:

```bash
# PISmith: train an attacker on AgentDojo
bash scripts/train_agentdojo.sh gpt4o-mini workspace "0,1,2,3"

# Climbing the Hill: train across a target curriculum on AgentDyn
TRAIN_GPUS=0,1,2,3 bash scripts/train_agentdyn_curriculum.sh nano-luna-terra
```

Set the relevant target API key before training. AgentDyn workflows also require a separate AgentDyn install. The [PISmith guide](docs/pismith.md) and [curriculum guide](docs/curriculum.md) cover setup, target selection, evaluation, and overrides.

## 📄 License

PIForge is released under the [MIT License](LICENSE).
