import base64
import io
import sys
from PIL import Image

path, label = sys.argv[1:]
image = Image.open(path).convert("RGB")
image.thumbnail((640, 360))
for quality in (68, 58, 48, 38):
    out = io.BytesIO()
    image.save(out, format="JPEG", quality=quality, optimize=True)
    encoded = base64.b64encode(out.getvalue()).decode("ascii")
    if len(encoded) <= 38000:
        break
chunks = [encoded[i:i + 3800] for i in range(0, len(encoded), 3800)]
for index, chunk in enumerate(chunks):
    print(f"::notice::{label}:{index}:{len(chunks)}:{chunk}")
