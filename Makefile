.POSIX:
.SUFFIXES: .lisp .py .go .hs .rs .awk .jq .nim .zig .ha .ml

OBJDIR = build
CFLAGS += -g -Wall -Wextra -Wconversion
ASFLAGS += -no-pie -znoexecstack

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
	rustc -C debug-assertions=y -O -o $@ $<

.nim:
	nim compile $<

.zig:
	zig build-exe $< && mv solution $@

.ha:
	hare build -o $@ $<

.ml:
	ocamlc -o $@ $<
	rm -f $@.cmi $@.cmo

clean:
	rm -rf ${OBJDIR}
	find 20* -maxdepth 2 -mindepth 2 -type f -name solution | xargs rm -f
