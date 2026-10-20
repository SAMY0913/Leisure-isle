
import re,sys
src=open(r"D:/休闲小岛幻境/游戏工程/scripts/main.gd",encoding="utf-8").read().split("
")
depth=0
stack=[]
in_str=None
def strip_line(line):
    return line  # simple: line-based balance ignoring quoted braces
for i,line in enumerate(src,1):
    # remove quoted segments naively
    s=""
    j=0
    while j<len(line):
        c=line[j]
        if in_str:
            if c=="\\": j+=2; continue
            if c==in_str: in_str=None
            j+=1; continue
        if c=='"':
            in_str='"'; j+=1; continue
        if c=="'":
            in_str="'"; j+=1; continue
        s+=c; j+=1
    for c in s:
        if c=="{":
            depth+=1; stack.append(i)
        elif c=="}":
            depth-=1
            if stack: stack.pop()
            if depth<0:
                print("NEG at line",i, line.strip())
print("final depth",depth,"stack tail",stack[-5:])
