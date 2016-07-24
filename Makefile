# Project settings
PROJECT := PythonTemplateDemo
PACKAGE := demo
REPOSITORY := jacebrowning/template-python-demo
DIRECTORIES := $(PACKAGE) tests
FILES := Makefile setup.py $(shell find $(DIRECTORIES) -name '*.py')

# Python settings
ifndef TRAVIS
	PYTHON_MAJOR ?= 3
	PYTHON_MINOR ?= 5
endif

# System paths
PLATFORM := $(shell python -c 'import sys; print(sys.platform)')
ifneq ($(findstring win32, $(PLATFORM)), )
	WINDOWS := true
	SYS_PYTHON_DIR := C:\\Python$(PYTHON_MAJOR)$(PYTHON_MINOR)
	SYS_PYTHON := $(SYS_PYTHON_DIR)\\python.exe
	# https://bugs.launchpad.net/virtualenv/+bug/449537
	export TCL_LIBRARY=$(SYS_PYTHON_DIR)\\tcl\\tcl8.5
else
	ifneq ($(findstring darwin, $(PLATFORM)), )
		MAC := true
	else
		LINUX := true
	endif
	SYS_PYTHON := python$(PYTHON_MAJOR)
	ifdef PYTHON_MINOR
		SYS_PYTHON := $(SYS_PYTHON).$(PYTHON_MINOR)
	endif
endif

# Virtual environment paths
ENV := env
ifneq ($(findstring win32, $(PLATFORM)), )
	BIN := $(ENV)/Scripts
	ACTIVATE := $(BIN)/activate.bat
	OPEN := cmd /c start
else
	BIN := $(ENV)/bin
	ACTIVATE := . $(BIN)/activate
	ifneq ($(findstring cygwin, $(PLATFORM)), )
		OPEN := cygstart
	else
		OPEN := open
	endif
endif

# Virtual environment executables
ifndef TRAVIS
	BIN_ := $(BIN)/
endif
PYTHON := $(BIN_)python
PIP := $(BIN_)pip
EASY_INSTALL := $(BIN_)easy_install
RST2HTML := $(PYTHON) $(BIN_)rst2html.py
PDOC := $(PYTHON) $(BIN_)pdoc
MKDOCS := $(BIN_)mkdocs
PEP8 := $(BIN_)pep8
PEP8RADIUS := $(BIN_)pep8radius
PEP257 := $(BIN_)pep257
PYLINT := $(BIN_)pylint
PYREVERSE := $(BIN_)pyreverse
NOSE := $(BIN_)nosetests
PYTEST := $(BIN_)py.test
COVERAGE := $(BIN_)coverage
COVERAGE_SPACE := $(BIN_)coverage.space
SNIFFER := $(BIN_)sniffer
HONCHO := PYTHONPATH=$(PWD) $(ACTIVATE) && $(BIN_)honcho

# Flags for PHONY targets
INSTALLED_FLAG := $(ENV)/.installed
DEPENDS_CI_FLAG := $(ENV)/.depends-ci
DEPENDS_DOC_FLAG := $(ENV)/.depends-doc
DEPENDS_DEV_FLAG := $(ENV)/.depends-dev
ALL_FLAG := $(ENV)/.all

# MAIN TASKS ###################################################################

.PHONY: all
all: depends doc $(ALL_FLAG)
$(ALL_FLAG): $(FILES)
	make check
	@ touch $@  # flag to indicate all setup steps were successful

.PHONY: ci
ci: check test ## Run all targets that determine CI status

.PHONY: watch
watch: depends .clean-test ## Continuously run all CI targets when files chanage
	@ rm -rf $(FAILED_FLAG)
	$(SNIFFER)

# SYSTEM DEPENDENCIES ##########################################################

.PHONY: doctor
doctor:  ## Confirm system dependencies are available
	@ echo "Checking Python version:"
	@ python --version | tee /dev/stderr | grep -q "3.5."

