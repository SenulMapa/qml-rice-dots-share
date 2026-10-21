#!/bin/bash
# Run ON macOS:  bash /Volumes/OC-SAFE/mac-icons/export-icons.sh
# Renders every app's icon exactly as the Dock shows it (NSWorkspace, includes Assets.car icons)
# to 1024px PNGs on the USB stick, plus the Dock's current app order.
set -euo pipefail
OUT="/Volumes/OC-SAFE/mac-icons/export"; mkdir -p "$OUT"
/usr/bin/osascript -l JavaScript - "$OUT" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
  const out = argv[0], fm = $.NSFileManager.defaultManager, ws = $.NSWorkspace.sharedWorkspace;
  const dirs = ['/Applications', '/Applications/Utilities', '/System/Applications', '/System/Applications/Utilities',
                '/System/Library/CoreServices', ObjC.unwrap($.NSHomeDirectory()) + '/Applications'];
  let n = 0;
  dirs.forEach(d => {
    const items = fm.contentsOfDirectoryAtPathError(d, null);
    if (!items || items.isNil()) return;
    ObjC.deepUnwrap(items).filter(f => f.endsWith('.app')).forEach(f => {
      const p = d + '/' + f, icon = ws.iconForFile(p);
      icon.setSize($.NSMakeSize(1024, 1024));
      const cg = icon.CGImageForProposedRectContextHints(null, null, null);
      const bmp = $.NSBitmapImageRep.alloc.initWithCGImage(cg);
      bmp.setSize($.NSMakeSize(1024, 1024));
      const png = bmp.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $());
      const bundle = $.NSBundle.bundleWithPath(p);
      const bid = (bundle && !bundle.isNil() && bundle.bundleIdentifier && !bundle.bundleIdentifier.isNil()) ? ObjC.unwrap(bundle.bundleIdentifier) : '';
      const name = f.replace(/\.app$/, '');
      png.writeToFileAtomically(out + '/' + name + '.png', true);
      $(JSON.stringify({ name: name, path: p, bundleId: bid })).writeToFileAtomicallyEncodingError(out + '/' + name + '.json', true, $.NSUTF8StringEncoding, null);
      n++;
    });
  });
  return 'exported ' + n + ' icons to ' + out;
}
JXA
defaults read com.apple.dock persistent-apps 2>/dev/null | grep -E '"_CFURLString"|file-label' > "$OUT/dock-order.txt" || true
echo "Dock order saved. Now reboot into Linux and tell Claude."
