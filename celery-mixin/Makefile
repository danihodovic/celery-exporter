JSONNET_FMT := jsonnetfmt -n 2 --max-blank-lines 2 --string-style s --comment-style s

all: fmt prometheus-alerts.yaml dashboards_out lint

fmt:
	find . -name 'vendor' -prune -o -name '*.libsonnet' -print -o -name '*.jsonnet' -print | \
		xargs -n 1 -- $(JSONNET_FMT) -i

prometheus-alerts.yaml: mixin.libsonnet config.libsonnet $(wildcard alerts/*)
	jsonnet -S alerts.jsonnet > $@

dashboards_out: mixin.libsonnet config.libsonnet $(wildcard dashboards/*)
	@mkdir -p dashboards_out
	jsonnet -J vendor -m dashboards_out dashboards.jsonnet

lint: prometheus-alerts.yaml
	find . -name 'vendor' -prune -o -name '*.libsonnet' -print -o -name '*.jsonnet' -print | \
		while read f; do \
			$(JSONNET_FMT) "$$f" | diff -u "$$f" -; \
		done

	promtool check rules prometheus-alerts.yaml

test: prometheus-alerts.yaml
	promtool test rules tests.yaml

clean:
	rm -rf dashboards_out prometheus-alerts.yaml
