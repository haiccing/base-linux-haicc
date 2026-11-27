#!/bin/sh
# The haicc command end to end, the working set: what is brought to the
# request so far (base-docs-hdlc, "Schema migration"). From the installer to
# an install booted, a child deployed from the runtime package, its
# validation tests run in it, and the teardown, in a temporary folder,
# removed after. It leaves nothing running. (test/run.sh: the whole, for
# after the migration.)
#   sh test/core.sh [--keep]
#     --keep    the temporary folder and its runtimes left as they are, to
#               inspect (its path printed)
#   SOURCES     the sources folder it links: the packages' bundles (the
#               app's among them) and Bare's tarball; else ../../../sources
#               from here; without one: skipped
# One line a check (ok, not ok), the count last; exit 0 passed, 1 failed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
pkg=$(cd "$here/.." && pwd)
keep=no
[ "${1:-}" = --keep ] && keep=yes
HAICC_HOME=$pkg . "$pkg/bin/haicc-lib.sh"   # the pins, this machine's Bare chosen
SOURCES=${SOURCES:-$pkg/../../sources}
for f in "$HAICC_ORG/$APP_PACKAGE.bundle" "$HAICC_ORG/base-component-boot.bundle" "$HAICC_ORG/base-package-runtime.bundle" "$HAICC_ORG/manifest.json" "$BARE_FILE"; do
  [ -f "$SOURCES/$f" ] || { echo "skipped: no $f in $SOURCES (SOURCES: a sources folder)"; exit 0; }
done
SOURCES=$(cd "$SOURCES" && pwd)

n=0; failed=0
ok () { n=$((n + 1)); echo "ok $n - $1"; }
no () { n=$((n + 1)); failed=$((failed + 1)); echo "not ok $n - $1"; [ -z "${2:-}" ] || echo "  # $2"; }
is () { if [ "$1" = "$2" ]; then ok "$3"; else no "$3" "got: $1; expected: $2"; fi; }
has () { case "$1" in *"$2"*) ok "$3" ;; *) no "$3" "got: $1; expected in it: $2" ;; esac; }

T=$(mktemp -d "${TMPDIR:-/tmp}/haicc-test.XXXXXX")
running () { pgrep -f -- "[/]bin/bare $T/" 2>/dev/null; }
cleanup () {
  if [ "$keep" = yes ]; then echo "kept: $T"; return; fi
  for pid in $(running); do kill "$pid" 2>/dev/null; done
  i=0; while [ -n "$(running)" ] && [ "$i" -lt 100 ]; do sleep 0.1 2>/dev/null || sleep 1; i=$((i + 1)); done
  for pid in $(running); do kill -9 "$pid" 2>/dev/null; done
  case "$T" in */haicc-test.*) rm -rf "$T" ;; esac
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# 1. installed; the sources linked; Bare put in place
out=$(sh "$pkg/haicc-install.sh" --home="$T/home" --bin="$T/bin" 2>&1)
is $? 0 "installed: sh haicc-install.sh --home --bin"
PATH=$T/bin:$PATH; export PATH
unset HAICC_HOME HAICC_WORK HAICC_REQUEST HAICC_RAW 2>/dev/null
HAICC_TIMEOUT=180; export HAICC_TIMEOUT
haicc sources link "$SOURCES" >/dev/null; is $? 0 "haicc sources link <folder>"
out=$(haicc prereq); is $? 0 "haicc prereq: all there"
W=$T/home/work

# 2. before the boot: an mrepo command says what is missing
out=$(haicc . haicc/mrepos 2>&1); is $? 3 "an mrepo command before the boot: exit 3"
has "$out" "no boot mrepo" "said: no boot mrepo (haicc boot/deploy)"

# 3. the boot: a program, a line a step, its outcome last
out=$(haicc boot/deploy 2>&1); is $? 0 "haicc boot/deploy"
has "$out" "Built local/boot at $W/mrepos/boot, from $HAICC_ORG/base-component-boot:" "a line a step: the boot mrepo built, where, from what"
has "$out" "  $HAICC_ORG/base-package-warm-boot" "its packages placed, each named: the warm boot among them"
is "$(printf '%s\n' "$out" | tail -n 1 | sed 's/pid [0-9]*/pid N/')" "Booted: local/boot is running, pid N, at $W." "its outcome, the last line"

