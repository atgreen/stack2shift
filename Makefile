stack2shift: *.asd *.lisp *.clt Makefile
	buildapp --output stack2shift \
		--asdf-path `pwd`/.. \
		--asdf-tree ~/quicklisp/dists/quicklisp/software \
		--load-system stack2shift \
		--compress-core \
		--entry "stack2shift:main"

clean:
	-rm -f stack2shift
	-rm -f *~
