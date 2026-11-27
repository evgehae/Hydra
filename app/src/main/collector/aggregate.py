#!/usr/bin/env python3
"""Склейка отчётов Гидры в priors.json: python3 aggregate.py export.json priors.json
export.json — ответ GET /v1/export (список отчётов). Для каждой сети берём стратегии по числу пользователей, у которых они работали."""
import json, sys, collections
reports = json.load(open(sys.argv[1], encoding='utf-8'))
seeds = collections.defaultdict(collections.Counter)
colos = collections.defaultdict(collections.Counter)
for r in reports:
    for key, v in (r.get('priors') or {}).items():
        for s in v.get('seeds', []): seeds[key][s] += 1
        for c in v.get('colos', []): colos[key][c] += 1
try: out = json.load(open(sys.argv[2], encoding='utf-8'))
except Exception: out = {}
for key in seeds:
    top = [s for s, _ in seeds[key].most_common(30)]
    old = out.get(key, {}).get('seeds', [])
    out[key] = {'seeds': top + [s for s in old if s not in top][:10],
                'colos': [c for c, _ in colos[key].most_common(4)] or out.get(key, {}).get('colos', [])}
json.dump(out, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('сетей:', len(out), 'отчётов:', len(reports))
