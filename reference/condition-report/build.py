import json, re, sys
base = sys.argv[1]          # previous report page, for the shared styles, icons and drawings
ql_path = sys.argv[2]       # question-list.json
out = sys.argv[3]
here = __file__.rsplit("/", 1)[0]
old = open(base).read()
ql = json.load(open(ql_path))

def grab(pat):
    m = re.search(pat, old, re.S)
    assert m, pat
    return m.group(0)

head = old[:old.index("<style>")]
css = old[old.index("<style>") + 7: old.index("</style>")]
helpers = "\n".join([
    grab(r"function esc\(s\) \{[^\n]*\n"),
    grab(r"var LU = \{.*?\n\};\n"),
    grab(r"function I\(name, size, cls\) \{.*?\n\}\n"),
    grab(r"var LOGO = [^\n]*\n"),
    grab(r"var ART = \{.*?\n\};\n"),
    grab(r"function art\(kind, cls\) \{[^\n]*\n"),
    grab(r"var POS2 = \{.*?\};\n"),
    grab(r"var CAR_OUTLINE = .*?</g>';\n"),
    grab(r"function fmtDate\(d\) \{.*?\n\}\n"),
])
extra_css = open(here + "/extra.css").read()
data = {"items": ql["items"], "dealer": ql["dealer"]}
app = open(here + "/app.js").read()

# every example answer must be an option of its check, and every dealer checklist line must point at items in the list
ids = {it["id"]: it for it in ql["items"]}
ex = re.findall(r'(ck_[a-z_]+): \[(.*?)\]\],?\n', app)
for cid, body in ex:
    assert cid in ids, cid
    for opt in re.findall(r'(?:\[|\], )\["([^"]+)"', "[" + body):
        assert opt in ids[cid]["options"], (cid, opt)
for line, src, refs in ql["dealer"]:
    for r in refs:
        assert r in ids, (line, r)

page = (head + "<style>" + css + extra_css + "</style>\n<div id=\"apps\" data-tab=\"all\"></div>\n<script>\n(function () {\n\"use strict\";\n"
        + "var QL = " + json.dumps(data, ensure_ascii=False) + ";\n" + helpers + "\n" + app + "\n})();\n</script>\n")
open(out, "w").write(page)
print("ok", len(page), "examples checked:", len(ex))
