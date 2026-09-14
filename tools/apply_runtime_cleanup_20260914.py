from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "index.html"
text = path.read_text(encoding="utf-8")
old = '\n<script src="./jgw-photo-storage-v2.js?v=20260914-2"></script>'
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one direct V2 include, found {count}")
text = text.replace(old, "", 1)
path.write_text(text, encoding="utf-8")
print("Removed duplicate direct V2 include; bundle loader remains canonical")
