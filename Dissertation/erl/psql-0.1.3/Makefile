## Makefile for building the skel application
## Author: Martin Carlson <martin@erlang-consulting.com>
## Usage: make Will build the source code
##        make docs Will build the docs
##        make app Will build the application resource file

include vsn.mk

APPLICATION=psql

ifndef ($(ERL_TOP))
ERL=erl $(ERL_ARGS)
else
ERL=$(ERL_TOP)/bin/erl $(ERL_ARGS)
endif

all: app
	@(cd src && $(ERL) -make)
test:
	@(cd tests && $(ERL) -DTEST -make)
docs:
	$(ERL) -noshell -pa `pwd`/ebin -run edoc_run application \
		"'$(APPLICATION)'" '"."' '[]' -s erlang halt

app: src/$(APPLICATION).app.src
	@(cd src && sed "s|%MODULES%|`ls -x -m *.erl | sed 's|.erl||g' | tr \\\n ' '`|g" `basename $<` | sed "s|%VSN%|$(VSN)|g" | sed "s|%NAME%|$(APPLICATION)|g" > ../ebin/`basename $< .src`)

clean:
	rm -fv ebin/*.beam
	rm -fv ebin/*.app
	rm -fv doc/*.html
	rm -fv doc/edoc-info
	rm -fv doc/*.css

cleanapp:
	rm -fv ebin/*.app
