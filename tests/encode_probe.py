import base64
import io
import sys
from PIL import Image

path, label, group = sys.argv[1], sys.argv[2], int(sys.argv[3])
image = Image.open(path).convert("RGB")
if label == "CLOSE":
    x = (image.width - 640) // 2
    y = (image.height - 360) // 2
    image = image.crop((x, y, x + 640, y + 360))
else:
    image.thumbnail((640, 360))
output = io.BytesIO()
image.save(output, format="JPEG", quality=58, optimize=True)
data = base64.b64encode(output.getvalue()).decode("ascii")
chunks = [data[i:i + 3800] for i in range(0, len(data), 3800)]
if len(chunks) > 20:
    raise ValueError(f"visual diagnostic is too large: {len(chunks)} parts")
for index, chunk in enumerate(chunks):
    if index // 10 == group:
        print(f"::notice::{label}:{index}:{len(chunks)}:{chunk}")
