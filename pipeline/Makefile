# Velix region pack. Run from the repo root: make -C pipeline pack [REGION=lombardy]
# Needs Docker (Colima or Docker Desktop locally; ubuntu-latest in CI).
REGION ?= lombardy
ROOT := $(abspath ..)
OUT := out/$(REGION)
TOOLS_IMAGE := velix-pipeline-tools
VALHALLA_IMAGE := $(shell python3 -c "import re;print(re.search(r'image: (\S+)', open('config/$(REGION).yml').read()).group(1))")
DOCKER_RUN := docker run --rm -e REGION=$(REGION) -v "$(ROOT):/work" -w /work/pipeline
TOOLS := $(DOCKER_RUN) $(TOOLS_IMAGE)
VALHALLA := $(DOCKER_RUN) $(VALHALLA_IMAGE)

.PHONY: pack tools extract elevation tiles hazards routes transit package validate smoke clean

pack: extract elevation tiles hazards routes transit package validate smoke

tools:
	docker build -q -t $(TOOLS_IMAGE) -f Dockerfile.tools .

extract: tools
	$(TOOLS) bash stages/extract.sh

elevation: tools
	$(TOOLS) python stages/elevation.py

tiles:
	$(VALHALLA) bash stages/tiles.sh

hazards: tools
	$(TOOLS) python stages/hazards.py

routes: tools
	$(TOOLS) python stages/routes.py

transit: tools
	$(TOOLS) python stages/transit.py

package: tools
	$(TOOLS) python stages/package.py

validate: tools
	$(TOOLS) python stages/validate.py

smoke: tools
	$(VALHALLA) bash stages/smoke_routes.sh
	$(TOOLS) python stages/smoke.py

clean:
	rm -rf $(OUT)
