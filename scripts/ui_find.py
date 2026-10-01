"""Prints the centre "x y" of the last on-screen element whose text or content-desc equals argv[1].
"@edit:N" matches the N-th text field (0-based) instead. Reads a uiautomator dump on stdin."""
import re, sys, xml.etree.ElementTree as ET
q = sys.argv[1]
nodes = list(ET.parse(sys.stdin).iter("node"))
if q.startswith("@edit"):
    i = int(q.split(":")[1]) if ":" in q else 0
    fields = [n for n in nodes if n.get("class") == "android.widget.EditText"]
    hits = fields[i:i + 1]
else:
    hits = [n for n in nodes if n.get("text") == q or n.get("content-desc") == q]
if not hits: sys.exit(1)
x1, y1, x2, y2 = map(int, re.findall(r"\d+", hits[-1].get("bounds")))
print((x1 + x2) // 2, (y1 + y2) // 2)
