#!/usr/bin/env python3
"""Turn a folder of diagram sources into one page with PIA's look, so nobody draws or styles by hand.

    diagram.py page <folder> "<title>" "<one-line summary>"
        Write <folder>/page.html from the folder's files, in name order, and print its path:
        - *.mmd   a Mermaid diagram. `%% title: …` and `%% caption: …` lines name it. On flowcharts,
                  state diagrams and schemas, `class <ids> changed` marks what changes and
                  `class <ids> removed` what goes away.
        - *.tsv   the code table: step, path, line, what it does, decision, state. One row per line,
                  no header. Paths in the repo's pushed history link to GitHub at that commit.

The page is always dark. The colours live here and only here: two neutrals and the owl's indigo.
"""
import html
import os
import re
import subprocess
import sys

BG = "#17181A"
BOX = "#2A2C30"
LINE = "#D7D9DC"
MUTED = "#9A9EA5"
OWL = "#3D3F9E"
OWL_LIGHT = "#8D92F0"
FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"

THEME = f"""---
config:
  theme: base
  themeVariables:
    darkMode: true
    fontFamily: "{FONT}"
    background: "{BG}"
    mainBkg: "{BOX}"
    primaryColor: "{BOX}"
    primaryTextColor: "{LINE}"
    primaryBorderColor: "{MUTED}"
    secondaryColor: "{BOX}"
    secondaryTextColor: "{LINE}"
    secondaryBorderColor: "{MUTED}"
    tertiaryColor: "{BG}"
    tertiaryTextColor: "{LINE}"
    tertiaryBorderColor: "{MUTED}"
    lineColor: "{LINE}"
    textColor: "{LINE}"
    titleColor: "{LINE}"
    nodeBorder: "{MUTED}"
    clusterBkg: "{BG}"
    clusterBorder: "{MUTED}"
    edgeLabelBackground: "{BG}"
    actorBkg: "{BOX}"
    actorBorder: "{MUTED}"
    actorTextColor: "{LINE}"
    actorLineColor: "{MUTED}"
    signalColor: "{LINE}"
    signalTextColor: "{LINE}"
    labelBoxBkgColor: "{BOX}"
    labelBoxBorderColor: "{MUTED}"
    labelTextColor: "{LINE}"
    loopTextColor: "{LINE}"
    noteBkgColor: "{BOX}"
    noteBorderColor: "{OWL_LIGHT}"
    noteTextColor: "{LINE}"
    attributeBackgroundColorOdd: "{BOX}"
    attributeBackgroundColorEven: "{BG}"
---
"""

# A schema's rows are painted one by one, so a fill there leaves every other row unreadable.
CLASSES = {
    "fill": f"""
classDef changed fill:{OWL},stroke:{OWL_LIGHT},color:#FFFFFF
classDef removed fill:{BG},stroke:{MUTED},color:{MUTED},stroke-dasharray:5 4""",
    "stroke": f"""
classDef changed stroke:{OWL_LIGHT},stroke-width:3px
classDef removed stroke:{MUTED},stroke-dasharray:5 4""",
}

STYLE = f"""
:root{{color-scheme:dark}}
body{{background:{BG};color:{LINE};font-family:{FONT};font-size:16px;line-height:1.5}}
.wrap{{max-width:1000px;margin:0 auto;padding-block:32px 56px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));display:grid;gap:32px}}
header,figure{{display:grid;gap:8px;margin:0;min-width:0}}
h1{{font-size:clamp(26px,4vw,34px);line-height:1.15;margin:0;text-wrap:balance}}
h2{{font-size:19px;line-height:1.3;margin:0;text-wrap:balance}}
header p,figcaption{{margin:0;max-width:72ch;color:{MUTED}}}
figcaption{{font-size:14.5px}}
.scroll{{overflow-x:auto;background:{BOX};border-radius:8px}}
pre.mermaid{{margin:0;padding:16px;min-width:640px;text-align:center;background:{BG};border:1px solid {BOX};border-radius:8px}}
table{{border-collapse:collapse;width:100%;font-size:14.5px}}
td{{padding:10px 12px;vertical-align:top}}
tr+tr td{{border-top:1px solid {BG}}}
code{{font-family:ui-monospace,Menlo,monospace;font-size:13.5px;overflow-wrap:anywhere}}
a{{color:{LINE};text-underline-offset:2px}}
.changed .nodeLabel,.changed .nodeLabel p{{color:#FFFFFF}}
.removed .nodeLabel,.removed .nodeLabel p{{color:{MUTED}}}
"""


