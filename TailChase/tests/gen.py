import os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
H = os.path.dirname(os.path.abspath(__file__))
files = {}
for dp, _, fs in os.walk(ROOT):
    for f in fs:
        if f.endswith(".luau"):
            p = os.path.join(dp, f)
            files[os.path.relpath(p, ROOT)] = open(p).read()
def lit(s):
    n = 1
    while ("]" + "="*n + "]") in s: n += 1
    return "[" + "="*n + "[" + s + "]" + "="*n + "]"
out = ["local SRC = {}"]
for k, v in files.items():
    out.append("SRC[%r] = %s" % (k, lit(v)))
out.append(open(os.path.join(H, "mock.luau")).read().replace("return M\n", "", 1) if False else "")
open(os.path.join(H, "sources.luau"), "w").write("\n".join(out) + "\nreturn SRC\n")
print(len(files), "fichiers")
