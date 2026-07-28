"""mlx-chat — Multi-turn chat against the local MLX inference server."""

import os
import sys

from openai import OpenAI

client = OpenAI(base_url=os.environ.get("MLX_API_URL", "http://127.0.0.1:11434/v1"), api_key="n/a")
model = os.environ["MLX_DEFAULT_MODEL"]
messages = []

# One-shot from stdin
if not sys.stdin.isatty():
    messages.append({"role": "user", "content": sys.stdin.read().strip()})
    print(client.chat.completions.create(model=model, messages=messages).choices[0].message.content)
    sys.exit(0)

# Seed from args
if len(sys.argv) > 1:
    prompt = " ".join(sys.argv[1:])
    messages.append({"role": "user", "content": prompt})
    r = client.chat.completions.create(model=model, messages=messages)
    print(f"MLX: {r.choices[0].message.content}\n")
    messages.append({"role": "assistant", "content": r.choices[0].message.content})

# Interactive loop
while True:
    try:
        user = input("You: ").strip()
    except (EOFError, KeyboardInterrupt):
        break
    if not user or user in ("exit", "quit"):
        break
    messages.append({"role": "user", "content": user})
    r = client.chat.completions.create(model=model, messages=messages)
    print(f"MLX: {r.choices[0].message.content}\n")
    messages.append({"role": "assistant", "content": r.choices[0].message.content})
