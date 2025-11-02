# Makefile derived from https://web.archive.org/web/20240205205603/https://venthur.de/2021-03-31-python-makefiles.html

# Get the directory this Makefile is sitting in
ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# system python interpreter. used only to create virtual environment
PY = python3
VENV = venv
BIN=$(ROOT_DIR)/$(VENV)/bin

SHELL_FILES := $(shell find $(ROOT_DIR)  -type f -name "*.sh" | grep -v $(VENV))

# By default, perform lints
all: bashate shellcheck 

# venv is used for ci linting purposes
$(VENV): requirements.txt
	$(PY) -m venv $(VENV)
	$(BIN)/pip install --upgrade -r requirements.txt
	touch $(VENV)

# Run bashate on all *.sh files in repo
.PHONY: bashate
bashate: $(VENV)
	$(BIN)/bashate $(SHELL_FILES)

# Run shellcheck on all *.sh files in repo
.PHONY: shellcheck
shellcheck: $(VENV)
	$(BIN)/shellcheck -x $(SHELL_FILES)

# Run yamllint on all *.y[a]ml files in repo
.PHONY: yamllint
yamllint: $(VENV)
	$(BIN)/yamllint -c $(ROOT_DIR)/.yamllint.yml .

# Clean venv and related files
clean:
	rm -rf $(VENV)
