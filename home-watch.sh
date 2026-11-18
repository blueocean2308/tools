#!/bin/bash
# Tu phuc hoi duong ham WireGuard + socks.
# Buoc 1: neu IP cua ten DDNS da doi -> chi cap nhat endpoint (wg set), khong khoi dong lai.
# Buoc 2: neu van loi -> ha/dung lai WireGuard va chay lai script socks.
IFACE=${IFACE:-homeclient}
CONF=${CONF:-/etc/wireguard/$IFACE.conf}
LOCK=${LOCK:-/run/home-watch.lock}
STAMP=${STAMP:-/run/home-watch.last}
LOG=${LOG:-/var/log/home-watch.log}
exec 9>"$LOCK"
flock -n 9 || exit 0
ok() { curl -s -m 12 --socks5-hostname 127.0.0.1:1080 "$1" >/dev/null; }
alive() { ok https://api.ipify.org || ok https://ifconfig.me; }
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }

refresh_endpoint() {
  local ep host port peer cur new
  [ -r "$CONF" ] || return 1
  ep=$(sed -n 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*//p' "$CONF" | head -n1 | tr -d '[:space:]')
  [ -n "$ep" ] || return 1
  host=${ep%:*}
  port=${ep##*:}
  [[ "$host" =~ ^[0-9.]+$ ]] && return 1
  new=$(getent ahostsv4 "$host" | awk '{print $1; exit}')
  [ -n "$new" ] || return 1
  peer=$(wg show "$IFACE" peers | head -n1)
  [ -n "$peer" ] || return 1
  cur=$(wg show "$IFACE" endpoints | awk -v p="$peer" '$1==p {print $2}')
  [ "$cur" = "$new:$port" ] && return 1
  wg set "$IFACE" peer "$peer" endpoint "$new:$port" || return 1
  say "DDNS $host doi IP: $cur -> $new:$port (wg set)"
  return 0
}

alive && exit 0

if refresh_endpoint; then
  sleep 5
  if alive; then say "phuc hoi sau khi cap nhat endpoint"; exit 0; fi
fi

now=$(date +%s)
last=$(cat "$STAMP" 2>/dev/null || echo 0)
[ $((now - last)) -lt 240 ] && exit 0
echo "$now" > "$STAMP"
say "socks loi -> khoi dong lai wg + socks"
wg-quick down "$IFACE" 2>/dev/null
wg-quick up "$IFACE" >> "$LOG" 2>&1
pkill -f microsocks 2>/dev/null || true
setsid /usr/local/bin/home-socks-up.sh >/dev/null 2>&1 < /dev/null &
sleep 5
if alive; then say "da phuc hoi"; else say "van loi"; fi
