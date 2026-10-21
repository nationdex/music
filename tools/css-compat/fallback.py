#!/usr/bin/env python3
"""Keeps the light-dark() fallback in site/assets/app.css in step with the color tokens.

  python3 tools/css-compat/fallback.py          rewrite the block between the compat markers
  python3 tools/css-compat/fallback.py --check  exit 1 if it is out of date (used by tests/smoke.sh)
"""
import re
import sys

PATH = "site/assets/app.css"
css = open(PATH, encoding="utf-8").read()
tokens = css[css.index("/* Tokens. The Material 3 colors"):]
root = re.search(r":root \{(.*?)\n\}", tokens, re.S).group(1)
pairs = re.findall(r"(--color-[A-Za-z0-9]+):\s*light-dark\(\s*(#[0-9a-fA-F]{3,8})\s*,\s*(#[0-9a-fA-F]{3,8})\s*\)", root)
if len(pairs) < 20:
    sys.exit("found only %d light-dark tokens; is the token block intact?" % len(pairs))
light = "\n".join("    %s: %s;" % (n, a) for n, a, _ in pairs)
dark = "\n".join("    %s: %s;" % (n, b) for n, _, b in pairs)
block = (
    "/* compat:start */\n@supports not (color: light-dark(white, black)) {\n  :root {\n%s\n  }\n  :root.dark {\n%s\n  }\n}\n/* compat:end */"
    % (light, dark)
)
new = re.sub(r"/\* compat:start \*/.*?/\* compat:end \*/", lambda _: block, css, flags=re.S)
if "--check" in sys.argv:
    sys.exit(0 if new == css else 1)
open(PATH, "w", encoding="utf-8").write(new)
print("fallback block for %d tokens" % len(pairs))