def git(root, *args):
    done = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else ""


def github(root):
    """The repo's web address and a pushed commit, or nothing when there isn't one."""
    match = re.search(r"github\.com[:/](.+?)(?:\.git)?$", git(root, "remote", "get-url", "origin"))
    upstream = git(root, "merge-base", "HEAD", "@{upstream}") or git(root, "rev-parse", "origin/HEAD")
    return (f"https://github.com/{match.group(1)}", upstream) if match and upstream else None


def code_table(path, root):
    remote = github(root)
    rows = []
    for line in open(path, encoding="utf-8").read().splitlines():
        step, file, number, what, decision, state = (line.split("\t") + [""] * 6)[:6]
        label = html.escape(f"{file}:{number}" if number else file)
        cell = f"<code>{label}</code>"
        if remote and git(root, "ls-tree", remote[1], "--", file):
            anchor = f"#L{number}" if number else ""
            cell = f'<a href="{remote[0]}/blob/{remote[1]}/{file}{anchor}">{cell}</a>'
        cells = [html.escape(step), cell, html.escape(what), html.escape(decision), html.escape(state)]
        rows.append("<tr>" + "".join(f"<td>{c}</td>" for c in cells) + "</tr>")
    return f'<div class="scroll"><table><tbody>{"".join(rows)}</tbody></table></div>'


def mermaid(source):
    kind = next((l.split()[0] for l in source.splitlines() if l.strip() and not l.strip().startswith("%%")), "")
    body = source.rstrip()
    if kind == "erDiagram":
        body += CLASSES["stroke"]
    elif kind != "sequenceDiagram":
        body += CLASSES["fill"]
    # `>` stays as it is: it is half of every arrow, and it can't open a tag.
    text = (THEME + body).replace("&", "&amp;").replace("<", "&lt;")
    return f'<div><pre class="mermaid">\n{text}\n</pre></div>'


def note(source, name):
    match = re.search(rf"^\s*%%\s*{name}:\s*(.+)$", source, re.M)
    return match.group(1).strip() if match else ""


def page(folder, title, summary):
    root = git(folder, "rev-parse", "--show-toplevel") or folder
    parts = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if name.endswith(".tsv"):
            parts.append(f"<figure>{code_table(path, root)}</figure>")
        elif name.endswith(".mmd"):
            source = open(path, encoding="utf-8").read()
            heading = note(source, "title")
            caption = note(source, "caption")
            parts.append(
                "<figure>"
                + (f"<h2>{html.escape(heading)}</h2>" if heading else "")
                + mermaid(source)
                + (f"<figcaption>{html.escape(caption)}</figcaption>" if caption else "")
                + "</figure>"
            )
    if not parts:
        sys.exit(f"no .mmd or .tsv files in {folder}")
    out = os.path.join(folder, "page.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(
            f'<title>{html.escape(title)}</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n'
            f'<style>{STYLE}</style>\n<div class="wrap">\n<header><h1>{html.escape(title)}</h1>'
            f"<p>{html.escape(summary)}</p></header>\n" + "\n".join(parts) + "\n</div>\n"
        )
    print(out)


def main(argv):
    if len(argv) != 4 or argv[0] != "page":
        sys.exit(__doc__)
    page(argv[1], argv[2], argv[3])


if __name__ == "__main__":
    main(sys.argv[1:])
