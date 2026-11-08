"""Art iterations (ART-ITERATION-001): every candidate an LLM-driven art workflow produces
goes to one place, one folder per iteration named YYYYMMDD_HHMM_<descriptive_name>
(local time of the run, lowercase words joined by underscores), so iterations are
catalogued in order and never overwrite each other. Approved sources stay in art-src/;
an iteration folder is evidence, never a source. Pure Python.
"""

from __future__ import annotations

import os
import re
from datetime import datetime

## Relative to the repository root.
ROOT = os.path.join(".reports", "art", "iterations")
NAME = re.compile(r"^(\d{8})_(\d{4})_([a-z0-9]+(?:_[a-z0-9]+)*)$")


def name(descriptive, when=None):
    """The iteration name for `descriptive` at `when` (default now)."""
    when = when or datetime.now()
    out = "%s_%s" % (when.strftime("%Y%m%d_%H%M"), descriptive)
    problems = name_problems(out)
    if problems:
        raise ValueError("; ".join(problems))
    return out


def name_problems(value):
    """Why `value` is not an iteration name (empty: it is one)."""
    match = NAME.match(value)
    if not match:
        return ["%r is not YYYYMMDD_HHMM_<descriptive_name> (lowercase words joined by _)" % value]
    stamp = match.group(1) + match.group(2)
    try:
        datetime.strptime(stamp, "%Y%m%d%H%M")
    except ValueError:
        return ["%r carries no real date and time" % value]
    return []


def path_problems(path, root_dir):
    """Why an output `path` is not inside one iteration folder under `root_dir`/ROOT."""
    base = os.path.normcase(os.path.abspath(os.path.join(root_dir, ROOT)))
    full = os.path.normcase(os.path.abspath(path))
    if not full.startswith(base + os.sep):
        return ["%s is outside %s" % (path, os.path.join(root_dir, ROOT))]
    folder = os.path.relpath(full, base).split(os.sep)[0]
    return name_problems(folder)