# PROJECT DEPENDENCIES #########################################################

.PHONY: env
env: $(PIP) $(INSTALLED_FLAG)
$(INSTALLED_FLAG): Makefile setup.py requirements.txt
	$(PYTHON) setup.py develop
	@ touch $@  # flag to indicate package is installed

$(PIP):
	$(SYS_PYTHON) -m venv --clear $(ENV)
	$(PYTHON) -m pip install --upgrade pip setuptools

.PHONY: depends
depends: depends-ci depends-doc depends-dev ## Install all project dependnecies

.PHONY: depends-ci
depends-ci: env Makefile $(DEPENDS_CI_FLAG)
$(DEPENDS_CI_FLAG): Makefile
	$(PIP) install --upgrade pep8 pep257 pylint coverage coverage.space nose nose-cov expecter
	@ touch $@  # flag to indicate dependencies are installed

.PHONY: depends-doc
depends-doc: env Makefile $(DEPENDS_DOC_FLAG)
$(DEPENDS_DOC_FLAG): Makefile
	$(PIP) install --upgrade pylint docutils readme pdoc mkdocs pygments
	@ touch $@  # flag to indicate dependencies are installed

.PHONY: depends-dev
depends-dev: env Makefile $(DEPENDS_DEV_FLAG)
$(DEPENDS_DEV_FLAG): Makefile
	$(PIP) install --upgrade pip pep8radius wheel sniffer honcho
ifdef WINDOWS
	$(PIP) install --upgrade pywin32
else ifdef MAC
	$(PIP) install --upgrade pync MacFSEvents==0.4
else ifdef LINUX
	$(PIP) install --upgrade pyinotify
endif
	@ touch $@  # flag to indicate dependencies are installed

# CHECKS #######################################################################

.PHONY: check
check: pep8 pep257 pylint ## Run all static analysis targets

.PHONY: pep8
pep8: depends-ci ## Check for convention issues
	$(PEP8) $(DIRECTORIES) --config=.pep8rc

.PHONY: pep257
pep257: depends-ci ## Check for docstring issues
	$(PEP257) $(DIRECTORIES)

.PHONY: pylint
pylint: depends-ci ## Check for code issues
	$(PYLINT) $(DIRECTORIES) --rcfile=.pylintrc

.PHONY: fix
fix: depends-dev
	$(PEP8RADIUS) --docformatter --in-place

# TESTS ########################################################################

RANDOM_SEED ?= $(shell date +%s)

NOSE_OPTS := --with-doctest --with-cov --cov=$(PACKAGE) --cov-report=html

.PHONY: test
test: test-all

.PHONY: test-unit
test-unit: depends-ci .clean-test ## Run the unit tests
	$(NOSE) $(PACKAGE) $(NOSE_OPTS)
ifndef TRAVIS
ifndef APPVEYOR
	$(COVERAGE) report --show-missing --fail-under=$(UNIT_TEST_COVERAGE)
endif
endif

.PHONY: test-int
test-int: depends-ci .clean-test ## Run the integration tests
	$(NOSE) tests $(NOSE_OPTS)
ifndef TRAVIS
ifndef APPVEYOR
	$(COVERAGE) report --show-missing --fail-under=$(INTEGRATION_TEST_COVERAGE)
endif
endif

.PHONY: test-all
test-all: depends-ci .clean-test ## Run all the tests
	$(NOSE) $(DIRECTORIES) $(NOSE_OPTS) -xv
ifndef TRAVIS
ifndef APPVEYOR
	$(COVERAGE) report --show-missing --fail-under=$(COMBINED_TEST_COVERAGE)
endif
endif

.PHONY: read-coverage
read-coverage:
	$(OPEN) htmlcov/index.html

# DOCUMENTATION ################################################################

.PHONY: doc
doc: uml pdoc mkdocs ## Run all documentation targets

