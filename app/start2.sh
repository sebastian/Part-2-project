#!/bin/sh
cd `dirname $0`
exec erl -chord_port 3002 -pa $PWD/ebin $PWD/deps/*/ebin -boot start_sasl -s reloader -s fs 
