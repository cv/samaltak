#!/usr/bin/env python3
"""Check the static retained-primitives catalog against the audit and registry."""

import re
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
BASES = ("necessity", "policy")
PROCESS_IDS = {515, 516, 518, 560}


def check(ok, message):
    if not ok:
        raise SystemExit(message)


def audited_ids(audit):
    ids = []
    for ranges in re.findall(r"^\|\s*([\d, –-]+)\|\s*Keep\s*\|", audit, re.M):
        for span in ranges.split(","):
            lo, *hi = [int(n) for n in re.split("[–-]", span)]
            ids.extend(range(lo, (hi[0] if hi else lo) + 1))
    return ids


class Catalog(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.ids = set()
        self.fragments = []
        self.totals = {}
        self.groups = {}
        self.group_sizes = Counter()
        self.rows = []
        self.group = self.row = self.capture = None
        self.feed(html)
        self.close()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        ident = attrs.get("id")
        classes = attrs.get("class", "").split()
        if ident:
            check(ident not in self.ids, f"Duplicate HTML ID: {ident}")
            self.ids.add(ident)
        for attr in ("src", "srcset", "poster", "background", "data"):
            check(attr not in attrs, f"Catalog must not load an asset: {tag} {attrs}")
        if "href" in attrs:
            href = attrs["href"]
            url = urlsplit(href)
            check(tag == "a" and not url.scheme and not url.netloc,
                  f"Unexpected non-local link or asset: {href}")
            if href.startswith("#"):
                self.fragments.append(href[1:])
            else:
                check((ROOT / "docs" / url.path).is_file(), f"Broken source link: {href}")

        if tag == "section" and "group" in classes:
            check(ident and "hidden" not in attrs, f"Family not statically visible: {attrs}")
            self.group = ident
            self.groups[ident] = ""
        elif tag == "span" and "group-count" in classes:
            self.capture = (tag, self.groups, self.group)
        elif tag == "strong" and ident and ident.endswith("total"):
            self.totals[ident] = ""
            self.capture = (tag, self.totals, ident)

        if tag == "tr" and "entry" in classes:
            check(self.group is not None, f"Entry outside a family: {ident}")
            check("hidden" not in attrs, f"Entry not statically visible: {ident}")
            self.row = dict(anchor=ident, basis=attrs.get("data-basis"),
                            number="", name="", badge="", reason="")
            self.rows.append(self.row)
            self.group_sizes[self.group] += 1
        if self.row is not None:
            if tag == "th":
                check(attrs.get("scope") == "row", "Missing row header scope")
            if tag == "td":
                self.capture = (tag, self.row, "reason")
            if tag == "code":
                self.capture = (tag, self.row, "name")
            if tag == "span" and "num" in classes:
                self.capture = (tag, self.row, "number")
            if tag == "span" and "badge" in classes:
                self.capture = (tag, self.row, "badge")

    def handle_data(self, text):
        if self.capture:
            _, fields, key = self.capture
            fields[key] += text

    def handle_endtag(self, tag):
        if self.capture and tag == self.capture[0]:
            key = self.capture[2]
            # After the badge, capture the visible explanation, not the badge text.
            self.capture = ("td", self.row, "reason") if key == "badge" else None
        if tag == "tr":
            self.row = None
        elif tag == "section":
            self.group = None


def main():
    keep = audited_ids((ROOT / "docs/ffi-primitive-audit.md").read_text(encoding="utf-8"))
    check(len(keep) == len(set(keep)) == 156, "Audit must contain 156 unique Keep IDs")
    check(not PROCESS_IDS.intersection(keep), "Retired process IDs must not be Keep")

    source = (ROOT / "vm/gen/primitive_entries.c").read_text(encoding="utf-8")
    pairs = re.findall(r'^\s*\{(\d+),\s*\d+,\s*"([^"]+)",\s*\w+\},', source, re.M)
    registry = {int(number): name for number, name in pairs}
    check(len(registry) == len(pairs), "Duplicate registry IDs")
    live_process_ids = PROCESS_IDS & registry.keys()
    check(not live_process_ids, f"Retired process IDs still registered: {sorted(live_process_ids)}")
    check(registry.get(422) == "windowSetPosition" and 422 not in keep,
          "SDL slot 422 must be registered outside the original Keep catalog")
    check(set(keep) <= registry.keys(), f"Audit IDs missing from registry: {set(keep) - registry.keys()}")

    html = (ROOT / "docs/vm-primitives-retained.html").read_text(encoding="utf-8")
    check(not re.search(r"url\s*\(|@import\b", html, re.I), "Unexpected CSS asset reference")
    catalog = Catalog(html)
    check(not set(catalog.fragments) - catalog.ids, "Broken internal link")
    check(set(catalog.groups) <= set(catalog.fragments), "Family missing a jump link")
    check(all(re.fullmatch(r"· \d+", n) and int(n[2:]) == catalog.group_sizes[g] > 0
              for g, n in catalog.groups.items()), "Missing family entries or incorrect family size")

    numbers = []
    reasons = set()
    bases = Counter()
    for row in catalog.rows:
        check(row["number"].isdigit(), f"Missing or invalid visible ID: {row}")
        number = int(row["number"])
        numbers.append(number)
        check(row["anchor"] == f"p-{number}", f"Mismatched entry anchor: {row}")
        check(row["name"] == registry.get(number), f"Mismatched registered name: {row}")
        basis = row["basis"]
        check(basis in BASES and row["badge"] == basis.title(), f"Mismatched basis: {row}")
        bases[basis] += 1
        reason = " ".join(row["reason"].lower().split())
        check(len(reason.split()) >= 6 and reason not in reasons, f"Missing or repeated explanation: {row}")
        reasons.add(reason)

    check(len(numbers) == len(set(numbers)), "Duplicate catalog IDs")
    check(set(numbers) == set(keep),
          f"Catalog/audit mismatch: missing {sorted(set(keep) - set(numbers))}; "
          f"extra {sorted(set(numbers) - set(keep))}")
    totals = {
        "total": len(numbers), "family-total": len(catalog.groups), "sdl-total": len(registry),
        "necessity-total": bases["necessity"], "policy-total": bases["policy"],
    }
    check(catalog.totals == {key: str(value) for key, value in totals.items()},
          f"Stale catalog totals: expected {totals}")
    print(f"OK: {len(numbers)} exact Keep IDs/names across {len(catalog.groups)} families "
          f"({bases['necessity']} necessity, {bases['policy']} policy); {len(registry)} SDL slots.")


if __name__ == "__main__":
    main()
