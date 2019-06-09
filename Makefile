.POSIX:
.SUFFIXES: .lisp .py .go .hs

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

clean:
	rm -rf ${OBJDIR} `find . -name solution`
