#!/bin/bash
set -eEo pipefail

echo "melk: Epson ET-2850 printhead maintenance tooling (gutenprint + helper scripts)"

# ── WHY ──────────────────────────────────────────────────────────────────────
# The ET-2850 is set up driverless (IPP Everywhere / AirPrint) — great for printing,
# but that means NO Epson maintenance software, so a nozzle check / head clean can
# otherwise only be triggered from the printer's own front panel.
#
# gutenprint ships `escputil`, which generates the ESC/P2 remote-mode maintenance
# commands. escputil insists on opening its --raw-device O_RDWR, so it can't write
# straight to a pipe or socket (/dev/stdout piped to nc/socat fails with
# "Cannot open ... read/write: No such device or address"). The reliable, dependency-
# light path — and the one actually verified on this machine on 2026-08-03 — is:
#   1. escputil writes the command bytes to a regular temp file (RDWR-capable), then
#   2. those bytes are streamed to the printer's raw JetDirect port 9100 via bash's
#      built-in /dev/tcp. No nc/socat needed (nc isn't even installed here).
#
# This migration installs two helper scripts into ~/.local/bin:
#   printer-nozzle-check  — prints the 4-colour nozzle test pattern (negligible ink)
#   printer-head-clean    — runs one standard clean cycle (uses ink; guarded)
#
# The printer's address is resolved at RUNTIME over mDNS (avahi) rather than hardcoded,
# so DHCP reassignments don't break the scripts. Override with PRINTER_HOST=<ip|host>
# or by passing the host as the first argument.
#
# Idempotent: gutenprint install is skipped if already present; both scripts are
# rewritten with fixed content on every run. No changes in the read-only omarchy tree.

BIN_DIR="$HOME/.local/bin"
NOZZLE="$BIN_DIR/printer-nozzle-check"
CLEAN="$BIN_DIR/printer-head-clean"

# 1) Ensure gutenprint (provides escputil) ─────────────────────────────────────
if pacman -Qi gutenprint &>/dev/null; then
  echo "✓ gutenprint already installed (escputil present)."
else
  echo "Installing gutenprint (provides escputil)…"
  sudo pacman -S --needed --noconfirm gutenprint
  echo "✓ gutenprint installed."
fi

mkdir -p "$BIN_DIR"

# 2) printer-nozzle-check ───────────────────────────────────────────────────────
cat > "$NOZZLE" <<'NOZZLE_EOF'
#!/bin/bash
# Installed by omarchy-fast migration 0000000026.
# Print an Epson nozzle-check pattern on the ET-2850. Negligible ink.
# Usage: printer-nozzle-check [host]   (or PRINTER_HOST=<ip|host>)
set -euo pipefail
PORT=9100

command -v escputil >/dev/null 2>&1 || { echo "escputil not found — install gutenprint." >&2; exit 1; }

resolve_printer() {
  [[ -n "${PRINTER_HOST:-}" ]] && { echo "$PRINTER_HOST"; return; }
  [[ -n "${1:-}" ]] && { echo "$1"; return; }
  # mDNS: first IPv4 address advertised by the EPSON ET-2850 IPP service.
  # Capture avahi's cache dump into a var, then parse — a live `avahi-browse | awk`
  # pipeline leaves avahi lingering (awk exits before avahi is SIGPIPE'd), which
  # wedges the caller. `-t` makes avahi self-terminate; retry to cover a cold cache.
  local out addr i
  for i in 1 2 3; do
    out="$(timeout 5 avahi-browse -rpt _ipp._tcp 2>/dev/null || true)"
    addr="$(printf '%s\n' "$out" | awk -F';' '$1=="=" && $3=="IPv4" && $0 ~ /ET-2850/ {print $8; exit}')"
    [[ -n "$addr" ]] && { printf '%s\n' "$addr"; return 0; }
    [[ $i -lt 3 ]] && sleep 0.5
  done
  return 1
}

host="$(resolve_printer "${1:-}")"
[[ -n "$host" ]] || { echo "Could not find the EPSON ET-2850 on the network. Pass an IP/host or set PRINTER_HOST=<ip>." >&2; exit 1; }

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
escputil --nozzle-check --new --raw-device "$tmp" >/dev/null
timeout 10 bash -c 'cat "$1" > "/dev/tcp/$2/$3"' _ "$tmp" "$host" "$PORT"

echo "✓ Nozzle-check pattern sent to $host — check the printed page."
echo "  Complete stair-step lines = healthy; gaps/missing colour = clogged (run printer-head-clean)."
NOZZLE_EOF
chmod +x "$NOZZLE"
echo "✓ Installed $NOZZLE"

# 3) printer-head-clean ─────────────────────────────────────────────────────────
cat > "$CLEAN" <<'CLEAN_EOF'
#!/bin/bash
# Installed by omarchy-fast migration 0000000026.
# Run ONE standard head-clean cycle on the ET-2850. Consumes ink — guarded.
# Usage: printer-head-clean [-y] [host]   (or PRINTER_HOST=<ip|host>)
set -euo pipefail
PORT=9100

command -v escputil >/dev/null 2>&1 || { echo "escputil not found — install gutenprint." >&2; exit 1; }

yes=0; hostarg=""
for a in "$@"; do
  case "$a" in
    -y|--yes) yes=1 ;;
    *) hostarg="$a" ;;
  esac
done

resolve_printer() {
  [[ -n "${PRINTER_HOST:-}" ]] && { echo "$PRINTER_HOST"; return; }
  [[ -n "$hostarg" ]] && { echo "$hostarg"; return; }
  # Capture avahi's cache dump into a var, then parse — a live `avahi-browse | awk`
  # pipeline leaves avahi lingering (awk exits before avahi is SIGPIPE'd), which
  # wedges the caller. `-t` makes avahi self-terminate; retry to cover a cold cache.
  local out addr i
  for i in 1 2 3; do
    out="$(timeout 5 avahi-browse -rpt _ipp._tcp 2>/dev/null || true)"
    addr="$(printf '%s\n' "$out" | awk -F';' '$1=="=" && $3=="IPv4" && $0 ~ /ET-2850/ {print $8; exit}')"
    [[ -n "$addr" ]] && { printf '%s\n' "$addr"; return 0; }
    [[ $i -lt 3 ]] && sleep 0.5
  done
  return 1
}

host="$(resolve_printer)"
[[ -n "$host" ]] || { echo "Could not find the EPSON ET-2850 on the network. Pass an IP/host or set PRINTER_HOST=<ip>." >&2; exit 1; }

if [[ $yes -ne 1 ]]; then
  if [[ ! -t 0 ]]; then
    echo "Refusing to clean without -y in a non-interactive shell (head cleaning uses ink)." >&2
    exit 1
  fi
  read -rp "Head cleaning uses ink. Run a clean cycle on the ET-2850 at $host? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted — no clean performed."; exit 0; }
fi

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
escputil --clean-head --new --raw-device "$tmp" >/dev/null
timeout 10 bash -c 'cat "$1" > "/dev/tcp/$2/$3"' _ "$tmp" "$host" "$PORT"

echo "✓ Clean cycle started on $host (~30–60s; the printer will whir)."
echo "  Wait until it goes idle, then run 'printer-nozzle-check' to compare."
echo "  No improvement after 2–3 cleans → use the printer's own Power Cleaning or let it rest."
CLEAN_EOF
chmod +x "$CLEAN"
echo "✓ Installed $CLEAN"

echo "Migration completed successfully!"
