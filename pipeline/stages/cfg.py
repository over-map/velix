"""Print one config value by dotted path (`python stages/cfg.py osm.url`), for the shell stages. A list prints
space-separated; a missing key prints nothing (optional settings such as region.osm_relation)."""
import sys

from common import load_config

v = load_config()
for k in sys.argv[1].split("."):
    if not isinstance(v, dict) or k not in v:
        sys.exit(0)
    v = v[k]
print(" ".join(map(str, v)) if isinstance(v, list) else v)
