#!/bin/sh
# Every how-to run where it is installed, end to end: an install, a
# how-to's boot deployed in it (haiccing/base-package-howto, at howtos),
# then each how-to with a script run through by the runner, howto/run,
# one after the other in the same scene (each run throws it away first);
# one that needs Docker skipped with the reason when no daemon answers;
# torn down, nothing left. Each how-to timed.
#   sh test/howtos.sh [--keep] [<org>/<package>/<name>...]
#     --keep    the temporary folder left as it is, its runtimes running (printed)
#     a key     only those how-tos (every one with a steps.haicc by default)
#   SOURCES     as for run.sh, the splectral packages' bundles in it too; without one: skipped
# One line a how-to (ok, not ok, ok # skip), what did not pass under it,
# the count last; exit 0 passed, 1 failed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
pkg=$(cd "$here/.." && pwd)
dev=$(cd "$pkg/../.." && pwd)
keep=no
[ "${1:-}" = --keep ] && { keep=yes; shift; }
HAICC_HOME=$pkg . "$pkg/bin/haicc-lib.sh"   # the pins, this machine's Bare chosen
SOURCES=${SOURCES:-$pkg/../../sources}
for f in "$HAICC_ORG/$APP_PACKAGE.bundle" "$HAICC_ORG/base-package-howto.bundle" "$BARE_FILE"; do
  [ -f "$SOURCES/$f" ] || { echo "skipped: no $f in $SOURCES (SOURCES: a sources folder)"; exit 0; }
done
SOURCES=$(cd "$SOURCES" && pwd)
n=0; failed=0
ok () { n=$((n + 1)); echo "ok $n - $1"; }
no () { n=$((n + 1)); failed=$((failed + 1)); echo "not ok $n - $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/  # /'; }
ms () { echo $(( $(date +%s%N) / 1000000 )); }
T=$(mktemp -d "${TMPDIR:-/tmp}/haicc-howtos.XXXXXX")
H=$T/home
cleanup () {
  if [ "$keep" = yes ]; then echo "kept: $T"; return; fi
  PATH=$T/bin:$PATH HAICC_HOME=$H haicc boot/teardown >/dev/null 2>&1
  case "$T" in "${TMPDIR:-/tmp}"/haicc-howtos.*) rm -rf "$T" ;; esac
}
trap cleanup EXIT
haicc () { PATH=$T/bin:$PATH HAICC_HOME=$H HAICC_TIMEOUT=900 "$T/bin/haicc" "$@" 2>&1; }
# Docker: what a how-to that needs it runs on
docker info >/dev/null 2>&1 && docker=yes || docker=no

# the how-tos: every one with a script, by its key <org>/<package>/<name>
keys=${*:-$(cd "$dev" && find haiccing splectral -path '*/howto/*/steps.haicc' -not -path '*/modules/*' | sort | sed 's#/howto/#/#; s#/steps.haicc$##')}

sh "$pkg/haicc-install.sh" --home="$H" --bin="$T/bin" >/dev/null
haicc sources link "$SOURCES" >/dev/null; haicc prereq >/dev/null
out=$(haicc boot/deploy); [ $? -eq 0 ] && ok "haicc boot/deploy" || { no "haicc boot/deploy" "$out"; exit 1; }
out=$(haicc --output . boot/deploy howtos haiccing/base-package-howto)
case "$out" in *'"deployed":"howtos"'*) ok "a how-to's boot deployed, at howtos" ;; *) no "a how-to's boot deployed" "$out"; exit 1 ;; esac

for k in $keys; do
  script="$dev/$(echo "$k" | sed 's#^\([^/]*/[^/]*\)/#\1/howto/#')/steps.haicc"
  if [ -f "$script" ] && grep -q '^# needs:.*docker' "$script" && [ "$docker" = no ]; then n=$((n + 1)); echo "ok $n - $k # skip needs docker, no daemon answers"; continue; fi
  s=$(ms)
  # its answer in natural language: passed, or where not and why
  out=$(haicc howtos howto/run . "$k")
  t=$(( $(ms) - s ))
  case "$out" in
    "$k: passed,"*) ok "$k ($t ms)" ;;
    *) no "$k ($t ms)" "$(printf '%s\n' "$out" | head -20)" ;;
  esac
done
out=$(haicc --output howtos howto/reset .); case "$out" in *'"reset":true'*) ok "the scene thrown away" ;; *) no "the scene thrown away" "$out" ;; esac
out=$(haicc boot/teardown); [ $? -eq 0 ] && ok "haicc boot/teardown" || no "haicc boot/teardown" "$out"
is_left=$(pgrep -f -- "[/]bin/bare $T/" | wc -l | tr -d ' ')
[ "$is_left" -eq 0 ] && ok "nothing of the install left running" || no "nothing of the install left running" "$is_left left"
[ "$docker" = no ] || { left=$(docker ps -aq --filter "label=haicc.folder" | wc -l | tr -d ' '); [ "$left" -eq 0 ] && ok "no container left" || no "no container left" "$left left"; }

echo "# checks = $((n - failed))/$n pass"
[ "$failed" -eq 0 ] && { echo "# ok"; exit 0; }
echo "# not ok"; exit 1
