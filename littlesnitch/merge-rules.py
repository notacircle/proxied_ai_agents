#!/usr/bin/env python3
"""Вливает правила из .lsrules в выгрузку Little Snitch (export-model).

Little Snitch 6 не умеет импортировать локальный .lsrules, поэтому:
  1. sudo littlesnitch export-model > backup.json        (делает пользователь)
  2. merge-rules.py backup.json claude-killswitch.lsrules [chatgpt-killswitch.lsrules ...] merged.json
  3. sudo littlesnitch restore-model merged.json        (делает пользователь)

Метка набора — его поле name («Claude kill-switch», «ChatGPT kill-switch»), она
же должна быть в notes каждого правила. Старые правила набора (по метке в notes)
удаляются, поэтому скрипт можно запускать повторно. Остальная модель не меняется.
С флагом --remove правила наборов только удаляются.
"""
import datetime
import json
import os
import sys

def main():
    args = sys.argv[1:]
    remove_only = args[:1] == ["--remove"]
    if remove_only:
        args = args[1:]
    if len(args) < 3:
        sys.exit("usage: merge-rules.py [--remove] <export.json> <rules.lsrules>... <out.json>")
    src, rule_files, dst = args[0], args[1:-1], args[-1]

    model = json.load(open(src))
    if "rules" not in model:
        sys.exit(f"{src}: не похоже на выгрузку export-model (нет ключа rules)")

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rules = model["rules"]
    for path in rule_files:
        ruleset = json.load(open(path))
        marker, new_rules = ruleset["name"], [] if remove_only else ruleset["rules"]
        kept = [r for r in rules if marker not in r.get("notes", "")]
        removed = len(rules) - len(kept)
        for r in new_rules:
            if marker not in r.get("notes", ""):
                sys.exit(f"{path}: правило без метки «{marker}» в notes: {r}")
            kept.append({**r, "creationDate": now, "modificationDate": now,
                         "origin": "frontend", "uid": os.getuid()})
        rules = kept
        print(f"{marker}: удалено старых {removed}, добавлено {len(new_rules)}")

    model["rules"] = rules
    json.dump(model, open(dst, "w"), ensure_ascii=False, indent=2)
    print(f"всего правил: {len(rules)} -> {dst}")


if __name__ == "__main__":
    main()
