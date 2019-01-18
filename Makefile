.POSIX:
.SILENT:
.SUFFIXES: .py .go .hs

OBJDIR = build

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
