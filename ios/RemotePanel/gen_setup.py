# -*- coding: utf-8 -*-
path = r"D:\Myproject\RemotePanel-handoff\ios\RemotePanel\setup_page.html"
data = open(path, encoding="utf-8").read().replace("\r", "")
lines = ["static NSString *RPSetupHTML(void) {", "    return [NSString stringWithUTF8String:"]
for line in data.split("\n"):
    esc = line.replace("\\", "\\\\").replace('"', '\\"')
    lines.append('        "%s\\n"' % esc)
lines.append("    ];")
lines.append("}")
out = r"D:\Myproject\RemotePanel-handoff\ios\RemotePanel\setup_html.inc"
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(len(lines))
