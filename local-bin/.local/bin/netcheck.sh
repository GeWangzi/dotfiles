#!/usr/bin/env bash
# Triage "the internet stopped working" on this laptop, layer by layer.
#
# The point is to tell apart three very different failures that all feel
# identical from a browser:
#
#   1. the wifi link is down
#   2. wifi is fine but the sing-box proxy tunnel has stalled
#   3. everything is fine and the problem is somewhere else
#
# Note that `systemctl is-active sing-box` does NOT distinguish these. sing-box
# stays "active" while its upstream proxy is silently dead, because the process
# is still running. Test the path, not the process.
#
# Usage: bash ~/netcheck.sh

# Not hardcoded: removing iwd removed its 80-iwd.link, which had pinned kernel
# names, so on 2026-08-25 this interface went from wlan0 to wlp2s0. A script
# that reports "wifi down" because it looked at a stale name is worse than none.
WLAN="${NETCHECK_IFACE:-}"
if [[ -z "$WLAN" ]]; then
    for d in /sys/class/net/*/wireless; do
        [[ -e "$d" ]] || continue
        WLAN=$(basename "$(dirname "$d")")
        break
    done
fi
if [[ -z "$WLAN" ]]; then
    printf '  \033[31mFAIL\033[0m no wireless interface found\n'
    exit 1
fi
GW=$(ip route show default dev "$WLAN" 2>/dev/null | awk '{print $3; exit}')
SRC=$(ip -4 -o addr show "$WLAN" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

pass() { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

echo
echo "=== Layer 0: link ==="
state=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$WLAN" '$1==d {print $2}')
ssid=$(nmcli -t -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
if [[ "$state" == "connected" ]]; then
    pass "$WLAN connected to '${ssid:-?}' with address ${SRC:-none}"
else
    fail "$WLAN state is '${state:-unknown}'"
    echo "  -> wifi itself is down. Run wifi-doctor for the layer, or check:"
    echo "     journalctl -u NetworkManager -u wpa_supplicant -b | tail -30"
    exit 1
fi

echo
echo "=== Layer 1: LAN, bypassing the tunnel ==="
if [[ -n "$GW" ]] && ping -c2 -W2 -I "$WLAN" "$GW" >/dev/null 2>&1; then
    pass "gateway $GW reachable"
else
    fail "gateway ${GW:-unknown} unreachable"
    echo "  -> associated but no working LAN. Usually DHCP or the router."
    echo "  -> try: sudo nmcli device reapply $WLAN"
    exit 1
fi

echo
echo "=== Layer 2: internet, bypassing the tunnel ==="
direct=no
if ping -c2 -W3 -I "$WLAN" 1.1.1.1 >/dev/null 2>&1; then
    direct=yes
    pass "1.1.1.1 reachable directly over $WLAN"
else
    fail "no direct internet over $WLAN"
    echo "  -> upstream or ISP problem, nothing to do with sing-box"
fi

echo
echo "=== Layer 3: the sing-box tunnel ==="
echo "  (systemctl says: $(systemctl is-active sing-box) -- not proof of anything)"
code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' https://api.anthropic.com/ 2>/dev/null)
if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
    pass "https://api.anthropic.com/ answered HTTP $code through the tunnel"
    echo
    echo "Network path is healthy end to end."
else
    fail "no HTTP response through the tunnel (curl code '${code:-timeout}')"
    if [[ "$direct" == "yes" ]]; then
        echo
        echo "  Wifi is fine, the tunnel is not. This is the failure mode that"
        echo "  looks like 'wifi stopped working' but is not. Do NOT reboot."
        echo
        echo "    sudo systemctl restart sing-box"
        echo
        echo "  Then run this script again. If it still fails, the upstream"
        echo "  proxy server is down and no local fix will help."
        echo "  Recent detail: journalctl -u sing-box -b --no-pager | tail -30"
    fi
fi
echo
