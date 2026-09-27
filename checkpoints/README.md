# Released attacker checkpoints

The model catalog is in [`models.json`](models.json). All released weights are
hosted on Hugging Face and grouped in the [PIForge attacker collection](https://huggingface.co/collections/AlbertYin/piforge-attackers-6ab881634edba2b4387942d4).
Each entry links to the complete checkpoint, including its tokenizer and config.

Download one checkpoint from the repository root:

```bash
python -m pip install huggingface_hub
python scripts/download_attacker.py agentdojo_attacker_qwen3_4b_muse_spark
```

Run `python scripts/download_attacker.py --list` to see every model, or pass
`--all` to download every release. Files are saved under `checkpoints/` and are
ignored by Git. The model IDs can also be passed directly to the training and
evaluation scripts where a model path is accepted.
