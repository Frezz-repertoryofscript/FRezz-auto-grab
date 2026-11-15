#!/usr/bin/env python3
"""Génère TailChase.rbxlx (place Roblox XML) à partir de default.project.json, sans Rojo.
Gère : $className, $path (fichier .luau / dossier), $properties (nombres, booléens, Color3 [r,g,b]).
Conventions Rojo : *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript,
dossier avec init(.server|.client).luau -> le script porte les autres fichiers comme enfants, sinon Folder.
Usage : python3 tools/build_rbxlx.py  (sortie : TailChase.rbxlx à la racine du projet)
"""
import json, os, sys
from xml.sax.saxutils import escape

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ref = [0]


def next_ref():
    ref[0] += 1
    return "RBX%08X" % ref[0]


def cdata(s):
    return "<![CDATA[" + s.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def prop_xml(name, value):
    if isinstance(value, bool):
        return '<bool name="%s">%s</bool>' % (name, "true" if value else "false")
    if isinstance(value, (int, float)):
        return '<float name="%s">%s</float>' % (name, value)
    if isinstance(value, list) and len(value) == 3:
        return '<Color3 name="%s"><R>%s</R><G>%s</G><B>%s</B></Color3>' % (name, *value)
    if isinstance(value, str):
        return '<string name="%s">%s</string>' % (name, escape(value))
    raise ValueError("propriété non gérée : %s" % name)


def item(cls, name, props=None, source=None, children=()):
    out = ['<Item class="%s" referent="%s"><Properties>' % (cls, next_ref())]
    out.append('<string name="Name">%s</string>' % escape(name))
    if source is not None:
        out.append('<ProtectedString name="Source">%s</ProtectedString>' % cdata(source))
    for k, v in (props or {}).items():
        out.append(prop_xml(k, v))
    out.append("</Properties>")
    out.extend(children)
    out.append("</Item>")
    return "".join(out)


def script_class(fname):
    if fname.endswith(".server.luau"):
        return "Script", fname[: -len(".server.luau")]
    if fname.endswith(".client.luau"):
        return "LocalScript", fname[: -len(".client.luau")]
    return "ModuleScript", fname[: -len(".luau")]


def from_path(path, name=None):
    """Retourne la liste des Items XML pour un chemin (fichier ou dossier)."""
    if os.path.isfile(path):
        cls, base = script_class(os.path.basename(path))
        return [item(cls, name or base, source=open(path, encoding="utf-8").read())]
    entries = sorted(os.listdir(path))
    init = next((e for e in entries if e in ("init.luau", "init.server.luau", "init.client.luau")), None)
    children = []
    for e in entries:
        if e == init or e.startswith("."):
            continue
        p = os.path.join(path, e)
        if os.path.isdir(p) or e.endswith(".luau"):
            children.extend(from_path(p))
    dname = name or os.path.basename(path)
    if init:
        cls, _ = script_class(init)
        return [item(cls, dname, source=open(os.path.join(path, init), encoding="utf-8").read(), children=children)]
    return [item("Folder", dname, children=children)]


def node(name, spec):
    children = []
    if "$path" in spec:
        p = os.path.join(ROOT, spec["$path"])
        if "$className" not in spec:
            got = from_path(p, name)
            if os.path.isfile(p):
                return got[0]
            # dossier mappé sur un service / conteneur existant : on garde ses enfants
            entries = from_path(p, name)[0]
            return entries
        children.extend(from_path(p) if os.path.isdir(p) else from_path(p))
    for k, v in spec.items():
        if not k.startswith("$"):
            children.append(node(k, v))
    cls = spec.get("$className", name)
    return item(cls, name, props=spec.get("$properties"), children=children)


def service(name, spec):
    """Service de premier niveau : ses enfants viennent de $path (contenu du dossier) et des clés."""
    children = []
    if "$path" in spec:
        p = os.path.join(ROOT, spec["$path"])
        for e in sorted(os.listdir(p)):
            if e.startswith("."):
                continue
            children.extend(from_path(os.path.join(p, e)))
    for k, v in spec.items():
        if k.startswith("$"):
            continue
        if "$path" in v and "$className" not in v and os.path.isdir(os.path.join(ROOT, v["$path"])) and k in ("StarterPlayerScripts", "StarterCharacterScripts"):
            # conteneur existant (StarterPlayerScripts) rempli par un dossier
            sub = []
            p = os.path.join(ROOT, v["$path"])
            for e in sorted(os.listdir(p)):
                if not e.startswith("."):
                    sub.extend(from_path(os.path.join(p, e)))
            children.append(item(k, k, props=v.get("$properties"), children=sub))
        else:
            children.append(node(k, v))
    return item(spec.get("$className", name), name, props=spec.get("$properties"), children=children)


def main():
    project = json.load(open(os.path.join(ROOT, "default.project.json"), encoding="utf-8"))
    tree = project["tree"]
    items = [service(k, v) for k, v in tree.items() if not k.startswith("$")]
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           + "".join(items) + "</roblox>")
    out = os.path.join(ROOT, sys.argv[1] if len(sys.argv) > 1 else "TailChase.rbxlx")
    open(out, "w", encoding="utf-8").write(xml)
    print("écrit", out, len(xml) // 1024, "Ko,", ref[0], "instances")


if __name__ == "__main__":
    main()
