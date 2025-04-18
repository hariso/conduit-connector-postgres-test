# Makefile for managing PostgreSQL container

# Variables
SERVICE_NAME = test-pg-connector
DEFAULT_RECORDS = 10000000
DB_USER = meroxauser
DB_NAME = meroxadb
DB_HOST = localhost
DB_PORT = 5432

# Declare phony targets
.PHONY: start stop restart logs status clean clean-all help run run-custom reset-table wait-for-db

# Default target
help:
	@echo "Available commands:"
	@echo "  make start       - Start the PostgreSQL container in detached mode"
	@echo "  make stop        - Stop the PostgreSQL container"
	@echo "  make restart     - Restart the PostgreSQL container"
	@echo "  make logs        - Show logs from the PostgreSQL container"
	@echo "  make status      - Check the status of the PostgreSQL container"
	@echo "  make clean       - Stop and remove the container and volumes"
	@echo "  make run         - Run main.go with default $(DEFAULT_RECORDS) records"
	@echo "  make run-custom  - Run main.go with custom record count (e.g., make run-custom RECORDS=5000)"
	@echo "  make reset-table - Reset the employees table (clear all data)"
	@echo "  make help        - Show this help message"

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

# Wait for the database to be ready
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

# Reset the employees table
reset-table:
	@echo "Resetting employees table..."
	@docker exec $(SERVICE_NAME) psql -U $(DB_USER) -d $(DB_NAME) -c "TRUNCATE TABLE employees RESTART IDENTITY;" || \
		(echo "Failed to reset table. Is the database running?"; exit 1)
	@echo "Table reset complete."

.PHONY: reset-db
reset-db: stop clean-all start
	@sleep 3

.PHONY: run-with-updated-version
run-with-updated-version: reset-db
	@go get github.com/conduitio/conduit-connector-postgres@ab22ca81bb27
	@go mod tidy
	@echo "Running main.go..."
	@go run main.go || (echo "Error running main.go"; exit 1)

.PHONY: run-with-latest-version
run-with-latest-version: reset-db
	@go get github.com/conduitio/conduit-connector-postgres@latest
	@go mod tidy
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
