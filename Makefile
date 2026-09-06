.PHONY: setup up down restart keys spend health health-local logs ui test clean webui webui-down clients
SHELL := /bin/bash

setup:        ## one-time bootstrap (venv, prisma, postgres, schema, models)
	@./scripts/setup.sh
up:           ## start postgres + gateway
	@./scripts/db.sh up && ./scripts/start.sh
down:         ## stop gateway (postgres keeps running)
	@./scripts/stop.sh
restart: down up
keys:         ## provision virtual keys (idempotent)
	@./scripts/provision-keys.sh
spend:        ## where the money went
	@./scripts/spend.sh
health:       ## on-demand health of ALL deployments (bills cloud models)
	@./scripts/health.sh
health-local: ## free health check (ollama + gateway + db)
	@./scripts/health-local.sh
webui:        ## start the graphical chat UI (Open WebUI)
	@./scripts/webui.sh up
webui-down:   ## stop the chat UI
	@./scripts/webui.sh down
clients:      ## configure Cline (CLI + VS Code) against the gateway
	@./scripts/setup-clients.sh
logs:         ## tail gateway logs
	@tail -f logs/gateway.log
ui:           ## open the admin UI
	@source .env; xdg-open "http://$$GATEWAY_HOST:$$GATEWAY_PORT/ui" 2>/dev/null || \
	 (source .env; echo "http://$$GATEWAY_HOST:$$GATEWAY_PORT/ui  (user: admin, pass: \$$LITELLM_MASTER_KEY)")
test:         ## end-to-end smoke test of every tier
	@./scripts/smoke-test.sh
clean:        ## stop everything and delete the database + chat-UI volumes
	@./scripts/stop.sh; ./scripts/webui.sh destroy; ./scripts/db.sh destroy
