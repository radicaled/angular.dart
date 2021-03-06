#!/bin/bash

set -e
. ./scripts/env.sh

echo '==========='
echo '== BUILD =='
echo '==========='

SIZE_TOO_BIG_COUNT=0

function checkSize() {
  file=$1
  if [[ ! -e $file ]]; then
    echo Could not find file: $file
    SIZE_TOO_BIG_COUNT=$((SIZE_TOO_BIG_COUNT + 1));
  else
    expected=$2
    actual=`cat $file | gzip | wc -c`
    if (( 100 * $actual >= 105 * $expected )); then
      echo ${file} is too large expecting ${expected} was ${actual}.
      SIZE_TOO_BIG_COUNT=$((SIZE_TOO_BIG_COUNT + 1));
    fi
  fi
}

# skip auxiliary tests if we are only running dart2js
if [[ $TESTS == "dart2js" ]]; then
  echo '------------------------'
  echo '-- BUILDING: examples --'
  echo '------------------------'

  if [[ $CHANNEL == "DEV" ]]; then
    dart "bin/pub_build.dart" -p example -e "example/expected_warnings.json"
  else
    ( cd example; pub build )
  fi

  (
    echo '-----------------------------------'
    echo '-- BUILDING: verify dart2js size --'
    echo '-----------------------------------'
    cd example
    checkSize build/web/animation.dart.js 208021
    checkSize build/web/bouncing_balls.dart.js 202325
    checkSize build/web/hello_world.dart.js 199919
    checkSize build/web/todo.dart.js 203121
    if ((SIZE_TOO_BIG_COUNT > 0)); then
      exit 1
    else
      echo Generated JavaScript file size check OK.
    fi
  )
else
  echo '--------------'
  echo '-- TEST: io --'
  echo '--------------'
  dart --checked test/io/all.dart

  echo '----------------------------'
  echo '-- TEST: symbol extractor --'
  echo '----------------------------'
  dart --checked test/tools/symbol_inspector/symbol_inspector_spec.dart

  ./scripts/generate-expressions.sh
  ./scripts/analyze.sh

  echo '-----------------------'
  echo '-- TEST: transformer --'
  echo '-----------------------'
  dart --checked test/tools/transformer/all.dart


  echo '---------------------'
  echo '-- TEST: changelog --'
  echo '---------------------'
  ./node_modules/jasmine-node/bin/jasmine-node ./scripts/changelog/;

  (
    echo '----------------'
    echo '-- TEST: perf --'
    echo '----------------'
    cd perf
    pub install
    for file in *_perf.dart; do
      echo ======= $file ========
      $DART $file
    done
  )
fi

BROWSERS=Dartium,ChromeNoSandbox,FireFox
if [[ $TESTS == "dart2js" ]]; then
  BROWSERS=ChromeNoSandbox,Firefox;
elif [[ $TESTS == "vm" ]]; then
  BROWSERS=Dartium;
fi

echo '-----------------------'
echo '-- TEST: AngularDart --'
echo '-----------------------'
echo BROWSER=$BROWSERS
./node_modules/jasmine-node/bin/jasmine-node playback_middleware/spec/ &&
  node "node_modules/karma/bin/karma" start karma.conf \
    --reporters=junit,dots --port=8765 --runner-port=8766 \
    --browsers=$BROWSERS --single-run --no-colors

if [[ $TESTS != "dart2js" ]]; then
  ./scripts/generate-documentation.sh;
fi
