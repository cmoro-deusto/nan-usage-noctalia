# Run both checks over the plugin. They need lua (5.4) and python3 (3.11, for its
# TOML reader); the static one also wants network, and skips that part without it.
test:
	cd nan-usage && lua tests/shared_test.lua && lua tests/plugin_test.lua && python3 tests/plugin_check.py

.PHONY: test
