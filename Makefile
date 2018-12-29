# usage: Make solution_YYYY-DD

OBJDIR = build

.SILENT:

2016/%: 2016/%.py
	echo "#!/bin/env python" > $@
	cat $< >> $@
	chmod +x $@

2017/%: 2017/%.hs
	ghc -O -outputdir $(OBJDIR) -o $@ $<

2018/%: 2018/%.go
	go build -o $@ $<

clean:
	rm -rf $(OBJDIR)
