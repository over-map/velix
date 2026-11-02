"""Print one config value by dotted path (`python stages/cfg.py osm.url`), for the shell stages."""
import sys

from common import load_config

v = load_config()
for k in sys.argv[1].split("."):
    v = v[k]
print(v)
