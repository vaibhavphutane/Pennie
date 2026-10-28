#!/usr/bin/env python3
"""Read-only mounted installer inspection; never launches the installer."""
import argparse, json, pathlib, plistlib, subprocess, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('installer', type=pathlib.Path, help='Path to the downloaded Grammarly DMG')
source = str(parser.parse_args().installer.expanduser().resolve(strict=True))
mount = tempfile.mkdtemp(prefix='writedock-installer-')
subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,source],check=True,stdout=subprocess.DEVNULL)
try:
    app = next(pathlib.Path(mount).glob('*.app'))
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    summary = {k:info.get(k) for k in ['CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion','CFBundleExecutable']}
    summary['source'] = source
    pathlib.Path('docs/evidence/download-metadata.json').write_text(json.dumps(summary,indent=2))
    framework = app/'Contents/Frameworks/ProjectLlamaContent.framework/Versions/A/Frameworks/GRAccessibilityKit.framework/Versions/A/GRAccessibilityKit'
    req = [
      {'name':'open_binary','arguments':{'path':str(framework),'provider_id':'hopper'}},
      {'name':'inspect_plist','arguments':{'path':str(app/'Contents/Info.plist')}},
      {'name':'search_procedures','arguments':{'pattern':'selectedText'}},
      {'name':'procedure_pseudo_code','arguments':{'procedure':'_$sSo14AXUIElementRefa18GRAccessibilityKitE15setSelectedTextyySSAC18AccessibilityErrorOYKF'}},
      {'name':'procedure_pseudo_code','arguments':{'procedure':'_$sSo14AXUIElementRefa18GRAccessibilityKitE34getSelectedTextWithBrowserFallbackSSyAC18AccessibilityErrorOYKF'}},
      {'name':'close_binary','arguments':{}}]
    path = pathlib.Path('docs/evidence/download-requests.json'); path.write_text(json.dumps(req,indent=2))
    subprocess.run(['python3','scripts/rea_mcp.py',str(path)],check=True)
    print(json.dumps(summary))
finally:
    subprocess.run(['hdiutil','detach',mount],check=True,stdout=subprocess.DEVNULL)
    pathlib.Path(mount).rmdir()
