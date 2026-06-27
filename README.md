# abeiplinux

`abeiplinux` is a small declarative geo firewall for `nftables` on Debian and
Ubuntu. You describe, per port, which countries or regions are allowed, and the
tool builds and maintains the `nftables` rules for you:

- per-port, per-country/region allow and deny rules from a simple `rules.conf`,
- blocks addresses from the AbuseIPDB blacklist on every managed port,
- always allows a configurable whitelist of trusted IPs,
- downloads only the country zones your rules actually use, with a local cache,
- refreshes the rules twice a day through a `systemd` timer,
- validates the `nftables` file before loading it and replaces it atomically.

## The model

You write rules like sentences in `/etc/abeiplinux/rules.conf`:

```text
# action  proto  port   geo
allow      tcp    22     europe
allow      tcp    5060   de
allow      udp    5060   de
allow      tcp    5061   us
deny       tcp    5060   ru,cn
allow      tcp    443    any
```

Two simple guarantees:

- A port that appears in any `allow` rule is **closed by default**: only the
  listed sources get in, everyone else is dropped.
- A port you never mention is **left untouched**.

On top of every managed port, the whitelist always wins and the AbuseIPDB
blacklist is always dropped.

### Fields

- `action` - `allow` or `deny`. `deny` drops a geo without closing the port for
  everyone else, and is evaluated before `allow`.
- `proto` - `tcp` or `udp`.
- `port` - a single port number.
- `geo` - one or more country codes (ISO 3166-1 alpha-2, lowercase), region
  names, comma-separated, or `any`.

## Requirements

- Debian or Ubuntu
- `systemd`, `nftables`, `curl`
- root access
- an AbuseIPDB API key, if you want to use the AbuseIPDB blacklist

Without an AbuseIPDB key the script still works; the AbuseIPDB sets stay empty.

## Installation

```sh
cd /root/abeiplinux
sudo ./install.sh
```

The installer:

- installs `curl`, `nftables`, and `ca-certificates`,
- copies the script to `/usr/local/sbin/abeiplinux-update`,
- creates `/etc/abeiplinux/abeiplinux.conf` and `/etc/abeiplinux/rules.conf`,
- installs `abeiplinux.service` and `abeiplinux.timer`,
- enables the service at boot and the twice-daily timer.

## Configuration

Two files live in `/etc/abeiplinux`:

- `rules.conf` - the per-port geo rules (see above).
- `abeiplinux.conf` - the AbuseIPDB key, the whitelist, region definitions, and
  the zone cache TTL.

After editing either file, apply the changes:

```sh
sudo systemctl start abeiplinux.service
```

### AbuseIPDB

```sh
ABUSEIPDB_API_KEY="your-api-key"
ABUSEIPDB_CONFIDENCE_MINIMUM="90"
ABUSEIPDB_LIMIT="10000"
ABUSEIPDB_DAYS="30"
```

- `ABUSEIPDB_API_KEY` - AbuseIPDB API key.
- `ABUSEIPDB_CONFIDENCE_MINIMUM` - minimum abuse confidence score.
- `ABUSEIPDB_LIMIT` - maximum number of entries to download.
- `ABUSEIPDB_DAYS` - how many days of AbuseIPDB history to consider.

### Whitelist (always-allow IPs)

`WHITELIST` keeps trusted addresses connected no matter what. Whitelisted IPs
can reach any port, even when they are outside an allowed geo or appear on the
AbuseIPDB blacklist:

```sh
WHITELIST="203.0.113.10 198.51.100.0/24 2001:db8::/48"
```

Space-separated, IPv4 and IPv6, single addresses or CIDR ranges. This is the
recommended way to protect your own admin IP from accidental lockout.

### Regions

Regions are macros that expand to a list of country codes. They are defined in
`abeiplinux.conf` as `REGION_<NAME>` variables and referenced by their
lowercased name in `rules.conf`:

```sh
REGION_EUROPE="ad al am at ... ua va xk"
REGION_NORTH_AMERICA="us ca mx"
REGION_NORDICS="dk fi is no se"      # add your own
```

`REGION_NORDICS` is then usable as `nordics` in a rule. Built-in defaults:
`europe`, `north_america`, `south_america`, `oceania`.

### Zone cache

```sh
ZONE_CACHE_HOURS="20"
```

Downloaded country zones are reused for this many hours before being refreshed.

## Manual run

```sh
sudo /usr/local/sbin/abeiplinux-update
```

## Status checks

```sh
systemctl status abeiplinux.timer
systemctl list-timers --all abeiplinux.timer
systemctl status abeiplinux.service
journalctl -u abeiplinux.service -n 100 --no-pager
```

Active rules and cached data:

```sh
nft list table inet abeiplinux
nft list chain inet abeiplinux input
ls /var/lib/abeiplinux/zones
```

## How the rules are built

For the example `rules.conf` above, the generated chain looks like this
(IPv6 lines omitted for brevity):

```text
chain input {
    type filter hook input priority -100; policy accept;
    ct state established,related accept

    ip saddr @whitelist4 accept                       # whitelist wins first
    tcp dport { 22, 443, 5060, 5061 } ip saddr @abuse4 drop
    udp dport { 5060 } ip saddr @abuse4 drop

    tcp dport 5060 ip saddr @g_ru_cn4 drop            # explicit deny

    tcp dport 22   ip saddr @g_europe4 accept         # geo allows
    tcp dport 5060 ip saddr @g_de4     accept
    udp dport 5060 ip saddr @g_de4     accept
    tcp dport 5061 ip saddr @g_us4     accept
    tcp dport 443  accept                             # "any"

    tcp dport { 22, 5060, 5061 } drop                 # deny-by-default
}
```

The table is replaced atomically: the generated file recreates the table in a
single `nft -f` load, so there is no moment in which the rules are missing. The
chain hooks `input` at priority `-100` and the chain policy is `accept`, so only
the ports you manage are affected; nothing else is touched.

The tool fails safe: if a required country zone cannot be downloaded and there is
no cached copy, the update aborts and leaves the previous ruleset in place rather
than risk closing a port with an empty allow set.

## Access safety

Before geo-fencing the port you use for SSH, make sure your current IP is inside
an allowed geo, or add it to `WHITELIST`. If you have access through your VPS
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
are picked up faster) and means a single failed run does not leave you a full day
out of date. The `ZONE_CACHE_HOURS` setting keeps the second daily run from
re-downloading what the first one already fetched. To change the cadence, edit
`OnCalendar=` in `/etc/systemd/system/abeiplinux.timer` and run
`systemctl daemon-reload`.

## Uninstall

```sh
cd /root/abeiplinux
sudo ./uninstall.sh
```

Removes the active `nftables` table, the systemd units, the script, and
`/etc/nftables.d/abeiplinux.nft`. Leaves `/etc/abeiplinux` and
`/var/lib/abeiplinux` in place.

## Data sources

- AbuseIPDB blacklist API: `https://api.abuseipdb.com/api/v2/blacklist`
- Country IP prefixes: `https://www.ipdeny.com`

## Notes

`abeiplinux` only touches the ports listed in `rules.conf`. It does not set a
default `DROP` policy for the whole system and does not close other ports.
