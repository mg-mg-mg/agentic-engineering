#!/usr/bin/env bash
set -euo pipefail
# Scan staged text and incoming commit trees/metadata, not pre-existing history.
# Requires only git and Python 3; binary media needs separate human review.
python3 - "${1:-origin/main}" <<'PY'
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args])


base = sys.argv[1]
git("rev-parse", "--verify", base + "^{commit}")
ancestry = subprocess.run(["git", "merge-base", "--is-ancestor", base, "HEAD"])
if ancestry.returncode == 1:
    sys.exit("Publication check: base is not an ancestor of HEAD; update the branch against the current base and rerun")
if ancestry.returncode != 0:
    sys.exit("Publication check: could not establish base ancestry; refusing publication")
email = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
noreply = re.compile(rb"(?:[0-9]+\+)?[A-Za-z0-9-]+@users\.noreply\.github\.com")
credentials = re.compile(
    rb"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|"
    rb"AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{30,}|"
    rb"BEGIN (?:[A-Z]+ )?PRIVATE KEY|https?://[^/\s]+:[^/@\s]+@"
)
failed = False


def scan(data, label):
    global failed
    if any(not noreply.fullmatch(match.group()) for match in email.finditer(data)):
        print(f"Publication check: non-noreply email in {label}", file=sys.stderr)
        failed = True
    if credentials.search(data):
        print(f"Publication check: possible credential in {label}", file=sys.stderr)
        failed = True


def scan_blob(blob, label):
    data = git("cat-file", "blob", blob)
    # This is a text check, not binary/media inspection or containment proof.
    if b"\0" not in data:
        scan(data, label)


for entry in git("ls-files", "--stage", "-z").split(b"\0"):
    if not entry:
        continue
    header, path = entry.split(b"\t", 1)
    mode, blob, stage = header.split()
    if stage != b"0" or mode == b"160000":
        sys.exit("Publication check: unresolved index entry or submodule")
    scan(path, "staged path")
    scan_blob(blob.decode(), "staged text")

commits = git("rev-list", base + "..HEAD").decode().splitlines()
for commit in commits:
    identities = git("show", "-s", "--format=%ae%n%ce", commit).splitlines()
    if len(identities) != 2 or any(not noreply.fullmatch(value) for value in identities):
        sys.exit("Publication check: incoming author/committer must use GitHub noreply")
    scan(git("show", "-s", "--format=%B", commit), "incoming commit message")
    for entry in git("ls-tree", "-r", "-z", commit).split(b"\0"):
        if not entry:
            continue
        header, path = entry.split(b"\t", 1)
        mode, kind, blob = header.split()
        scan(path, "incoming path")
        if kind == b"blob":
            scan_blob(blob.decode(), "incoming text")
        else:
            sys.exit("Publication check: submodules require separate review")
if failed:
    sys.exit(1)
print("Publication check passed: staged text and incoming commits; existing history and binary media excluded")
PY
