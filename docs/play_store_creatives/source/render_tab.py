import sys
from playwright.sync_api import sync_playwright
from PIL import Image
D='/private/tmp/claude-610778768/-Users-d111879-Documents-Project-DEMO-Student-Student-mobile-sapp/739b2a61-0815-49ef-9e3b-31ade666ab1c/scratchpad/promo'
N=sys.argv[1:] or ['t1_hero','t2_explore','t3_personal','t4_details','t5_ai','t6_cta']
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':1920,'height':1080},device_scale_factor=1.5)
    for n in N:
        pg.goto(f'file://{D}/{n}.html'); pg.wait_for_load_state('networkidle'); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(300)
        pg.screenshot(path=f'{D}/out/{n}.png')
    b.close()
ims=[Image.open(f'{D}/out/{n}.png').convert('RGB') for n in N]
print(ims[0].size)
c=Image.new('RGB',(1940,1640),'white')
for i,im in enumerate(ims): c.paste(im.resize((960,540)),((i%2)*980,(i//2)*550))
c.save(D+'/tabprev.png')
