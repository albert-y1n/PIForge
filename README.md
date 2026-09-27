<h1 align="center">PIForge</h1>

<p align="center"><strong>An Open Framework for RL-based Prompt Injection Red Teaming</strong></p>

<p align="center">
  💻 <a href="https://github.com/albert-y1n/PIForge">Code</a> ·
  🤗 <a href="https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4">Models</a> ·
  📜 <a href="#papers">Papers</a> ·
  📓 <a href="docs/training.md">Training Guide</a>
</p>

---

PIForge is the codebase for **[PISmith](https://arxiv.org/abs/2603.13026)** and **Climbing the Hill**. It trains attacker language models through reinforcement learning against prompt injection defenses. The same training core supports single-target RL and target curricula that move from easier targets to harder ones. We provide benchmark integrations, launch scripts, evaluation tools, and [released attacker models](https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4).

PISmith sustains exploration and learns from rare successful attacks; Climbing the Hill uses those same RL components across a sequence of targets so that a stronger target can be reached from a trained attacker.

## ✨ News

- **2026.07** — [PISmith](https://arxiv.org/abs/2603.13026) was accepted to COLM 2026.

## What's here

| Component | Where | Purpose |
|---|---|---|
| Benchmarks | [`benchmarks/`](benchmarks/) | Prompt injection tasks and reward adapters for PIArena, InjecAgent, AgentDojo, AgentDyn, and IPI Arena OS. |
| RL training | [`train.py`](train.py), [`core/`](core/), [`configs/`](configs/) | Shared attacker training implementation and benchmark configurations. |
| Recipes and evaluation | [`scripts/`](scripts/), [`eval/`](eval/) | Single-target and curriculum launchers, checkpoint transfer, and evaluation. |

## Quickstart

Run commands from the repository root. Training requires Python 3.10 and GPUs; API targets also require the relevant provider key.

```bash
git clone https://github.com/albert-y1n/PIForge.git
cd PIForge
conda create -n piforge python=3.10 -y
conda activate piforge
pip install -r requirements.txt
```

For AgentDyn experiments, install [AgentDyn](https://github.com/SaFo-Lab/AgentDyn) separately:

```bash
git clone https://github.com/SaFo-Lab/AgentDyn.git
pip install -e AgentDyn --no-deps
export OPENAI_API_KEY="your-openai-api-key"
```

### Train an attacker

The PISmith single-target recipes cover PIArena and InjecAgent. For GPT-4o-mini and GPT-5-nano on AgentDojo/AgentDyn, the recommended training set is the **AgentDyn `github` subset**; `train_agentdyn.sh` uses it by default. PIArena and InjecAgent use their own benchmark datasets.

| Task and target | Training recipe |
|---|---|
| PIArena · Meta-SecAlign | `bash scripts/train_piarena.sh secalign` |
| PIArena · no defense | `bash scripts/train_piarena.sh none` |
| InjecAgent · Meta-SecAlign | `bash scripts/train_injecagent.sh vllm` |
| AgentDojo/AgentDyn · GPT-4o-mini | `bash scripts/train_agentdyn.sh gpt4o-mini` |
| AgentDojo/AgentDyn · GPT-5-nano | `bash scripts/train_agentdyn.sh gpt5-nano` |

For GPT-5.6-Luna and GPT-5.6-Terra, train across target stages with curriculum RL. These presets also use the AgentDyn `github` subset:

```bash
TRAIN_GPUS=0,1,2,3 bash scripts/train_agentdyn_curriculum.sh nano-luna
TRAIN_GPUS=0,1,2,3 bash scripts/train_agentdyn_curriculum.sh nano-luna-terra
```

Each stage initializes the attacker from the previous stage's checkpoint. The [training guide](docs/training.md) covers other curricula, native AgentDojo suites, target setup, and evaluation.

### Evaluate an attacker

```bash
EVAL_SUITES=github ATTACKER_GPUS=0 \
  bash scripts/evaluate.sh agentdyn \
  checkpoints/agentdyn/checkpoint-XXX openai gpt-5-nano
```

PIArena and InjecAgent have benchmark-specific evaluation launchers in [`scripts/`](scripts/). See the [training guide](docs/training.md) for examples and options.

## Released attackers

All released weights are in the [PIForge Hugging Face collection](https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4). The [model catalog](checkpoints/models.json) lists the model IDs; weights are hosted on Hugging Face.

| Benchmark | Target | Attacker checkpoint |
|---|---|---|
| PIArena | Meta-SecAlign | [piarena_attacker_qwen3_4b_secalign](https://huggingface.co/AlbertYin/piarena_attacker_qwen3_4b_secalign) |
| PIArena | Qwen3-4B | [piarena_attacker_qwen3_4b_none](https://huggingface.co/AlbertYin/piarena_attacker_qwen3_4b_none) |
| InjecAgent | Meta-SecAlign | [injecagent_attacker_qwen3_4b_secalign](https://huggingface.co/AlbertYin/injecagent_attacker_qwen3_4b_secalign) |
| AgentDojo/AgentDyn | GPT-4o-mini | [agentdojo_attacker_qwen3_4b_4o_mini](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_4o_mini) |
| AgentDojo/AgentDyn | GPT-5-nano | [agentdojo_attacker_qwen3_4b_5_nano](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5_nano) |
| AgentDojo/AgentDyn | GPT-5.6-Luna | [agentdojo_attacker_qwen3_4b_5.6_luna](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_luna) |
| AgentDojo/AgentDyn | GPT-5.6-Terra | [agentdojo_attacker_qwen3_4b_5.6_terra](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_5.6_terra) |
| AgentDojo/AgentDyn | Muse-Spark | [agentdojo_attacker_qwen3_4b_muse_spark](https://huggingface.co/AlbertYin/agentdojo_attacker_qwen3_4b_muse_spark) |

## Papers

- [PISmith: Reinforcement Learning-based Red Teaming for Prompt Injection Defenses](https://arxiv.org/abs/2603.13026)
- Climbing the Hill: Prompt Injection Red-Teaming Against Frontier Models with Curriculum Reinforcement Learning

## License

PIForge is released under the [MIT License](LICENSE).
