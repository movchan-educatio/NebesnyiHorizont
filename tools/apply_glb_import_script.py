"""Assign the GLB material post-import hook to a folder of .glb assets.

Usage:
    python tools/apply_glb_import_script.py Assets/Drones/ua_norm
    python tools/apply_glb_import_script.py Assets/frontline --script \
        res://scripts/tools/glb_material_post_import.gd

The matching .import files are backed up once as *.import.bak-material before
the `import_script/path` field is changed.  Run Godot with --import afterward
(or reimport the folder from the editor).
"""
from __future__ import annotations

import argparse
import pathlib
import shutil

DEFAULT_SCRIPT = "res://scripts/tools/glb_material_post_import.gd"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=pathlib.Path)
    parser.add_argument("--script", default=DEFAULT_SCRIPT)
    args = parser.parse_args()

    imports = sorted(args.folder.rglob("*.glb.import"))
    if not imports:
        print("No .glb.import files found in", args.folder)
        return 1
    changed = 0
    for path in imports:
        text = path.read_text(encoding="utf-8")
        if f'import_script/path="{args.script}"' in text:
            continue
        backup = path.with_suffix(path.suffix + ".bak-material")
        if not backup.exists():
            shutil.copy2(path, backup)
        text = text.replace('import_script/path=""',
                            f'import_script/path="{args.script}"')
        # If a different custom script was set, replace it too.
        lines = []
        for line in text.splitlines():
            if line.startswith("import_script/path="):
                line = f'import_script/path="{args.script}"'
            lines.append(line)
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        changed += 1
    print(f"Updated {changed}/{len(imports)} GLB import files in {args.folder}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
