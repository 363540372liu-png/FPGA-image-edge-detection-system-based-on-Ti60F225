from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "sim" / "split_hdmi_readout.ppm"
output = ROOT / "sim" / "split_panel_landscape_preview.png"

# Model the accepted Waveshare behavior: stretch the 640x480 HDMI raster to
# the native 480x640 portrait panel, then view the panel after a clockwise
# 90-degree physical rotation.  NEAREST matches the coordinate model used by
# the RTL test and avoids inventing interpolation detail.
hdmi = Image.open(source).convert("RGB")
portrait = hdmi.resize((480, 640), Image.Resampling.NEAREST)
landscape = portrait.transpose(Image.Transpose.ROTATE_270)
landscape.save(output)

if landscape.size != (640, 480):
    raise SystemExit(f"unexpected preview size {landscape.size}")

print(f"SPLIT_PREVIEW_PASS {output} size={landscape.size}")
