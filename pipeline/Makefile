# Velix region pack. Run from the repo root: make -C pipeline pack [REGION=lombardy]
# Needs Docker (Colima or Docker Desktop locally; ubuntu-latest in CI).
REGION ?= lombardy
ROOT := $(abspath ..)
OUT := out/$(REGION)
TOOLS_IMAGE := velix-pipeline-tools
# Shared settings live in config/_base.yml (read with a regex: the host may not have PyYAML).
base = $(shell python3 -c "import re;print(re.search(r'\n$(1):\n(?:  .*\n)*?  $(2): (\S+)', open('config/_base.yml').read()).group(1))")
VALHALLA_IMAGE := $(call base,valhalla,image)
DOCKER_RUN := docker run --rm -e REGION=$(REGION) -v "$(ROOT):/work" -w /work/pipeline
TOOLS := $(DOCKER_RUN) $(TOOLS_IMAGE)
VALHALLA := $(DOCKER_RUN) $(VALHALLA_IMAGE)
PLANETILER_IMAGE := $(call base,basemap,image)
BASEMAP_ZOOM := $(call base,basemap,maxzoom)
REGION_BOUNDS = $(shell python3 stages/bounds.py $(OUT)/region.geojson)

.PHONY: test pack tools extract elevation prepare tiles hazards routes transit basemap overlays package validate smoke clean

pack: extract elevation prepare tiles hazards routes transit basemap overlays package validate smoke

test: tools
	$(TOOLS) python -m unittest discover -s tests -v

tools:
	docker build -q -t $(TOOLS_IMAGE) -f Dockerfile.tools .

extract: tools
	$(TOOLS) bash stages/extract.sh

elevation: tools
	$(TOOLS) python stages/elevation.py

prepare: tools
	$(TOOLS) python stages/prepare_routing.py

tiles:
	$(VALHALLA) bash stages/tiles.sh

hazards: tools
	$(TOOLS) python stages/hazards.py

routes: tools
	$(TOOLS) python stages/routes.py

transit: tools
	$(TOOLS) python stages/transit.py
	$(TOOLS) python stages/transit_paths.py

# OpenMapTiles basemap. Tiles are stored uncompressed: the pack's xz then compresses across tiles (151 MB instead of
# 203 MB with per-tile gzip, measured 16 Oct 2026); MapLibre reads uncompressed PMTiles tiles directly.
# Planetiler's temp files stay inside the container (it runs as root: the host couldn't delete them on Linux).
# Its other sources (water polygons, Natural Earth, lake centerlines) are read from the cache; --download only when one
# is missing: with it, planetiler asks each server for the file's size, and osmdata.openstreetmap.de timing out failed
# every region (9 Nov 2026). The cache is refreshed monthly in CI (workflow cache keys).
PLANETILER_SOURCES := water-polygons-split-3857.zip natural_earth_vector.sqlite.zip lake_centerline.shp.zip
PLANETILER_DOWNLOAD = $(if $(strip $(foreach f,$(PLANETILER_SOURCES),$(if $(wildcard cache/planetiler/$(f)),,missing))),--download,)
basemap: tools
	docker run --rm -v "$(ROOT)/pipeline/out:/out" -v "$(ROOT)/pipeline/cache:/cache" $(PLANETILER_IMAGE) \
	  --osm-path=/out/$(REGION)/map.osm.pbf $(PLANETILER_DOWNLOAD) --download-dir=/cache/planetiler \
	  --water_polygons_path=/cache/planetiler/water-polygons-split-3857.zip \
	  --natural_earth_path=/cache/planetiler/natural_earth_vector.sqlite.zip \
	  --lake_centerlines_path=/cache/planetiler/lake_centerline.shp.zip \
	  --tmpdir=/tmp/planetiler --bounds=$(REGION_BOUNDS) --maxzoom=$(BASEMAP_ZOOM) \
	  --tile-compression=none --output-layerstats --output=/out/$(REGION)/basemap.pmtiles --force
	$(TOOLS) python stages/basemap_meta.py

overlays: tools
	$(TOOLS) python stages/overlays.py

package: tools
	$(TOOLS) python stages/package.py

validate: tools
	$(TOOLS) python stages/validate.py

smoke: tools
	$(TOOLS) python stages/smoke_trips.py
	$(VALHALLA) bash stages/smoke_routes.sh
	$(TOOLS) python stages/smoke.py

clean:
	rm -rf $(OUT)
