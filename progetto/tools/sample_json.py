"""Writes a small sample of a large JSON file of the world: the same structure, only the first few entries of every
long list, with a note of how many there are. For the inspection pack (tools/make_inspection_pack.ps1).

    python sample_json.py <input.json> <output.json> [items]
"""
import json
import sys


def shrink(value, items):
    if isinstance(value, list):
        if len(value) > items and all(isinstance(v, (int, float)) for v in value):
            return value[:12] + ["... %d numeri in tutto" % len(value)]
        out = [shrink(v, items) for v in value[:items]]
        if len(value) > items:
            out.append("... %d elementi in tutto, qui i primi %d" % (len(value), items))
        return out
    if isinstance(value, dict):
        return {k: shrink(v, items) for k, v in value.items()}
    return value


def main():
    src, dst = sys.argv[1], sys.argv[2]
    items = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    with open(src, encoding='utf-8') as f:
        data = json.load(f)
    with open(dst, 'w', encoding='utf-8', newline='') as f:
        json.dump(shrink(data, items), f, ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()