# 4. a command for the mrepos: what it says printed. The first one waits
# behind the boot hook (the schema registry deployed, the activations): nothing is taken in before it is done
out=$(haicc . haicc/mrepos); is $? 0 "haicc . haicc/mrepos"
is "$out" "2 mrepos in the install's registry.
local/avro-registry at avro-registry, from $HAICC_ORG/base-component-avro-registry, running.
local/boot at ., from $HAICC_ORG/base-component-boot, running." "the install's registry: the boot mrepo and the schema registry, the fixture its boot hook deployed"
is "$(running | wc -l | tr -d ' ')" 2 "two runtimes running: the boot mrepo's, the schema registry's"
[ -d "$W/mrepos/local/avro-registry/.git" ] && [ ! -e "$W/mrepos/local/avro-registry/avro" ] && ok "the schema registry deployed at its fixed position: its repository, no folder of types beside it" || no "the schema registry deployed at its fixed position"
out=$(haicc . warm-boot/mrepos); has "$out" "local/avro-registry, in local/avro-registry." "the install's mrepos by their folders (the warm boot): the registry among them"
out=$(haicc avro-registry avro-registry/types); is $? 0 "haicc avro-registry avro-registry/types"
has "$out" "$HAICC_ORG/base-package-runtime/request" "the registry's types, by URI"
out=$(haicc avro-registry avro-registry/get "$HAICC_ORG/base-package-runtime/request"); has "$out" "Its fingerprint: " "one type: its fingerprint"
has "$out" "Attached: $HAICC_ORG/base-package-runtime/request (avro/string)" "its schema attached, a text"
has "$out" '"name": "haiccing.basePackageRuntime.request"' "shown as it is stored, from the attachment"
out=$(haicc avro-registry avro-registry/load); has "$out" "In its main: 0 added, 0 written again" "loaded again: every type a contract, nothing to write (its commission loaded it into its main)"
out=$(haicc avro-registry runtime/run . "packages/$HAICC_ORG/base-component-avro-registry/test/validate-in-situ" 2>&1); is $? 0 "the registry's validation tests, run in it"
has "$out" "Passed: /test/validate-in-situ" "passed"
out=$(haicc . runtime/run . "packages/$HAICC_ORG/base-package-warm-boot/test/validate-in-situ" 2>&1); is $? 0 "the warm boot's validation tests, run in the boot mrepo"
has "$out" "Passed: /test/validate-in-situ" "passed"
out=$(haicc . crud/read . 2>&1); is $? 1 "a protocol not brought to the request yet: failed, exit 1"
has "$out" "haicc: Refused, nothing run." "said on stderr: refused"
has "$out" "no protocol: crud (" "and why"
out=$(haicc . boot/deploy 2>&1); is $? 1 "what an action needs and is not given: exit 1"
has "$out" "missing argument: target" "said: missing argument: target"
out=$(haicc . haicc/mrepos --flags nope 2>&1); is $? 1 "a flag there is none of: exit 1"
has "$out" "Not run: its flags." "said: not run"

# 5. a child deployed from the runtime package, on its own
out=$(haicc . boot/deploy rt "$HAICC_ORG/base-package-runtime" 2>&1); is $? 0 "haicc . boot/deploy rt $HAICC_ORG/base-package-runtime"
has "$out" "Deployed rt as local/rt, from $HAICC_ORG/base-package-runtime." "what it says: deployed, its position, its unique URI, its package"
has "$out" "Its commission is done." "its commission waited for"
has "$out" "Its service is started." "its service as its commission left it"
[ -d "$W/mrepos/local/rt/.git" ] && ok "placed by its unique URI: mrepos/local/rt" || no "placed by its unique URI"
is "$(running | wc -l | tr -d ' ')" 3 "three runtimes running"
out=$(haicc . haicc/mrepos local/rt); has "$out" "local/rt at rt, from $HAICC_ORG/base-package-runtime, running." "in the install's registry, running"
out=$(haicc . boot/deploy rt "$HAICC_ORG/base-package-runtime"); is $? 0 "deployed again: a repeat, exit 0"
has "$out" "rt is deployed already, as local/rt" "said: deployed already, nothing done"

# 6. commands at its position: sent on, answered there
out=$(haicc rt runtime/run . "packages/$HAICC_ORG/base-package-runtime/test/validate-in-situ" 2>&1); is $? 0 "haicc rt runtime/run . .../test/validate-in-situ"
has "$out" "Passed: /test/validate-in-situ of $HAICC_ORG/base-package-runtime, 3 units." "its validation tests, run in it: passed"
has "$out" "/test/types: passed" "its types among them"
out=$(haicc rt info/get); is $? 0 "haicc rt info/get"
has "$out" ".: The mrepo runtime: the engine every mrepo runs on." "its info: what the page asked for is, said"
has "$out" "Attached: base-package-runtime (avro/string)" "its page attached, a text, shown below its line"
out=$(haicc rt service/start); has "$out" "The service was started already: nothing moved." "haicc rt service/start: a repeat, said"
out=$(haicc --request rt service/stop); is $? 0 "haicc --request: the whole request"
has "$out" '"status": "done"' "returned done"
has "$out" '"mrepo":"local/rt"' "sent on: the request it became linked, its mrepo"
out=$(haicc rt nope/x 2>&1); is $? 1 "refused there: exit 1 here"
has "$out" "no protocol: nope (" "said, as the child said it"
out=$(haicc rt service/start); has "$out" "The service is started: its state is started." "started again"
out=$(haicc --raw . haicc/mrepos | wc -l | tr -d ' '); is "$out" 1 "haicc --raw: the record as stored, one line"

# 7. torn down: the child, then the machine level
out=$(haicc . boot/teardown rt); is $? 0 "haicc . boot/teardown rt"
has "$out" "Torn down rt (local/rt): its runtime stopped" "said: its runtime stopped, its folder removed"
[ ! -e "$W/mrepos/local/rt" ] && ok "its folder gone" || no "its folder gone"
out=$(haicc boot/deploy 2>&1); is $? 0 "the boot again"
has "$out" "local/boot is built already" "there already: kept"
out=$(haicc boot/teardown 2>&1); is $? 0 "haicc boot/teardown"
has "$out" "Torn down the install at $W: 2 runtimes stopped, 0 containers removed" "said: the install torn down, its runtimes stopped (the boot mrepo's, the schema registry's)"
is "$(running | wc -l | tr -d ' ')" 0 "no process of the install left"
[ ! -e "$W/mrepos" ] && [ ! -e "$W/packages" ] && ok "the mrepos and the package store removed" || no "the mrepos and the package store removed"
out=$(haicc boot/teardown 2>/dev/null); is $? 0 "torn down twice: a repeat, exit 0"
has "$out" "Nothing to tear down at $W" "said: nothing there"

if [ "$keep" != yes ]; then
  cleanup; trap - EXIT
  [ -z "$(running)" ] && ok "nothing left running" || no "nothing left running"
  [ ! -e "$T" ] && ok "its folder removed" || no "its folder removed"
fi
echo "# checks = $((n - failed))/$n pass"
if [ "$failed" -eq 0 ]; then echo "# ok"; exit 0; else echo "# not ok"; exit 1; fi
