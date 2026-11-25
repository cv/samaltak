#!/usr/bin/env python3
"""Check the static retained-primitives catalog against the audit and registry."""

import re
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
BASES = ("necessity", "policy")
IMAGE_DISPLAY_IDS = set(range(200, 207))
# The fork's primitives (cv/samaltak), registered after the audit and outside it, as 422 is; upstream's registry has
# 185 slots. One retired or added here changes this list and the catalog's fork-total and sdl-total. Retired into
# typed vm:core exports (docs/ffi-fork.md), their numbers not reused: 119 and 122 (core_bytes_mismatch, _last_mismatch), 207 (core_png_filter).
FORK_PRIMITIVES = {
    147: "samplerBuffer", 208: "zlibMatches",
    210: "zlibWriteTokens", 212: "rawBytesReplace", 213: "pixelsPack", 214: "zrleTiles",
    462: "gpuUploadTextureAddress", 463: "windowPresentAddress", 485: "rasterQuadBounds",
    590: "deviceOpen", 591: "deviceClose", 592: "deviceIoctl", 593: "deviceMap", 594: "deviceUnmap",
    595: "deviceConstants", 596: "deviceRead", 597: "deviceWrite", 646: "cryptoCrc32",
}


def check(ok, message):
    if not ok:
        raise SystemExit(message)


def audited_ids(audit, disposition):
    ids = []
    pattern = rf"^\|\s*([\d, –-]+)\|\s*{re.escape(disposition)}\s*\|"
    for ranges in re.findall(pattern, audit, re.M):
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
    audit = (ROOT / "docs/ffi-primitive-audit.md").read_text(encoding="utf-8")
    keep = audited_ids(audit, "Keep")
    check(len(keep) == len(set(keep)) == 149, "Audit must contain 149 unique Keep IDs")
    image_ids = audited_ids(audit, "Image display")
    check(len(image_ids) == 7 and set(image_ids) == IMAGE_DISPLAY_IDS,
          "Audit must assign exactly 200–206 to Image display")
    ffi_manifest = (ROOT / "tests/vm/ffi_cutover_slots.tsv").read_text(encoding="utf-8")
    ffi_ids = {int(number) for number in re.findall(r"^(\d+)\t", ffi_manifest, re.M)}
    ffi_audit = [n for disposition in ("Adapter", "Extend", "Process cutover")
                 for n in audited_ids(audit, disposition)]
    check(len(ffi_audit) == len(ffi_ids) == 102 and set(ffi_audit) == ffi_ids,
          "Audit FFI retirements must match the 102 slots in the FFI manifest")
    retired = ffi_ids | IMAGE_DISPLAY_IDS
    check(len(retired) == 109, "Expected 102 FFI retirements and seven separate image display retirements")
    check(retired.isdisjoint(keep), "Retired IDs must not be Keep")

    source = (ROOT / "vm/gen/primitive_entries.c").read_text(encoding="utf-8")
    pairs = re.findall(r'^\s*\{(\d+),\s*\d+,\s*"([^"]+)",\s*\w+\},', source, re.M)
    registry = {int(number): name for number, name in pairs}
    check(len(registry) == len(pairs), "Duplicate registry IDs")
    live_retired_ids = retired & registry.keys()
    check(not live_retired_ids, f"Retired IDs still registered: {sorted(live_retired_ids)}")
    fork = {number: registry.get(number) for number in FORK_PRIMITIVES}
    check(fork == FORK_PRIMITIVES, f"The fork's primitives changed: expected {FORK_PRIMITIVES}, registered {fork}")
    check(FORK_PRIMITIVES.keys().isdisjoint(set(keep) | retired), "The fork's primitives must be outside the audit")
    check(len(registry) - len(FORK_PRIMITIVES) == 185, "Expected 185 hosted SDL registry slots beside the fork's")
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
        "total": len(numbers), "family-total": len(catalog.groups), "sdl-total": len(registry), "fork-total": len(FORK_PRIMITIVES),
        "necessity-total": bases["necessity"], "policy-total": bases["policy"],
    }
    check(catalog.totals == {key: str(value) for key, value in totals.items()},
          f"Stale catalog totals: expected {totals}")
    print(f"OK: {len(numbers)} exact Keep IDs/names across {len(catalog.groups)} families "
          f"({bases['necessity']} necessity, {bases['policy']} policy); {len(registry)} SDL slots.")
    print(f"OK: {len(retired)} retired slots absent ({len(ffi_ids)} FFI, {len(image_ids)} image display).")


if __name__ == "__main__":
    main()
