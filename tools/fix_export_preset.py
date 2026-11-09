import re

p = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\export_presets.cfg"
with open(p, "r", encoding="utf-8", errors="replace") as f:
    lines = f.read().splitlines()

out = []
for ln in lines:
    if ln.startswith("application/file_version="):
        ln = 'application/file_version="1.10.0.0"'
    elif ln.startswith("application/product_version="):
        ln = 'application/product_version="1.10.0.0"'
    elif ln.startswith("application/product_name="):
        ln = 'application/product_name="Nebesnyi Horizont"'
    elif ln.startswith("application/file_description="):
        ln = 'application/file_description="Nebesnyi Horizont - FPV drone simulator"'
    out.append(ln)

with open(p, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print("updated", p)
