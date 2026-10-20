from PIL import Image
im=Image.open(r'D:/休闲小岛幻境/开发产物/shots/01_noon.png')
c=im.crop((0,0,760,300)).resize((1140,450), Image.LANCZOS)
c.save(r'D:/休闲小岛幻境/开发产物/shots/_crop_noon_sky.png')
im2=Image.open(r'D:/休闲小岛幻境/开发产物/shots/02_sunset_sky.png')
print(im.size, im2.size)