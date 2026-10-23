# LFS458 — materiały szkoleniowe
#
# Makefile robi dwie rzeczy: przygotowuje stanowisko i renderuje slajdy.
# Pracą z labami zajmuje się ./bin/labctl i to on jest tu jedynym punktem
# wejścia — celowo nie owijamy go w cele make'a.

SHELL  := /bin/bash
LABCTL := ./bin/labctl

# Slajdy renderuje marp. Jeśli jest zainstalowany jako samodzielna binarka —
# używamy jej i Node nie jest potrzebny. Jeśli nie, spadamy na npx.
MARP        := $(shell command -v marp 2>/dev/null || echo "npx marp")
# marp-cli NIE ma opcji --port (-p to --preview); port serwera bierze
# wyłącznie ze zmiennej PORT, domyślnie 8080.
SLIDES_PORT ?= 8099

.DEFAULT_GOAL := help
.PHONY: help doctor setup test slides slides-html watch clean

help: ## ta pomoc
	@echo
	@echo "  LFS458 — materiały szkoleniowe"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36mmake %-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf "  Laby obsługuje labctl — make go nie owija:\n"
	@printf "    \033[36m%-22s\033[0m %s\n" "$(LABCTL) lab 01"   "prowadzona sesja: środowisko, zadanie po zadaniu"
	@printf "    \033[36m%-22s\033[0m %s\n" "$(LABCTL) check 01" "samo sprawdzenie, bez sesji"
	@printf "    \033[36m%-22s\033[0m %s\n" "$(LABCTL) doctor"   "stanowisko i stan środowisk"
	@printf "    \033[36m%-22s\033[0m %s\n" "$(LABCTL) --help"   "reszta poleceń"
	@echo

## ——— stanowisko ———————————————————————————————————————————————

doctor: ## sprawdza, czego brakuje na stanowisku
	@./scripts/zainstaluj.sh --sprawdz --slajdy

setup: ## doinstalowuje brakujące narzędzia do ~/.local/bin
	@./scripts/zainstaluj.sh --slajdy

## ——— materiały ————————————————————————————————————————————————

test: ## testy silnika sprawdzającego i walidacja materiałów
	@python3 tests/test_engine.py
	@$(LABCTL) validate

slides: ## prezentacje → build/pdf
	@mkdir -p build/pdf
	$(MARP) --config-file .marprc.yml --pdf --pdf-outlines --allow-local-files -I slides -o build/pdf

slides-html: ## prezentacje → build/html (działa offline)
	@mkdir -p build/html
	$(MARP) --config-file .marprc.yml --allow-local-files -I slides -o build/html
	@cp slides/nawigacja.js build/html/   # przechodzenie między rozdziałami
	@./scripts/indeks.py                  # spis rozdziałów (tryb serwera ma własny)

watch: ## podgląd slajdów na żywo (domyślnie http://localhost:8099)
	@echo "  podgląd: http://localhost:$(SLIDES_PORT)"
	PORT=$(SLIDES_PORT) $(MARP) --config-file .marprc.yml --server slides

clean: ## usuwa build/
	rm -rf build
