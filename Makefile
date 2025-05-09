# Makefile for managing PostgreSQL container

# Variables
SERVICE_NAME = test-pg-connector
DEFAULT_RECORDS = 10000000
DB_USER = meroxauser
DB_NAME = meroxadb
DB_HOST = localhost
DB_PORT = 5432

# Default branch to use if not specified
POSTGRES_BRANCH ?= haris/read-n-batches-handler-refactor
# POSTGRES_BRANCH ?= haris/read-n-batches
POSTGRES_REPO ?= https://github.com/conduitio/conduit-connector-postgres

.PHONY: help
help:
	@echo "Makefile for managing PostgreSQL container and related tasks"
	@echo ""
	@echo "Available targets:"
	@echo "  start             Start the PostgreSQL container"
	@echo "  stop              Stop the PostgreSQL container"
	@echo "  restart           Restart the PostgreSQL container"
	@echo "  logs              Show logs from the PostgreSQL container"
	@echo "  status            Show the status of the PostgreSQL container"
	@echo "  clean             Stop and remove the container"
	@echo "  clean-all         Remove container, volumes, and data"
	@echo "  wait-for-db       Wait for the database to become ready"
	@echo "  reset-table       Truncate the 'employees' table and reset IDs"
	@echo "  reset-db          Stop, clean, and restart the database"
	@echo "  get-connector     Fetch and use latest connector from specified branch"
	@echo "  run-with-version  Reset DB, get connector, and run main.go"
	@echo "  run               Run main.go"
	@echo "  run-custom        Run main.go with a custom record count (use RECORDS=...)"

# Start the PostgreSQL container in detached mode
start:
	@echo "Starting PostgreSQL container..."
	docker compose up -d $(SERVICE_NAME)
	@echo "PostgreSQL container started on port $(DB_PORT)"
	@echo "Database: $(DB_NAME), User: $(DB_USER)"
	@echo "Waiting for database to be ready..."
	@make wait-for-db

# Stop the PostgreSQL container
stop:
	@echo "Stopping PostgreSQL container..."
	docker compose stop $(SERVICE_NAME)
	@echo "PostgreSQL container stopped"

# Restart the PostgreSQL container
restart:
	@echo "Restarting PostgreSQL container..."
	docker compose restart $(SERVICE_NAME)
	@echo "PostgreSQL container restarted"

# Show logs from the PostgreSQL container
logs:
	@echo "Showing logs from PostgreSQL container..."
	docker compose logs -f $(SERVICE_NAME)

# Check the status of the PostgreSQL container
status:
	@echo "Checking status of PostgreSQL container..."
	docker compose ps $(SERVICE_NAME)

# Stop and remove the container and volumes
clean:
	@echo "Cleaning up PostgreSQL container and volumes..."
	docker compose down
	@echo "PostgreSQL container and volumes removed"

# More advanced clean that also removes volumes
clean-all:
	@echo "Removing PostgreSQL container, volumes, and data..."
	docker compose down -v
	@echo "PostgreSQL container, volumes, and data removed"

wait-for-db:
	@for i in $$(seq 1 30); do \
		if docker exec $(SERVICE_NAME) pg_isready -U $(DB_USER) -d $(DB_NAME) > /dev/null 2>&1; then \
			echo "Database is ready!"; \
			exit 0; \
		fi; \
		echo "Waiting for database to be ready... $$i/30"; \
		sleep 1; \
	done; \
	echo "ERROR: Database did not become ready in time"; \
	exit 1

reset-table:
	@echo "Resetting employees table..."
	@docker exec $(SERVICE_NAME) psql -U $(DB_USER) -d $(DB_NAME) -c "TRUNCATE TABLE employees RESTART IDENTITY;" || \
		(echo "Failed to reset table. Is the database running?"; exit 1)
	@echo "Table reset complete."

.PHONY: reset-db
reset-db: stop clean-all start
	@sleep 3

.PHONY: get-connector
get-connector:
	@echo "Fetching latest commit from $(POSTGRES_BRANCH) branch..."
	@latest_commit=$$(git ls-remote $(POSTGRES_REPO) refs/heads/$(POSTGRES_BRANCH) | cut -f1); \
	if [ -z "$$latest_commit" ]; then \
		echo "Error: Branch $(POSTGRES_BRANCH) not found in repository"; \
		exit 1; \
	fi; \
	echo "Found commit: $$latest_commit"; \
	go get github.com/conduitio/conduit-connector-postgres@$$latest_commit
	@go mod tidy
	@echo "Updated to latest commit from $(POSTGRES_BRANCH)"

.PHONY: run-with-version
run-with-version: reset-db get-connector run

.PHONY: run
run:
	@echo "Running main.go..."
	@go run main.go || (echo "Error running main.go"; exit 1)

# Run the main.go application with custom record count
run-custom: start reset-table
	@if [ -z "$(RECORDS)" ]; then \
		echo "Error: RECORDS parameter is required. Usage: make run-custom RECORDS=5000"; \
		exit 1; \
	fi
	@echo "Running main.go with $(RECORDS) records..."
	@go run main.go $(RECORDS) || \
		(echo "Error running main.go"; exit 1)
