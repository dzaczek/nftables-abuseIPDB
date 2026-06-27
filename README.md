# abeiplinux

`abeiplinux` builds `nftables` rules for SSH on Debian and Ubuntu:

- blocks addresses from the AbuseIPDB blacklist,
- optionally allows SSH connections only from European prefixes,
- always allows a configurable whitelist of trusted IPs,
- refreshes the rules daily through a `systemd` timer,
- validates the `nftables` file before loading it,
- stores the last downloaded lists in `/var/lib/abeiplinux`.

The default mode is a hardened SSH policy:

```text
whitelist     -> accept
AbuseIPDB     -> drop
Europe        -> accept
rest of world -> drop
```

## Requirements

- Debian or Ubuntu
- `systemd`
- `nftables`
- `curl`
- root access
- an AbuseIPDB API key, if you want to use the AbuseIPDB blacklist

Without an AbuseIPDB key the script still works, but it creates empty `abuse4` and `abuse6` sets.

## Installation

```sh
cd /root/abeiplinux
sudo ./install.sh
```

The installer:

- installs `curl`, `nftables`, and `ca-certificates`,
- copies the script to `/usr/local/sbin/abeiplinux-update`,
- creates the configuration at `/etc/abeiplinux/abeiplinux.conf`,
- installs `abeiplinux.service` and `abeiplinux.timer`,
- enables the service at boot and the daily timer.

## AbuseIPDB configuration

Edit:

```sh
sudo nano /etc/abeiplinux/abeiplinux.conf
```

Set:

```sh
ABUSEIPDB_API_KEY="your-api-key"
ABUSEIPDB_CONFIDENCE_MINIMUM="90"
ABUSEIPDB_LIMIT="10000"
ABUSEIPDB_DAYS="30"
```

Parameters:

- `ABUSEIPDB_API_KEY` - AbuseIPDB API key.
- `ABUSEIPDB_CONFIDENCE_MINIMUM` - minimum abuse confidence score.
- `ABUSEIPDB_LIMIT` - maximum number of entries to download.
- `ABUSEIPDB_DAYS` - how many days of AbuseIPDB history to consider.

After saving the configuration, run an update:

```sh
sudo systemctl start abeiplinux.service
```

## SSH and Europe configuration

Defaults:

```sh
SSH_PORT="22"
ENABLE_EUROPE_ALLOWLIST="yes"
```

If SSH runs on a different port:

```sh
SSH_PORT="2222"
```

If you want to use only AbuseIPDB without the Europe geo-block:

```sh
ENABLE_EUROPE_ALLOWLIST="no"
```

You change the country list in `COUNTRIES`. The format is ISO 3166-1 alpha-2 codes, lowercase.

## Whitelist (always-allow IPs)

Use `WHITELIST` to keep trusted addresses connected no matter what. Whitelisted
IPs can always reach SSH, even when they are outside the Europe allowlist or
appear on the AbuseIPDB blacklist:

```sh
WHITELIST="203.0.113.10 198.51.100.0/24 2001:db8::/48"
```

- Entries are space-separated.
- IPv4 and IPv6 are both supported and sorted into their own sets automatically.
- Single addresses and CIDR ranges are both accepted.
- The whitelist is checked first, before the AbuseIPDB and Europe rules.

This is the recommended way to protect your own admin IP from accidental lockout.

## Manual run

```sh
sudo /usr/local/sbin/abeiplinux-update
```

Or through systemd:

```sh
sudo systemctl start abeiplinux.service
```

## Status checks

Timer:

```sh
systemctl status abeiplinux.timer
systemctl list-timers --all abeiplinux.timer
```

Last run:

```sh
systemctl status abeiplinux.service
journalctl -u abeiplinux.service -n 100 --no-pager
```

Active rules:

```sh
nft list table inet abeiplinux_ssh
nft list chain inet abeiplinux_ssh input
```

Entry counts:

```sh
wc -l /var/lib/abeiplinux/*.set
```

## How the rules work

The script generates a table:

```text
table inet abeiplinux_ssh
```

Inside it, it creates the sets:

```text
allow4   - whitelist IPv4
allow6   - whitelist IPv6
europe4  - European IPv4 prefixes
europe6  - European IPv6 prefixes
abuse4   - AbuseIPDB IPv4
abuse6   - AbuseIPDB IPv6
```

The `input` chain has priority `-100`, so the rules are evaluated early:

```text
ct state established,related accept
tcp dport 22 ip saddr @allow4 accept
tcp dport 22 ip6 saddr @allow6 accept
tcp dport 22 ip saddr @abuse4 drop
tcp dport 22 ip6 saddr @abuse6 drop
tcp dport 22 ip saddr @europe4 accept
tcp dport 22 ip6 saddr @europe6 accept
tcp dport 22 drop
```

Order matters: the whitelist wins first, then AbuseIPDB is dropped before the
Europe allowlist is applied.

The table is replaced atomically: the generated file recreates the table in a
single `nft -f` load, so there is no moment in which the SSH rules are missing.

## Access safety

Before enabling the geo-block, make sure your current IP address is inside the
allowed range, or add it to `WHITELIST`. If you have access through your VPS
provider's emergency console, keep it as a recovery plan.

Recommended SSH configuration:

```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
```

## Update schedule

The timer runs the update:

- 2 minutes after system boot,
- twice a day (03:00 and 15:00),
- with a randomized delay of up to 30 minutes.

The upstream `ipdeny.com` country zones are regenerated once a day, so refreshing
more often than daily does not return fresher data. The twice-a-day schedule
shortens the staleness window (so IP allocations that migrate between countries
are picked up faster) and means a single failed run does not leave you a full
day out of date. To change the cadence, edit `OnCalendar=` in
`/etc/systemd/system/abeiplinux.timer` and run `systemctl daemon-reload`.

Check the next run:

```sh
systemctl list-timers --all abeiplinux.timer
```

## Uninstall

```sh
cd /root/abeiplinux
sudo ./uninstall.sh
```

The script removes:

- the active `nftables` table,
- the systemd units,
- `/usr/local/sbin/abeiplinux-update`,
- `/etc/nftables.d/abeiplinux.nft`.

It leaves in place:

- `/etc/abeiplinux`,
- `/var/lib/abeiplinux`.

## Data sources

- AbuseIPDB blacklist API: `https://api.abuseipdb.com/api/v2/blacklist`
- European IP prefixes: `https://www.ipdeny.com`

## Notes

`abeiplinux` only touches the SSH port set in `SSH_PORT`. It does not set a
default `DROP` policy for the whole system and does not close other ports.
