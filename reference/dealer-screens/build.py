"""Build the V1 inspected-car screens page from the condition report page (its styles, icons, drawings and example data).
usage: python3 build.py ../condition-report/condition-report.html ../condition-report/app.js dealer-screens.html
"""
import re, sys
src, appjs, out = sys.argv[1:4]
here = __file__.rsplit("/", 1)[0] if "/" in __file__ else "."
page = open(src).read()
head = page[:page.index("<style>")].replace("<title>Bidbus Condition Report</title>", "<title>Inspected Car Screens</title>")
css = page[page.index("<style>") + 7: page.index("</style>")]
script = page[page.index("<script>") + 8: page.rindex("</script>")]
# the condition report page's own script: data, helpers and app; keep it and add the V1 screens inside the same scope
body_start = script.index('"use strict";') + len('"use strict";')
end = script.rindex("})();")
v1 = open(here + "/v1.js").read()
script2 = script[:end] + "\n" + v1 + "\n" + script[end:]
# the dealer app styles are scoped to #apps; give the V1 screens the same styles
scoped = "\n".join(r.replace("#apps", "#v1") for r in re.findall(r"[^{}]*#apps[^{}]*\{[^}]*\}", css) if "data-tab" not in r and ".dcard" not in r)
html = (head + "<style>" + css + scoped + "\n" + open(here + "/v1.css").read() + "</style>\n<div id=\"apps\"></div><div id=\"v1\"></div>\n<script>" + script2 + "</script>\n")
open(out, "w").write(html)
print("ok", len(html))
