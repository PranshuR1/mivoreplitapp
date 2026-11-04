"""Download the reviewed public model at build time; no credentials are needed."""
from hashlib import sha256
from pathlib import Path
from urllib.request import urlopen

REVISION = "91cad51170dc346986eccefdc2dd33a9da36ead9"
BASE = f"https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/{REVISION}"
EXPECTED = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
destination = Path("/model")
destination.mkdir(parents=True, exist_ok=True)
partial = destination / "model.partial"
try:
    digest = sha256()
    with urlopen(f"{BASE}/qwen2.5-1.5b-instruct-q4_k_m.gguf", timeout=120) as source, partial.open("wb") as output:
        while chunk := source.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
    if digest.hexdigest() != EXPECTED:
        raise RuntimeError("Downloaded model checksum did not match the reviewed revision")
    partial.replace(destination / "model.gguf")
finally:
    partial.unlink(missing_ok=True)
for source_name, target_name in [("LICENSE", "LICENSE-QWEN"), ("README.md", "MODEL_CARD.md")]:
    with urlopen(f"{BASE}/{source_name}", timeout=30) as source:
        (destination / target_name).write_bytes(source.read())
