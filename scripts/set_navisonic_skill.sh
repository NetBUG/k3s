#!/usr/bin/env bash
#
# set_navisonic_skill.sh — write apps/asknavidrome/app/secret.sops.yaml: the
# Navidrome password of the `alexa` user and the Alexa skill ID, encrypted by the
# .sops.yaml rule (cluster age key) (docs/en/12-asknavidrome-alexa.md, step 3).
#
# Usage (from anywhere):
#   scripts/set_navisonic_skill.sh
#
# Both values are read from the terminal and piped straight into sops, so the
# plaintext never touches disk or shell history. Re-run to change either value;
# the old file is replaced only after sops succeeds.
set -euo pipefail

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

command -v sops >/dev/null || die "sops not found (brew install sops)."

# sops looks for .sops.yaml from the cwd, and matches its creation rule against
# the input path; stdin has none, so --filename-override names the target.
cd "$(dirname "$0")/.."
[ -f .sops.yaml ] || die "No .sops.yaml in $PWD."
OUT="apps/asknavidrome/app/secret.sops.yaml"
[ -d "$(dirname "$OUT")" ] || die "Missing $(dirname "$OUT")."

if [ -e "$OUT" ]; then
  read -rp "$OUT exists. Replace it? [y/N] " ans
  [[ "$ans" == [yY]* ]] || die "Aborted."
fi

read -rsp "Navidrome password for alexa: " NAVI_PASS; echo
[ -n "$NAVI_PASS" ] || die "Empty password."
read -rp "Alexa skill ID (amzn1.ask.skill.…): " NAVI_SKILL_ID
[[ "$NAVI_SKILL_ID" == amzn1.ask.skill.* ]] || die "Skill ID must start with amzn1.ask.skill."

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

TMP="$(mktemp "$OUT.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

# Values are base64 under `data`, so no YAML quoting can break on odd characters.
printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: asknavidrome\n  namespace: asknavidrome\ntype: Opaque\ndata:\n  NAVI_PASS: %s\n  NAVI_SKILL_ID: %s\n' \
    "$(b64 "$NAVI_PASS")" "$(b64 "$NAVI_SKILL_ID")" |
  sops -e --input-type yaml --output-type yaml --filename-override "$OUT" /dev/stdin > "$TMP"
unset NAVI_PASS NAVI_SKILL_ID

# Count the two values only: sops' own `mac:` is an ENC[...] line too.
[ "$(grep -cE '^ +NAVI_(PASS|SKILL_ID): ENC\[' "$TMP")" -eq 2 ] || die "Expected 2 encrypted values; $OUT left unchanged."
mv "$TMP" "$OUT"
trap - EXIT
log "Wrote $OUT (2 encrypted values). Commit it together with apps/asknavidrome/."
