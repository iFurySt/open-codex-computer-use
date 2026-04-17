PROJECT ?=
SLUG ?=

.PHONY: init build app test smoke check-docs check-repo ci release-package new-history new-plan

init:
	@if [ -z "$(PROJECT)" ]; then echo "用法: make init PROJECT=项目名"; exit 1; fi
	./scripts/init-project.sh "$(PROJECT)"

build:
	swift build

app:
	./scripts/build-open-computer-use-app.sh debug

test:
	swift test

smoke:
	./scripts/run-tool-smoke-tests.sh

check-docs:
	./scripts/check-docs.sh

check-repo:
	./scripts/check-docs.sh
	./scripts/check-repo-hygiene.sh

ci:
	./scripts/ci.sh

release-package:
	./scripts/release-package.sh

new-history:
	@if [ -z "$(SLUG)" ]; then echo "用法: make new-history SLUG=变更名"; exit 1; fi
	./scripts/new-history.sh "$(SLUG)"

new-plan:
	@if [ -z "$(SLUG)" ]; then echo "用法: make new-plan SLUG=计划名"; exit 1; fi
	./scripts/new-exec-plan.sh "$(SLUG)"
