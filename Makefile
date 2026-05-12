SHELL := /usr/bin/env bash

.PHONY: test demo pipeline report clean-alerts

test:
	bash services/m4_integration/m4_integration_tests.sh all

demo:
	bash services/m4_integration/complete_pipeline.sh demo

pipeline:
	sudo bash services/m4_integration/complete_pipeline.sh run

report:
	cd reports/latex && pdflatex chabahroot_report.tex

clean-alerts:
	rm -rf /tmp/chabah_detection_state /tmp/chabah_pipeline_state
