"""Generate synthetic, non-production manual-import documents. No app fixture code is used.

Run with Python containing Pillow and reportlab. Outputs are deterministic and
written beside this script. No chart is tuned using extraction results.
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

OUT = Path(__file__).resolve().parent
FONT_DIR = Path('/System/Library/Fonts/Supplemental')
BLUE, TEAL, ORANGE, PURPLE = '#2467AD', '#138879', '#D77720', '#7551A8'
INK, GRID = '#222B36', '#DCE2E8'

def font(size, bold=False, serif=False):
    name = 'Georgia' if serif else ('Arial Bold' if bold else 'Arial')
    return ImageFont.truetype(str(FONT_DIR / (name + '.ttf')), size)

def label(draw, xy, text, size=30, anchor='mm', bold=False, serif=False):
    draw.text(xy, text, fill=INK, font=font(size, bold, serif), anchor=anchor)

def base(title, size=(1200, 900), serif=False):
    image = Image.new('RGB', size, 'white')
    draw = ImageDraw.Draw(image)
    label(draw, (size[0]/2, 65), title, 43, bold=True, serif=serif)
    return image, draw

def bars(name, title, categories, values, horizontal=False, grid=False,
         size=(1200, 900), colors=None, serif=False):
    image, d = base(title, size, serif)
    w, h = size
    left = 405 if horizontal else 205
    right, top, bottom = w-110, 180, h-215
    lo, hi = (-30, 40) if min(values) < 0 else (0, 50 if max(values)>40 else 40)
    def coord(value):
        return left+(value-lo)/(hi-lo)*(right-left) if horizontal else bottom-(value-lo)/(hi-lo)*(bottom-top)
    ticks = range(lo, hi+1, 10)
    for tick in ticks:
        p = coord(tick)
        if horizontal:
            if grid: d.line((p,top,p,bottom), fill=GRID, width=2)
            label(d, (p,bottom+40), str(tick), 31)
        else:
            if grid: d.line((left,p,right,p), fill=GRID, width=2)
            label(d, (left-30,p), str(tick), 31, anchor='rm')
    zero = coord(0)
    if horizontal:
        d.line((left,bottom,right,bottom), fill=INK, width=3)
        d.line((zero,top,zero,bottom), fill=INK, width=3)
    else:
        d.line((left,top,left,bottom), fill=INK, width=3)
        d.line((left,zero,right,zero), fill=INK, width=3)
    palette = colors or [BLUE, TEAL, ORANGE, PURPLE]
    for i, (category, value) in enumerate(zip(categories,values)):
        if horizontal:
            cy = top+(i+.5)*(bottom-top)/len(values)
            half = min(43,(bottom-top)/len(values)*.27)
            d.rectangle((min(zero,coord(value)),cy-half,max(zero,coord(value)),cy+half),fill=palette[i%len(palette)])
            label(d,(left-30,cy),category,28,anchor='rm')
        else:
            cx = left+(i+.5)*(right-left)/len(values)
            half = (right-left)/len(values)*.25
            d.rectangle((cx-half,min(zero,coord(value)),cx+half,max(zero,coord(value))),fill=palette[i%len(palette)])
            label(d,(cx,bottom+48),category,31)
    label(d,((left+right)/2,h-82),'Hours' if horizontal else 'Category',31)
    if not horizontal: label(d,(left-80,top-45),'Count',29)
    image.save(OUT/name)
    return image

def line(name,title,values,grid=False,size=(1260,900),serif=False):
    image,d = base(title,size,serif)
    w,h=size; left,right,top,bottom=200,w-110,190,h-215
    for tick in range(0,51,10):
        y=bottom-tick/50*(bottom-top)
        if grid: d.line((left,y,right,y),fill=GRID,width=2)
        label(d,(left-30,y),str(tick),31,anchor='rm')
    d.line((left,top,left,bottom,right,bottom),fill=INK,width=3)
    xs=[left+(i+.5)*(right-left)/len(values) for i in range(len(values))]
    points=[(x,bottom-v/50*(bottom-top)) for x,v in zip(xs,values)]
    d.line(points,fill=BLUE,width=6)
    for i,(x,y) in enumerate(points):
        d.ellipse((x-15,y-15,x+15,y+15),fill=BLUE)
        label(d,(x,bottom+48),['Week A','Week B','Week C','Week D'][i],29)
    label(d,((left+right)/2,h-82),'Week',31)
    label(d,(left-70,top-45),'Count',29)
    image.save(OUT/name)

def pie(name,title,categories,values,printed=False,size=(1320,1000),serif=False):
    image,d=base(title,size,serif)
    w,h=size; cx,cy,r=w/2,h*.51,245
    colors=[BLUE,ORANGE,TEAL,PURPLE]
    angle=-90
    for i,(category,value) in enumerate(zip(categories,values)):
        end=angle+value*3.6
        d.pieslice((cx-r,cy-r,cx+r,cy+r),angle,end,fill=colors[i])
        mid=math.radians((angle+end)/2)
        x,y=cx+(r+115)*math.cos(mid),cy+(r+115)*math.sin(mid)
        label(d,(x,y),category,32,serif=serif)
        if printed:
            px,py=cx+r*.58*math.cos(mid),cy+r*.58*math.sin(mid)
            # Dark readable text on a light label patch; geometry stays separate.
            text=str(value)+'%'; box=d.textbbox((px,py),text,font=font(31,True),anchor='mm')
            d.rectangle((box[0]-5,box[1]-4,box[2]+5,box[3]+4),fill='white')
            label(d,(px,py),text,31,bold=True)
        angle=end
    image.save(OUT/name)

def pdf(name,images):
    c=canvas.Canvas(str(OUT/name),pagesize=(720,540),invariant=1)
    c.setTitle('ChartBridge synthetic manual-import test')
    for image in images:
        c.drawImage(ImageReader(image),0,0,width=720,height=540,preserveAspectRatio=True,anchor='c')
        c.showPage()
    c.save()

def main():
    basic=bars('01_vertical_basic.png','Community garden harvest',['Beans','Carrots','Peas'],[20,35,28])
    bars('02_vertical_negative.png','Weekly inventory change',['North','Central','South'],[-20,30,10],colors=[TEAL,BLUE,ORANGE])
    bars('03_vertical_gridlines.png','Library activities',['Reading','Art','Music','Coding'],[15,42,26,34],grid=True,size=(1400,950),serif=True)
    bars('04_horizontal_basic.png','Volunteer hours',['Garden','Library','Shelter'],[15,30,22],horizontal=True)
    bars('05_horizontal_long_labels.png','Community program attendance',['Neighborhood cleanup','After-school tutoring','Public library workshops'],[24,38,17],horizontal=True,grid=True,size=(1600,1000),serif=True)
    bars('06_horizontal_negative.png','Monthly balance change',['January','February','March'],[-20,30,10],horizontal=True)
    line('07_line_basic.png','Weekly trail visitors',[10,25,18,40])
    line('08_line_declining.png','Weekly water use',[45,33,24,12],size=(1380,950),serif=True)
    line('09_line_gridlines.png','Weekly recycling totals',[15,32,22,44],grid=True)
    pie('10_pie_basic.png','Travel to school',['Walking','Bus','Cycling'],[45,30,25])
    pie('11_pie_four_slices.png','Community budget',['Parks','Library','Roads','Arts'],[40,27,21,12],size=(1440,1080),serif=True)
    pie('12_pie_printed_percentages.png','Workshop preferences',['Science','Art','Music'],[50,30,20],printed=True)
    pdf('13_multipage_test.pdf',[basic,Image.open(OUT/'04_horizontal_basic.png')])
    pdf('14_chart_single_page.pdf',[basic])
    image,d=base('Two-series stacked totals and trend',(1320,950))
    for i,(a,b) in enumerate([(80,110),(150,95),(100,170),(180,90)]):
        x=260+i*230
        d.rectangle((x,730-a,x+95,730),fill=BLUE)
        d.rectangle((x,730-a-b,x+95,730-a),fill=ORANGE)
        label(d,(x+45,780),['East','West','North','South'][i],30)
    d.line([(300,560),(530,380),(760,520),(990,330)],fill=PURPLE,width=8)
    label(d,(660,860),'Unsupported: stacked bars with a second-series trend',30)
    image.save(OUT/'15_unsupported_chart.png')
    print('Generated 13 PNG images and two PDF documents in',OUT)

if __name__ == '__main__': main()
