from pathlib import Path

src_path=Path('tools/app_ux_polish.py')
src=src_path.read_text(encoding='utf-8')
old="s = s.replace('function renderAll(){renderHeader();', onboarding_fn + 'function renderAll(){renderOnboardingGuide();renderHeader();', 1)"
new="""if 'function renderAll(){applyAppearance();renderHeader();' in s:\n    s = s.replace('function renderAll(){applyAppearance();renderHeader();', onboarding_fn + 'function renderAll(){applyAppearance();renderOnboardingGuide();renderHeader();', 1)\nelse:\n    s = s.replace('function renderAll(){renderHeader();', onboarding_fn + 'function renderAll(){renderOnboardingGuide();renderHeader();', 1)"""
if old not in src:
    raise SystemExit('Expected renderAll patch statement not found')
src=src.replace(old,new,1)
exec(compile(src,str(src_path),'exec'),{'__name__':'__main__','__file__':str(src_path)})
print('Focused UX polish completed through compatibility runner')
