#!/usr/bin/env python3
"""Targeted text edits for tools/mac-theme. Prints the result on stdout; never
writes the file. Run as: python3 -I ini.py <command> ...

  ini         FILE SECTION KEY VALUE   set KEY=VALUE in [SECTION]; file/section/key
                                       are created when missing, all else is kept
  toml-output FILE TABLE VALUE         set output_path in [TABLE] of a matugen
                                       config.toml (single-quoted, as the repo does)
"""
import re
import sys


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def ini_set(text, section, key, value):
    lines = text.split("\n") if text else []
    if lines and lines[-1] == "":
        lines.pop()
    head = "[%s]" % section
    start = next((i for i, l in enumerate(lines) if l.strip() == head), None)
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines += [head, "%s=%s" % (key, value)]
        return "\n".join(lines) + "\n"
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
    for i in range(start + 1, end):
        m = re.match(r"\s*%s\s*=" % re.escape(key), lines[i])
        if m:
            lines[i] = "%s=%s" % (key, value)
            return "\n".join(lines) + "\n"
    ins = end
    while ins > start + 1 and not lines[ins - 1].strip():
        ins -= 1
    lines.insert(ins, "%s=%s" % (key, value))
    return "\n".join(lines) + "\n"


def toml_output(text, table, value):
    lines = text.split("\n")
    head = "[%s]" % table
    start = next((i for i, l in enumerate(lines) if l.strip() == head), None)
    if start is None:
        return text
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith("["):
            break
        if re.match(r"\s*output_path\s*=", lines[i]):
            lines[i] = "output_path = '%s'" % value
            break
    return "\n".join(lines)


def main(argv):
    if len(argv) >= 6 and argv[1] == "ini":
        sys.stdout.write(ini_set(read(argv[2]), argv[3], argv[4], argv[5]))
    elif len(argv) == 5 and argv[1] == "toml-output":
        sys.stdout.write(toml_output(read(argv[2]), argv[3], argv[4]))
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
