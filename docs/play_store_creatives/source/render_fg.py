from playwright.sync_api import sync_playwright
from PIL import Image
D='/private/tmp/claude-610778768/-Users-d111879-Documents-Project-DEMO-Student-Student-mobile-sapp/739b2a61-0815-49ef-9e3b-31ade666ab1c/scratchpad/promo'
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':1024,'height':500},device_scale_factor=1)
    for n in ['fg1_brand','fg2_ai','fg3_paths']:
        pg.goto(f'file://{D}/{n}.html'); pg.wait_for_load_state('networkidle'); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(300)
        pg.screenshot(path=f'{D}/out/{n}.png')
    b.close()
ims=[Image.open(f'{D}/out/{n}.png').convert('RGB') for n in ['fg1_brand','fg2_ai','fg3_paths']]
c=Image.new('RGB',(1024,1540),'white')
for i,im in enumerate(ims): c.paste(im,(0,i*520))
c.save(D+'/fgprev.png')
