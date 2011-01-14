#!/bin/sh
cd `dirname $0`
exec erl -emu_args -fs_web_port 3000 -pastry_port 4001 -pa $PWD/ebin $PWD/deps/*/ebin -boot start_sasl -s reloader -s fs 
