import sys, glob
from playwright.sync_api import sync_playwright
from PIL import Image
D='/private/tmp/claude-610778768/-Users-d111879-Documents-Project-DEMO-Student-Student-mobile-sapp/739b2a61-0815-49ef-9e3b-31ade666ab1c/scratchpad/promo'
names = sys.argv[1:] or ['1_hero','2_explore','3_personal','4_details','5_ai','6_cta']
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width':1080,'height':1920}, device_scale_factor=1)
    for n in names:
        pg.goto(f'file://{D}/{n}.html'); pg.wait_for_load_state('networkidle')
        pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(300)
        pg.screenshot(path=f'{D}/out/{n}.png')
    b.close()
fs=sorted(glob.glob(D+'/out/[1-6]_*.png')); ims=[Image.open(f).convert('RGB') for f in fs]
W=360; c=Image.new('RGB',(W*len(ims)+20*(len(ims)-1),640),'white')
for k,i in enumerate(ims): c.paste(i.resize((W,640)),(k*(W+20),0))
c.save(D+'/preview.png'); print([ (f.split('/')[-1], i.size) for f,i in zip(fs,ims)])
