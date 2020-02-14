.POSIX:
.SUFFIXES: .lisp .py .go .hs .rs .awk

OBJDIR = build
CFLAGS += -g -Wall -Wextra

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

.hs:
	ghc -O -outputdir ${OBJDIR} -o $@ $<

.go:
	go build -o $@ $<

.rs:
	rustc --edition 2018 -o $@ $<

clean:
	rm -rf ${OBJDIR}
	rm -f `find . -name solution`
	rm -f `find . -type f -a -name 'input'`
	rm -f `find . -type f -name 'ex*'`

distclean: clean
	rm -f cookies.jar
	rm -rf puzzles
