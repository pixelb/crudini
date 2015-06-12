name = crudini
version = 0.6

all:
	help2man -n "manipulate ini files" -o crudini.1 -N ./crudini-help
	./crudini-help --help > README

dist: all
	mkdir ${name}-${version}
	{ git ls-files; echo crudini.1; } | xargs cp -a --parents --target=${name}-${version}
	tar -czf ${name}-${version}.tar.gz ${name}-${version}
	rm -Rf ${name}-${version}
