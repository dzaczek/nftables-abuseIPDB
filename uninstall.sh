#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo ./uninstall.sh" >&2
	exit 1
fi

systemctl disable --now abeiplinux.timer >/dev/null 2>&1 || true
systemctl disable --now abeiplinux.service >/dev/null 2>&1 || true

if command -v nft >/dev/null 2>&1 && nft list table inet abeiplinux >/dev/null 2>&1; then
	nft delete table inet abeiplinux
fi

rm -f /etc/systemd/system/abeiplinux.service
rm -f /etc/systemd/system/abeiplinux.timer
rm -f /usr/local/sbin/abeiplinux-update
rm -f /etc/nftables.d/abeiplinux.nft
systemctl daemon-reload

echo "Removed abeiplinux service, timer, script, and active nftables table."
echo "Left in place: /etc/abeiplinux and /var/lib/abeiplinux"