.PHONY: uml
uml: depends-doc docs/*.png ## Generate UML diagrams for classes and packages
docs/*.png: $(FILES)
	$(PYREVERSE) $(PACKAGE) -p $(PACKAGE) -a 1 -f ALL -o png --ignore tests
	- mv -f classes_$(PACKAGE).png docs/classes.png
	- mv -f packages_$(PACKAGE).png docs/packages.png

.PHONY: pdoc
pdoc: depends-doc pdoc/$(PACKAGE)/index.html  ## Generate API documentaiton from the code
pdoc/$(PACKAGE)/index.html: $(FILES)
	$(PDOC) --html --overwrite $(PACKAGE) --html-dir docs/apidocs

.PHONY: mkdocs
mkdocs: depends-doc site/index.html ## Build the documentation with mkdocs
site/index.html: mkdocs.yml docs/*.md
	ln -sf `realpath README.md --relative-to=docs` docs/index.md
	ln -sf `realpath CHANGELOG.md --relative-to=docs/about` docs/about/changelog.md
	ln -sf `realpath CONTRIBUTING.md --relative-to=docs/about` docs/about/contributing.md
	ln -sf `realpath LICENSE.md --relative-to=docs/about` docs/about/licence.md
	$(MKDOCS) build --clean --strict

.PHONY: mkdocs-live
mkdocs-live: depends-doc ## Launch and continuously rebuild the mkdocs site
	eval "sleep 3; open http://127.0.0.1:8000" &
	$(MKDOCS) serve

# RELEASE ######################################################################

.PHONY: register-test
register-test: README.rst CHANGELOG.rst ## Register the project on the test PyPI
	$(PYTHON) setup.py register --strict --repository https://testpypi.python.org/pypi

.PHONY: register
register: README.rst CHANGELOG.rst ## Register the project on PyPI
	$(PYTHON) setup.py register --strict

.PHONY: upload-test
upload-test: register-test ## Upload the current version to the test PyPI
	$(PYTHON) setup.py sdist upload --repository https://testpypi.python.org/pypi
	$(PYTHON) setup.py bdist_wheel upload --repository https://testpypi.python.org/pypi
	$(OPEN) https://testpypi.python.org/pypi/$(PROJECT)

.PHONY: upload
upload: .git-no-changes register ## Upload the current version to PyPI
	$(PYTHON) setup.py check --restructuredtext --strict --metadata
	$(PYTHON) setup.py sdist upload
	$(PYTHON) setup.py bdist_wheel upload
	$(OPEN) https://pypi.python.org/pypi/$(PROJECT)

.PHONY: .git-no-changes
.git-no-changes:
	@ if git diff --name-only --exit-code;        \
	then                                          \
		echo Git working copy is clean...;        \
	else                                          \
		echo ERROR: Git working copy is dirty!;   \
		echo Commit your changes and try again.;  \
		exit -1;                                  \
	fi;

%.rst: %.md
	pandoc -f markdown_github -t rst -o $@ $<

# CLEANUP ######################################################################

.PHONY: clean
clean: .clean-dist .clean-test .clean-doc .clean-build
	rm -rf $(ALL_FLAG)

.PHONY: clean-all
clean-all: clean .clean-env .clean-workspace

.PHONY: .clean-build
.clean-build:
	find $(DIRECTORIES) -name '*.pyc' -delete
	find $(DIRECTORIES) -name '__pycache__' -delete
	rm -rf $(INSTALLED_FLAG) *.egg-info

.PHONY: .clean-doc
.clean-doc:
	rm -rf README.rst docs/apidocs *.html docs/*.png site

.PHONY: .clean-test
.clean-test:
	rm -rf .cache .pytest .coverage htmlcov

.PHONY: .clean-dist
.clean-dist:
	rm -rf dist build

.PHONY: .clean-env
.clean-env: clean
	rm -rf $(ENV)

.PHONY: .clean-workspace
.clean-workspace:
	rm -rf *.sublime-workspace

# HELP #########################################################################

.PHONY: help
help: all
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
