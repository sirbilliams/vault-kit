#!/bin/bash
# golden.sh capture <f1|f2> <out-dir>      run the existing autotest for both themes into <out-dir>/<theme>/
# golden.sh compare [--fuzz N%] [--max-px N] <golden-dir> <new-dir>
#                                           compare every PNG pair (ImageMagick `compare -metric AE`),
#                                           diff images go to <new-dir>/_diff/, exit 1 on any difference.
# Builds nothing: build the ports first. Game art stays OUTSIDE this repo (goldens contain it).
#
# DETERMINISM (measured 2026-10-29, same binary, two identical runs, fuzz 0):
#  f1 (2026-10-30, after the port's fixed autotest clock): two identical runs are bit-identical, fuzz 0 and
#      max-px 0 (29 files per theme, ~6 s per theme). Strict compare is the default; goldens recaptured then.
#  f2: STRICT compare works (no --fuzz/--max-px): since the port change, --dev-autotest uses a fixed
#      16 ms-per-frame UI clock (uiTicks) and a fixed random seed; two identical runs give 0 differing
#      files of 112. Goldens must be recaptured after any intended visual change.
set -u

# ---- configuration (edit paths here) ---------------------------------------
CAPTURE_TIMEOUT=300                                   # seconds per game run
F2_BIN=${F2_BIN:-$HOME/Projects/Fallout2Ce-Dualscreen-Android/build-desktop/fallout2-ce}
F2_RUN=${F2_RUN:-$HOME/Projects/f2ds-run}             # Steam data linked, save copied, fallout2.cfg
F2_SCENARIOS=${F2_SCENARIOS:-"dualscreen dualpipboy"}
F2_THEMES="pipboy=2 classic=0"                        # name=[touch] bottom_theme value
F1_BIN=${F1_BIN:-$HOME/Projects/Fallout1Ce-Dualscreen-Android/build-desktop/fallout-ce}
F1_RUN=${F1_RUN:-$HOME/Projects/f1-run}               # scratch data + fallout.cfg
F1_THEMES="pipboy=2 classic=0"                        # name=FALLOUT_AUTOTEST_THEME value
FUZZ=0%                                               # default per-pixel colour fuzz
MAX_DIFF_PIXELS=0                                     # a file passes if differing pixels <= this
# -----------------------------------------------------------------------------

die() { echo "golden.sh: $*" >&2; exit 2; }

