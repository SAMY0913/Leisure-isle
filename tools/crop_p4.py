
from PIL import Image
import os
SH=r"D:\休闲小岛幻境\开发产物\shots"
im=Image.open(os.path.join(SH,"03_flowers_close.png"))
im.crop((520,300,780,540)).resize((1040,960), Image.LANCZOS).save(os.path.join(SH,"_crop_bird1.png"))
print("ok")
