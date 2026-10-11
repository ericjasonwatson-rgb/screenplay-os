#!/usr/bin/env python3
"""Draw the original, locally authored frames for The Last Light demo.

Requires Pillow only for regenerating the committed PNGs. No network or AI API.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import math

OUT = Path(__file__).resolve().parents[1] / "assets" / "demo-boards"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1280, 720
INK = (29, 42, 53)
MID = (74, 92, 104)
PAPER = (231, 226, 209)
SEA = (132, 165, 174)
SKY = (192, 204, 200)
WARM = (216, 170, 92)


def line(d, points, width=6, color=INK):
    d.line(points, fill=color, width=width, joint="curve")


def star(d, x, y, r=37):
    points = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * .43
        points.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    d.polygon(points, fill=PAPER, outline=INK, width=5)
    line(d, [(x, y-r), (x, y+r*.37)], 3, MID)


def water(d, horizon=390):
    d.rectangle((0, 0, W, horizon), fill=SKY)
    d.rectangle((0, horizon, W, H), fill=SEA)
    line(d, [(0, horizon), (W, horizon)], 5)
    for yy in range(horizon+35, H, 52):
        for xx in range((yy//52)%2*55, W, 185):
            line(d, [(xx, yy), (xx+85, yy-4), (xx+131, yy)], 3, MID)


def pier(d, x=110, y=470):
    d.polygon([(x, y), (x+570, y-55), (x+720, y+15), (x+130, H), (x, H)], fill=PAPER, outline=INK, width=6)
    for xx in range(x+60, x+600, 120):
        line(d, [(xx, y-5), (xx+55, H)], 3, MID)
    for xx in (x+90, x+500):
        line(d, [(xx, y-12), (xx, y-115)], 9)


def lamp(d, x=850, y=155, lit=False, scale=1):
    s=scale
    if lit:
        d.ellipse((x-100*s,y-90*s,x+100*s,y+90*s), fill=(235,210,141))
    d.polygon([(x-37*s,y+22*s),(x-47*s,y+115*s),(x+47*s,y+115*s),(x+37*s,y+22*s)], fill=(58,76,82), outline=INK, width=5)
    d.rectangle((x-31*s,y+27*s,x+31*s,y+92*s), fill=(239,205,129) if lit else (151,177,174), outline=INK, width=4)
    line(d, [(x-55*s,y+22*s),(x,y-23*s),(x+55*s,y+22*s)], 6)
    line(d, [(x,y+115*s),(x,y+490*s)], 15)
    if lit:
        for dx in (-130,-75,75,130): line(d,[(x+dx*s,y-50*s),(x+dx*1.3*s,y-90*s)],3,WARM)


def ferry(d, x=670, y=355, scale=1):
    s=scale
    d.polygon([(x-250*s,y),(x+265*s,y),(x+185*s,y+125*s),(x-170*s,y+125*s)], fill=PAPER, outline=INK, width=7)
    d.rectangle((x-125*s,y-135*s,x+145*s,y), fill=(203,206,193), outline=INK, width=6)
    for xx in (-85,0,85): d.rectangle((x+(xx-30)*s,y-97*s,x+(xx+30)*s,y-38*s), fill=SKY, outline=INK, width=4)
    line(d,[(x-20*s,y-135*s),(x-20*s,y-190*s)],7)


def person(d, x, y, scale=1, facing=1, coat=(75, 92, 104)):
    s=scale
    d.ellipse((x-27*s,y-95*s,x+27*s,y-35*s), fill=PAPER, outline=INK, width=5)
    d.polygon([(x-24*s,y-36*s),(x+25*s,y-36*s),(x+51*s,y+145*s),(x-53*s,y+145*s)],fill=coat,outline=INK,width=6)
    line(d,[(x-21*s,y+144*s),(x-27*s,y+215*s)],6)
    line(d,[(x+19*s,y+144*s),(x+28*s,y+215*s)],6)
    line(d,[(x+21*s,y+2*s),(x+facing*77*s,y+68*s)],6)
    line(d,[(x-25*s,y+7*s),(x-facing*58*s,y+72*s)],6)
    line(d,[(x+facing*25*s,y-60*s),(x+facing*28*s,y-60*s)],3)


def key(d,x,y,s=1):
    d.ellipse((x-25*s,y-25*s,x+25*s,y+25*s),outline=WARM,width=max(3,int(10*s)))
    line(d,[(x+24*s,y),(x+105*s,y)],max(3,int(11*s)),WARM)
    line(d,[(x+87*s,y),(x+87*s,y+25*s),(x+104*s,y+25*s)],max(3,int(8*s)),WARM)


def room(d):
    d.rectangle((0,0,W,H),fill=(185,196,191))
    d.polygon([(0,0),(285,120),(285,H),(0,H)],fill=(95,112,117))
    d.polygon([(W,0),(1000,110),(1000,H),(W,H)],fill=(95,112,117))
    d.rectangle((330,70,950,535),fill=INK)
    d.rectangle((346,86,934,519),fill=SKY)
    d.rectangle((346,340,934,519),fill=SEA)
    line(d,[(640,80),(640,522)],8)
    line(d,[(338,350),(941,350)],6)
    d.rectangle((0,620,W,H),fill=(89,103,103))


def draw(i):
    im=Image.new('RGB',(W,H),PAPER); d=ImageDraw.Draw(im)
    if i<=4:
        room(d)
        if i==1: person(d,790,435,1.1,-1); star(d,880,540,28); lamp(d,500,243,True,.29)
        elif i==2: ferry(d,650,388,.32); lamp(d,780,290,True,.28); person(d,260,440,1.35,1)
        elif i==3: person(d,625,365,1.9,-1); star(d,870,525,35)
        else: person(d,430,405,1.35,1); person(d,800,405,1.35,-1,coat=(111,100,89)); star(d,610,515,32)
    elif i<=8:
        water(d)
        pier(d)
        if i==5: ferry(d,970,392,.45); lamp(d,160,135,False,.52); person(d,425,356,1.05,1)
        elif i==6: person(d,440,320,1.55,1); star(d,625,402,49); ferry(d,1050,390,.28)
        elif i==7: person(d,520,310,1.85,1); star(d,680,415,36)
        else: person(d,400,327,1.45,1); ferry(d,940,365,.53); lamp(d,110,170,False,.45)
    else:
        water(d,415)
        d.polygon([(0,640),(W,510),(W,H),(0,H)],fill=(196,190,169),outline=INK,width=6)
        lamp(d,890,180, i==12, .75)
        if i==9: person(d,350,330,1.2,1); person(d,615,340,1.1,-1,coat=(111,100,89))
        elif i==10: person(d,335,340,1.35,1); person(d,650,340,1.35,-1,coat=(111,100,89)); key(d,600,365,.75)
        elif i==11: person(d,540,310,1.8,-1,coat=(111,100,89)); key(d,650,360,1)
        else: person(d,380,340,1.3,1); person(d,670,340,1.3,-1,coat=(111,100,89)); key(d,770,435,.6)
    # Pencil-like frame and a few short hatching lines, all authored geometry.
    d.rectangle((18,18,W-19,H-19),outline=INK,width=6)
    for j in range(11):
        xx=36+j*103
        line(d,[(xx,H-42),(xx+32,H-49)],2,MID)
    im.save(OUT/f'{i:02d}.png',optimize=True)


if __name__=='__main__':
    for i in range(1,13): draw(i)
    print(f'Drew 12 original frames in {OUT}')
