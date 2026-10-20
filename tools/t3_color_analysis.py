import numpy as np
from PIL import Image
base = r'D:/休闲小岛幻境/开发产物/shots6/t3/'
q1 = np.asarray(Image.open(base+'t3_q1_view.png').convert('RGB')).astype(np.float64)/255.0
q2 = np.asarray(Image.open(base+'t3_q2_view.png').convert('RGB')).astype(np.float64)/255.0
q4 = np.asarray(Image.open(base+'t3_q4_view.png').convert('RGB')).astype(np.float64)/255.0
def srgb(x): return np.where(x<=0.0031308, 12.92*x, 1.055*np.power(np.clip(x,0,1),1/2.4)-0.055)
def lin(x): return np.where(x<=0.04045, x/12.92, np.power((np.clip(x,0,1)+0.055)/1.055,2.4))
hs=[(400,400),(1200,300),(2000,200),(800,1000),(1500,1200),(300,1300)]
for name,img in [('q2',q2),('q4',q4)]:
    print('== compare q1 vs', name)
    for (x,y) in hs:
        a=q1[y,x]; b=img[y,x]
        print('  px',(x,y),'q1',np.round(a,3),name,np.round(b,3),'srgb(q1)',np.round(srgb(a),3),'srgb2(q1)',np.round(srgb(srgb(a)),3),'lin(name)',np.round(lin(b),3))
for name,img in [('q2',q2),('q4',q4)]:
    a=q1[:250].reshape(-1,3); b=img[:250].reshape(-1,3)
    print('sky', name)
    for label,pred in [('srgb(q1)',srgb(a)),('srgb2(q1)',srgb(srgb(a))),('lin(q1)',lin(a))]:
        print('   ',label,'meanabs',round(float(np.abs(pred-b).mean()),4))
    print('    direct q1 meanabs', round(float(np.abs(a-b).mean()),4))
# 全图：q2 与 srgb2(q1) 的线性拟合
a=q1.reshape(-1,3); b=q2.reshape(-1,3)
pred=srgb(srgb(a))
print('ALL q2 vs srgb2(q1) meanabs', round(float(np.abs(pred-b).mean()),4), 'corr', round(float(np.corrcoef(pred.ravel(),b.ravel())[0,1]),4))
print('ALL q2 vs q1 direct meanabs', round(float(np.abs(a-b).mean()),4))
# 若 q2 = srgb2(q1)，则 lin(q2) 应 ≈ srgb(q1)
pred2=srgb(lin(b))
print('ALL srgb(lin(q2)) vs q1 meanabs', round(float(np.abs(pred2-a).mean()),4))