capture_f2() {
  local out=$1 pair name val scen work
  for pair in $F2_THEMES; do
    name=${pair%%=*}; val=${pair##*=}
    mkdir -p "$out/$name"
    # Work dir of symlinks + a COPY of the cfg with the theme set; the rig's cfg is never touched.
    work=$(mktemp -d)
    local e
    for e in "$F2_RUN"/*; do
      case $(basename "$e") in fallout2.cfg|shots|debug.log) ;; *) ln -s "$e" "$work/" ;; esac
    done
    cp "$F2_RUN/fallout2.cfg" "$work/fallout2.cfg"
    if grep -q '^bottom_theme=' "$work/fallout2.cfg"; then
      sed -i "s/^bottom_theme=.*/bottom_theme=$val/" "$work/fallout2.cfg"
    else
      sed -i "s/^\[touch\]\$/[touch]\nbottom_theme=$val/" "$work/fallout2.cfg"
    fi
    for scen in $F2_SCENARIOS; do
      rm -rf "$work/shots-$scen"
      ( cd "$work" && SDL_AUDIODRIVER=dummy SDL_VIDEODRIVER=offscreen timeout -k 5 $CAPTURE_TIMEOUT \
          "$F2_BIN" --dev-autotest="$work/shots-$scen" --dev-load-game=1 --dev-autotest-scenario="$scen" \
          </dev/null >"$work/$scen.log" 2>&1 )
      echo "f2 $name $scen rc=$?"
      local f
      for f in "$work/shots-$scen"/*.png; do
        [ -e "$f" ] && cp "$f" "$out/$name/${scen}__$(basename "$f")"
      done
    done
    rm -rf "$work"
  done
}

capture_f1() {
  local out=$1 pair name val
  for pair in $F1_THEMES; do
    name=${pair%%=*}; val=${pair##*=}
    mkdir -p "$out/$name"
    local tmp; tmp=$(mktemp -d)
    ( cd "$F1_RUN" && timeout -k 5 $CAPTURE_TIMEOUT env SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy \
        FALLOUT_AUTOTEST_DIR="$tmp" FALLOUT_AUTOTEST_THEME=$val "$F1_BIN" --dev-autotest \
        </dev/null >"$tmp.log" 2>&1 )
    echo "f1 $name rc=$?"
    local f
    for f in "$tmp"/*.bmp; do   # BMP -> PNG (lossless) so compare/storage match F2
      [ -e "$f" ] && magick "$f" "$out/$name/$(basename "${f%.bmp}").png"
    done
    rm -rf "$tmp" "$tmp.log"
  done
}

compare_dirs() {
  local fuzz=$FUZZ
  while :; do
    case ${1:-} in
      --fuzz) fuzz=$2; shift 2 ;;
      --max-px) MAX_DIFF_PIXELS=$2; shift 2 ;;
      *) break ;;
    esac
  done
  local gold=${1:-} new=${2:-}
  [ -d "$gold" ] && [ -d "$new" ] || die "usage: compare [--fuzz N%] <golden-dir> <new-dir>"
  rm -rf "$new/_diff"
  local bad=0 total=0 rel n
  while IFS= read -r rel; do
    total=$((total+1))
    if [ ! -f "$new/$rel" ]; then echo "MISSING  $rel"; bad=$((bad+1)); continue; fi
    n=$(compare -metric AE -fuzz "$fuzz" "$gold/$rel" "$new/$rel" "$new/_diff.tmp.png" 2>&1 >/dev/null)
    n=${n%% *}   # IM7 prints "N (fraction)"; N may be fractional
    if ! [[ $n =~ ^[0-9.e+-]+$ ]]; then echo "ERROR    $rel ($n)"; bad=$((bad+1)); rm -f "$new/_diff.tmp.png"; continue; fi
    if awk -v n="$n" -v m="$MAX_DIFF_PIXELS" 'BEGIN{exit !(n+0 > m+0)}'; then
      mkdir -p "$new/_diff/$(dirname "$rel")"; mv "$new/_diff.tmp.png" "$new/_diff/$rel" 2>/dev/null || magick "$gold/$rel" "$new/$rel" -alpha off -compose difference -composite "$new/_diff/$rel"
      echo "DIFF     $rel  $n px"; bad=$((bad+1))
    else
      rm -f "$new/_diff.tmp.png"; echo "ok       $rel  $n px"
    fi
  done < <(cd "$gold" && find . -name '*.png' -not -path './_diff/*' | sed 's|^\./||' | sort)
  while IFS= read -r rel; do
    [ -f "$gold/$rel" ] || { echo "EXTRA    $rel"; bad=$((bad+1)); }
  done < <(cd "$new" && find . -name '*.png' -not -path './_diff/*' | sed 's|^\./||' | sort)
  echo "compared $total files, $bad problem(s), fuzz=$fuzz, max-diff-px=$MAX_DIFF_PIXELS"
  [ "$bad" -eq 0 ]
}

case ${1:-} in
  capture)
    [ $# -eq 3 ] || die "usage: capture <f1|f2> <out-dir>"
    case $2 in f1) capture_f1 "$3" ;; f2) capture_f2 "$3" ;; *) die "game must be f1 or f2" ;; esac ;;
  compare) shift; compare_dirs "$@" ;;
  *) die "usage: $0 capture <f1|f2> <out-dir> | compare [--fuzz N%] <golden-dir> <new-dir>" ;;
esac
