#!/bin/sh
cd `dirname $0`
exec erl -emu_args -chord_port 3002 -pa $PWD/ebin $PWD/deps/*/ebin -boot start_sasl -s reloader -s fs 
