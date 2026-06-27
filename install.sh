#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo ./install.sh" >&2
	exit 1
fi

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if ! command -v apt-get >/dev/null 2>&1; then
	echo "This installer supports Debian/Ubuntu systems with apt-get." >&2
	exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl nftables ca-certificates

install -d -m 0755 /etc/abeiplinux /etc/nftables.d /var/lib/abeiplinux /var/lib/abeiplinux/zones /usr/local/sbin
install -m 0755 "${BASE_DIR}/bin/abeiplinux-update" /usr/local/sbin/abeiplinux-update

if [ ! -f /etc/abeiplinux/abeiplinux.conf ]; then
	install -m 0600 "${BASE_DIR}/etc/abeiplinux.conf.example" /etc/abeiplinux/abeiplinux.conf
else
	echo "Keeping existing /etc/abeiplinux/abeiplinux.conf"
fi

if [ ! -f /etc/abeiplinux/rules.conf ]; then
	install -m 0644 "${BASE_DIR}/etc/rules.conf.example" /etc/abeiplinux/rules.conf
else
	echo "Keeping existing /etc/abeiplinux/rules.conf"
fi

install -m 0644 "${BASE_DIR}/systemd/abeiplinux.service" /etc/systemd/system/abeiplinux.service
install -m 0644 "${BASE_DIR}/systemd/abeiplinux.timer" /etc/systemd/system/abeiplinux.timer

systemctl daemon-reload
systemctl enable abeiplinux.service
systemctl enable --now abeiplinux.timer

echo "Installed abeiplinux."
echo "Edit /etc/abeiplinux/abeiplinux.conf (ABUSEIPDB_API_KEY, WHITELIST, regions)"
echo "and /etc/abeiplinux/rules.conf (per-port geo rules), then run:"
echo "  systemctl start abeiplinux.service"
