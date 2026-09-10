from pathlib import Path

src_path=Path('tools/app_ux_polish.py')
src=src_path.read_text(encoding='utf-8')

# Compatibility: current index.html starts renderAll with applyAppearance().
old="s = s.replace('function renderAll(){renderHeader();', onboarding_fn + 'function renderAll(){renderOnboardingGuide();renderHeader();', 1)"
new="""if 'function renderAll(){applyAppearance();renderHeader();' in s:\n    s = s.replace('function renderAll(){applyAppearance();renderHeader();', onboarding_fn + 'function renderAll(){applyAppearance();renderOnboardingGuide();renderHeader();', 1)\nelif 'function renderAll(){renderHeader();' in s:\n    s = s.replace('function renderAll(){renderHeader();', onboarding_fn + 'function renderAll(){renderOnboardingGuide();renderHeader();', 1)\nelse:\n    raise AssertionError('renderAll anchor not found')"""
if old not in src:
    raise SystemExit('Expected renderAll patch statement not found')
src=src.replace(old,new,1)

# Compatibility: the current button label is “Gartenmitte setzen”.
old_button="s = s.replace('<button class=\"btn ghost small\" id=\"openGardenCenter\" type=\"button\">Gartenmitte auf Karte</button>', '', 1)"
new_button="s = s.replace('<button class=\"btn ghost small\" id=\"openGardenCenter\" type=\"button\">Gartenmitte setzen</button>', '', 1)"
if old_button not in src:
    raise SystemExit('Expected openGardenCenter patch statement not found')
src=src.replace(old_button,new_button,1)

exec(compile(src,str(src_path),'exec'),{'__name__':'__main__','__file__':str(src_path)})
print('Focused UX polish completed through compatibility runner')
