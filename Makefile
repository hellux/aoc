.POSIX:
.SUFFIXES: .lisp .py .go .hs .rs .awk .jq .nim

OBJDIR = build
CFLAGS += -g -Wall -Wextra -Wconversion

.lisp:
	sbcl --load $< \
		 --eval "(sb-ext:save-lisp-and-die #p\"$@\" :toplevel #'main :executable t)"

.awk:
	echo "#!/usr/bin/env -S awk -f" > $@
	cat $< >> $@
	chmod a+x $@

.py:
	echo "#!/bin/env python" > $@
	cat $< >> $@
	chmod a+x $@

.jq:
	echo "#!/bin/env -S jq -f" > $@
	cat $< >> $@
	chmod a+x $@

.hs:
	ghc -O -outputdir ${OBJDIR} -o $@ $<

.go:
	go build -o $@ $<

.rs:
	rustc -o $@ $<

.nim:
	nim compile $<

clean:
	rm -rf ${OBJDIR}
	find 20* -mindepth 2 -type f -name solution -print0 | xargs -0 rm
