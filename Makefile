.POSIX:
.SUFFIXES: .lisp .py .go .hs .rs

OBJDIR = build

.lisp:
	sbcl --load $< \
		 --eval "(sb-ext:save-lisp-and-die #p\"$@\" :toplevel #'main :executable t)"

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
	rm -rf ${OBJDIR} `find . -name solution`
	rm -rf ${OBJDIR} `find . -name '*input*'`
	rm -rf ${OBJDIR} `find . -name ex`
