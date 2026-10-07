# Steam Machine automation - controller-driven suspend/wake of the PC and the Sony TV.
#
#   sudo make install        install everything and activate it
#   make diff                compare the repo with what is installed right now
#   make check               syntax checks + scan for hardcoded user paths
#   sudo make uninstall      remove everything except the config
#
# Staged install (no root, nothing activated):  make install DESTDIR=/tmp/stage CONF_GROUP=

PREFIX     ?= /usr/local
BINDIR     ?= $(PREFIX)/bin
CONFDIR    ?= /etc/steam-machine
UDEVDIR    ?= /etc/udev/rules.d
SYSTEMDDIR ?= /etc/systemd/system
CONF_GROUP ?= wheel
DESTDIR    ?=

BIN_FILES  := controllers-active suspend-with-tv-off tv-control 8bitdo-suspend steam-controller-watch
UDEV_PLAIN := 70-usb-hub-wakeup.rules 73-steam-controller-wakeup.rules 75-bluetooth-no-wakeup.rules
UDEV_TMPL  := 72-8bitdo-suspend.rules
SED_VARS    = sed -e 's|@BINDIR@|$(BINDIR)|g'
STAGE      := $(CURDIR)/build/stage

.PHONY: help install install-bin install-config install-udev install-systemd activate \
        uninstall purge check diff check-root

help:
	@sed -n '3,8p' Makefile | sed 's/^# \{0,1\}//'

install: check-root install-bin install-config install-udev install-systemd activate
	@echo
	@echo "Done. Edit $(CONFDIR)/steam-machine.conf if the TV address, PSK or HDMI port changed."

check-root:
	@[ -n "$(DESTDIR)" ] || [ "$$(id -u)" = 0 ] || { echo "Run as root:  sudo make install"; exit 1; }

install-bin:
	@echo "==> scripts -> $(DESTDIR)$(BINDIR)"
	@for f in $(BIN_FILES); do install -D -m 0755 scripts/$$f $(DESTDIR)$(BINDIR)/$$f || exit 1; done

# Never overwrite an existing config (it holds the TV's PSK).
install-config:
	@dst="$(DESTDIR)$(CONFDIR)/steam-machine.conf"; \
	if [ -e "$$dst" ]; then \
	  echo "==> keeping existing $$dst (delete it and re-run to restore the repo defaults)"; \
	else \
	  grp=""; \
	  if [ -n "$(CONF_GROUP)" ] && getent group "$(CONF_GROUP)" >/dev/null 2>&1; then grp="-g $(CONF_GROUP)"; fi; \
	  install -D -m 0640 $$grp config/steam-machine.conf "$$dst" && echo "==> config -> $$dst"; \
	fi

install-udev:
	@echo "==> udev rules -> $(DESTDIR)$(UDEVDIR)"
	@install -d $(DESTDIR)$(UDEVDIR)
	@for f in $(UDEV_PLAIN); do install -m 0644 udev/$$f $(DESTDIR)$(UDEVDIR)/$$f || exit 1; done
	@for f in $(UDEV_TMPL); do $(SED_VARS) udev/$$f.in > $(DESTDIR)$(UDEVDIR)/$$f && chmod 0644 $(DESTDIR)$(UDEVDIR)/$$f || exit 1; done

install-systemd:
	@echo "==> systemd units -> $(DESTDIR)$(SYSTEMDDIR)"
	@install -d $(DESTDIR)$(SYSTEMDDIR)/systemd-suspend.service.d
	@$(SED_VARS) systemd/steam-controller-watch.service.in > $(DESTDIR)$(SYSTEMDDIR)/steam-controller-watch.service
	@$(SED_VARS) systemd/tv-wake.conf.in > $(DESTDIR)$(SYSTEMDDIR)/systemd-suspend.service.d/tv-wake.conf
	@chmod 0644 $(DESTDIR)$(SYSTEMDDIR)/steam-controller-watch.service $(DESTDIR)$(SYSTEMDDIR)/systemd-suspend.service.d/tv-wake.conf

activate:
ifeq ($(DESTDIR),)
	@echo "==> activating"
	systemctl daemon-reload
	udevadm control --reload-rules
	udevadm trigger --action=add --subsystem-match=usb
	systemctl enable --now steam-controller-watch.service
else
	@echo "==> staged install (DESTDIR set): skipping activation"
endif

uninstall: check-root
ifeq ($(DESTDIR),)
	-systemctl disable --now steam-controller-watch.service
endif
	@for f in $(BIN_FILES); do rm -f $(DESTDIR)$(BINDIR)/$$f; done
	@for f in $(UDEV_PLAIN) $(UDEV_TMPL); do rm -f $(DESTDIR)$(UDEVDIR)/$$f; done
	@rm -f $(DESTDIR)$(SYSTEMDDIR)/steam-controller-watch.service $(DESTDIR)$(SYSTEMDDIR)/systemd-suspend.service.d/tv-wake.conf
	@rmdir --ignore-fail-on-non-empty $(DESTDIR)$(SYSTEMDDIR)/systemd-suspend.service.d 2>/dev/null || true
ifeq ($(DESTDIR),)
	-systemctl daemon-reload
	-udevadm control --reload-rules
endif
	@echo "Removed. The config $(DESTDIR)$(CONFDIR) was kept (make purge deletes it)."

purge: uninstall
	rm -rf $(DESTDIR)$(CONFDIR)

check:
	@echo "==> syntax"
	@for f in $$(grep -l '^#!.*bash' bin/*); do bash -n $$f || exit 1; done
	@python3 -m py_compile bin/tv-control && rm -rf bin/__pycache__
	@if command -v shellcheck >/dev/null 2>&1; then echo "==> shellcheck"; shellcheck bin/controllers-active bin/suspend-with-tv-off bin/8bitdo-suspend bin/steam-controller-watch; else echo "(shellcheck not installed, skipped)"; fi
	@echo "==> hardcoded user paths"
	@if grep -rnE '/home/|/var/home/|\.local/share|~/' bin config systemd udev; then echo "FOUND hardcoded paths above"; exit 1; else echo "none"; fi

diff:
	@rm -rf $(STAGE)
	@$(MAKE) --no-print-directory install-bin install-config install-udev install-systemd DESTDIR=$(STAGE) CONF_GROUP= >/dev/null
	@cd $(STAGE) && find . -type f | sort | while read -r f; do \
	  live="$${f#.}"; \
	  if [ ! -e "$$live" ]; then echo "missing   $$live"; \
	  elif diff -q "$$live" "$$f" >/dev/null; then echo "same      $$live"; \
	  else echo "DIFFERS   $$live"; diff -u --label "installed" --label "repo" "$$live" "$$f" | sed 's/^/            /'; fi; \
	done
