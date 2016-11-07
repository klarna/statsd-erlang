PROJECT = statsd_erlang
PROJECT_DESCRIPTION = "StatsD client"
PROJECT_VERSION = 1.0.0

MORE_ERLC_OPTS = -DAPPLICATION=$(PROJECT)

include erlang.mk

ERLC_OPTS += $(MORE_ERLC_OPTS)

vsn-check:
	./vsn-check.sh $(PROJECT_VERSION)

hex-publish: distclean
	$(verbose) rebar3 hex publish

