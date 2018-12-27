# usage: Make solution_YYYY-DD

OBJDIR = build

2017/%: 2017/%.hs
	ghc -outputdir $(OBJDIR) -o $@ $<

2018/%: 2018/%.go
	go build -o $@ $<

clean:
	rm -rf $(OBJDIR)
