"""(From github.com/chuspeeism/iphone-duo, MIT: LICENSE-iphone-duo.) Prepare the Apple reference assets locally; they are not part of the MIT-licensed source."""

from pathlib import Path
from shutil import copyfile
from urllib.request import urlretrieve
from zipfile import ZipFile

from pxr import Sdf, Usd


import os
# (where they go: DUO_ASSETS, out of the repository: Apple's, not ours to keep)
assets = Path(os.environ.get("DUO_ASSETS", Path(__file__).resolve().parent / "assets"))
textures = assets / "textures"
ui = assets / "ui"
textures.mkdir(parents=True, exist_ok=True)
ui.mkdir(parents=True, exist_ok=True)

model = assets / "iPhone_Duo_Star_White.usdz"
model_url = "https://www.apple.com/105/media/us/iphone-duo/2026/9305e4b9-72d9-4c05-9381-b572adadd5e5/ar/iPhone_Duo_e-sim_Star-White_Variant.usdz"
if not model.exists():
    print("Downloading the Apple reference model...", flush=True)
    urlretrieve(model_url, model)

with ZipFile(model) as archive:
    for name in archive.namelist():
        if Path(name).suffix.lower() in {".png", ".jpg", ".jpeg", ".avif"}:
            (textures / Path(name).name).write_bytes(archive.read(name))

print("Preparing the unfolded pose...", flush=True)
stage = Usd.Stage.Open(str(model))
stage.GetDefaultPrim().GetVariantSet("Pose").SetVariantSelection("Landscape")
flattened = Usd.Stage.Open(stage.Flatten())
for prim in flattened.Traverse():
    for attribute in prim.GetAttributes():
        value = attribute.Get()
        if isinstance(value, Sdf.AssetPath) and value.path:
            # Flattening resolves USDZ references to package paths; use local texture paths for the browser.
            filename = Path(value.path.split("[")[-1].rstrip("]")).name
            attribute.Set(Sdf.AssetPath(f"textures/{filename}"))
flattened.GetRootLayer().Export(str(assets / "iPhone_Duo_Render.usdc"))

copyfile(textures / "bRLlvSMXjHGTFMA.avif", ui / "wallpaper-inner.avif")

clock_base = "https://www.apple.com/v/iphone-duo/a/static/uploads/dIFKSKvliUSYOBw/MszYeqEKDgnBqxc/CRqwzvoYesuhNwK"
hig_base = "https://developer.apple.com/tutorials/images/com.apple.HIG"
ui_sources = {
    "clock-inner.avif": f"{clock_base}/lockscreen_ui_inner-wallpaper_png.avif",
    "clock-outer.avif": f"{clock_base}/lockscreen_ui_outer-wallpaper_png.avif",
    "launcher-inner.png": f"{hig_base}/designing-for-iphone-hero-inside@2x.png",
    "launcher-outer.png": f"{hig_base}/designing-for-iphone-hero-outside@2x.png",
}
for filename, url in ui_sources.items():
    print(f"Downloading {filename}...", flush=True)
    urlretrieve(url, ui / filename)

print("Assets ready. Run: python3 -m http.server 8766 --bind 127.0.0.1")
