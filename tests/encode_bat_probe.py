import base64
import io
import sys
from PIL import Image

path, label = sys.argv[1:]
image = Image.open(path).convert("RGB")
image.thumbnail((640, 360))
out = io.BytesIO()
image.save(out, format="JPEG", quality=65, optimize=True)
encoded = base64.b64encode(out.getvalue()).decode("ascii")
chunks = [encoded[i:i + 3800] for i in range(0, len(encoded), 3800)]
if len(chunks) > 10:
    raise ValueError(f"diagnostic too large: {len(chunks)} chunks")
for index, chunk in enumerate(chunks):
    print(f"::notice::{label}:{index}:{len(chunks)}:{chunk}")
