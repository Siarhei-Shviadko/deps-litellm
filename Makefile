-include .env
-include vendors/deps-pipelines/shared/Makefile
-include Makefile.local

CURRENT_UID := $(shell id -u):$(shell id -g)
HASH := $(shell git rev-parse HEAD)
DATE := $(shell date)
TAG := $(shell git describe || echo "latest")
commit_short_sha := "$(CI_COMMIT_SHORT_SHA)"

CI_PROJECT_NAME ?= deps-litellm
HELM_CHART := .helm/services
HELM_BASE_VALUES := .helm/services/values.yaml
LITELLM_MODEL_CONFIG_FILE := etc/litellm/config.yaml

APP_NAME = litellm
NO_DEV_DOCKER_IMAGE = deps-litellm
DEV_DOCKER_IMAGE = deps-litellm-dev

.PHONY: config
## Show current docker compose config
config:
	docker compose -f docker-compose.yml config

.PHONY: install
## Install default environment settings
install:
	test -f .env || cp .env.example .env
	test -f etc/litellm/.env || cp etc/litellm/.env.example etc/litellm/.env

.PHONY: login
## Login in docker registry
login:
	docker login $(repository)

.PHONY: prereq
## Prepare local environment
prereq:
	test -f .env || echo >> .env
	docker network create deps-network || true

.PHONY: run
## Run service
run: | prereq
	docker compose up -d

.PHONY: start
## Run service (alias for run)
start: run

.PHONY: logs
## Open service logs
logs:
	docker compose logs -f $(APP_NAME)

.PHONY: status
## Get running status information
status:
	docker compose ps

.PHONY: stop
## Stop running services
stop:
	docker compose stop

.PHONY: down
## Stop and remove containers
down:
	docker compose down

.PHONY: shell-litellm
## Open shell in LiteLLM container
shell-litellm:
	docker compose exec $(APP_NAME) /bin/sh

.PHONY: pull
## Pull service images (no-op: config-only service)
pull:
	@echo "Config-only service — no images to pull"

.PHONY: build-prod
## Build production images (no-op: config-only service)
build-prod:
	@echo "Config-only service — no images to build"

.PHONY: push
## Push images to registry (no-op: config-only service)
push:
	@echo "Config-only service — no images to push"

.PHONY: tag
## Retag built services (no-op: config-only service)
tag:
	@echo "Config-only service — no images to tag"

.PHONY: ci
## Run CI checks (Helm lint/template + docker compose config)
ci: helmlint config

.PHONY: helmlint
## Lint and render Helm chart for all environments
helmlint:
	helm lint $(HELM_CHART) --set-file litellm_settings.LITELLM_MODEL_CONFIG=$(LITELLM_MODEL_CONFIG_FILE)
	@for env_values in .helm/values.*.yaml; do \
		echo "==> helm lint with $$env_values"; \
		helm lint $(HELM_CHART) -f $(HELM_BASE_VALUES) -f "$$env_values" --set-file litellm_settings.LITELLM_MODEL_CONFIG=$(LITELLM_MODEL_CONFIG_FILE); \
	done
	helm template $(CI_PROJECT_NAME) $(HELM_CHART) \
		-f $(HELM_BASE_VALUES) \
		--set-file litellm_settings.LITELLM_MODEL_CONFIG=$(LITELLM_MODEL_CONFIG_FILE) \
		--output-dir chart

.PHONY: helm-upgrade-service
helm-upgrade-service:
	helm upgrade --install $(CI_PROJECT_NAME) $(HELM_CHART) \
        --values $(HELM_BASE_VALUES) $(ADDITIONAL_VALUES) \
        --set-file litellm_settings.LITELLM_MODEL_CONFIG=$(LITELLM_MODEL_CONFIG_FILE) \
        --set registry=$(REPOSITORY_URL) \
        --set vault_settings.enabled=$(VAULT_ENABLE) \
        --timeout 300s \
        --atomic \
        --wait \
        --debug \
        --namespace $(NAMESPACE)

.PHONY: helm-deployment-rollback
helm-deployment-rollback:
	helm rollback --namespace $(NAMESPACE) $(CI_PROJECT_NAME) 0

.PHONY: helm-rollback
helm-rollback:
	make helm-deployment-rollback

.PHONY: helm-upgrade
helm-upgrade:
	make helm-upgrade-service

testdkube := $(shell kubectl config current-context)
ifeq ($(testdkube), rancher-desktop)
.PHONY: skaffold
skaffold:
	cd skaffold && skaffold run -f skaffold.yaml
endif
