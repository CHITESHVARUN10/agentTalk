.PHONY: help bootstrap build clean run setup-model xcode \
        rust-build rust-test rust-lint rust-fmt rust-fix

.DEFAULT_GOAL := help

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Fresh machine setup (prerequisites + xcodegen + deps + model)
	./scripts/bootstrap.sh

build: ## Build everything (Rust release + Swift app)
	./scripts/build.sh

clean: ## Clean all build artifacts
	./scripts/clean.sh

run: ## Build and launch AgentTalk
	./scripts/run.sh

setup-model: ## Download and verify the whisper model
	./scripts/setup-model.sh

xcode: ## Generate Xcode project from project.yml
	xcodegen generate --spec project.yml

rust-build: ## Build Rust core only (release)
	cd rust-core && cargo build --release

rust-build-debug: ## Build Rust core only (debug)
	cd rust-core && cargo build

rust-test: ## Run Rust tests
	cd rust-core && cargo test

rust-lint: ## Run clippy with strict warnings
	cd rust-core && cargo clippy -- -D warnings

rust-fmt: ## Check Rust formatting
	cd rust-core && cargo fmt -- --check

rust-fix: ## Auto-fix Rust formatting
	cd rust-core && cargo fmt

check: rust-test rust-lint rust-fmt ## Run all Rust checks
