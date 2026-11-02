#!/usr/bin/env python3
"""Вливает правила из .lsrules в выгрузку Little Snitch (export-model).

Little Snitch 6 не умеет импортировать локальный .lsrules, поэтому:
  1. sudo littlesnitch export-model > backup.json        (делает пользователь)
  2. merge-rules.py backup.json claude-killswitch.lsrules merged.json
  3. sudo littlesnitch restore-model merged.json        (делает пользователь)

Старые правила kill-switch (по метке в notes) удаляются, поэтому скрипт можно
запускать повторно. Всё остальное в модели переносится без изменений.
"""
import datetime
import json
import os
import sys

MARKER = "Claude kill-switch"


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: merge-rules.py <export.json> <rules.lsrules> <out.json>")
    src, rules_path, dst = sys.argv[1:]

    model = json.load(open(src))
    if "rules" not in model:
        sys.exit(f"{src}: не похоже на выгрузку export-model (нет ключа rules)")
    new_rules = json.load(open(rules_path))["rules"]

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    kept = [r for r in model["rules"] if MARKER not in r.get("notes", "")]
    removed = len(model["rules"]) - len(kept)

    for r in new_rules:
        if MARKER not in r.get("notes", ""):
            sys.exit(f"правило без метки «{MARKER}» в notes: {r}")
        kept.append({**r, "creationDate": now, "modificationDate": now,
                     "origin": "frontend", "uid": os.getuid()})

    model["rules"] = kept
    json.dump(model, open(dst, "w"), ensure_ascii=False, indent=2)
    print(f"удалено старых правил kill-switch: {removed}, добавлено: {len(new_rules)}, "
          f"всего правил: {len(kept)} -> {dst}")


if __name__ == "__main__":
    main()
