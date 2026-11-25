# CatSynth 64: build with 64tass (https://sourceforge.net/projects/tass64/)
#   make            build/catsynth.prg (run it: RUN, or SYS 2061)
#   make packed     build/catsynth64.prg, packed with Exomizer 3 (as released)
#   make web        build/catsynth-web.prg: the web edition (docs/play), the
#                   ten techno songs (gen/techno.inc) in its song slots

all: build/catsynth.prg

build/catsynth.prg: $(wildcard src/*.asm) $(wildcard gen/*)
	mkdir -p build
	64tass -C -a src/catsynth.asm -o $@ -l build/catsynth.lbl -L build/catsynth.lst

web: build/catsynth-web.prg

build/catsynth-web.prg: $(wildcard src/*.asm) $(wildcard gen/*)
	mkdir -p build
	64tass -C -a -D WEB=1 src/catsynth.asm -o $@

packed: build/catsynth.prg
	exomizer sfx sys -x1 -q -o build/catsynth64.prg build/catsynth.prg

# the release disk's boot: CATSYNTH64 (build/autoboot.prg: LOAD"*",8,1
# starts it) loads CATBOOT (build/catboot.prg, the 1541 fast loader: set
# CB_SYS to the packed program's SYS), which loads CATSYNTH64 MAIN (the
# packed program) and starts it
catboot: build/catboot.prg build/autoboot.prg
build/catboot.prg: src/catboot.asm
	mkdir -p build
	64tass -C -a src/catboot.asm -o $@
build/autoboot.prg: src/autoboot.asm
	mkdir -p build
	64tass -C -a src/autoboot.asm -o $@

clean:
	rm -f build/catsynth.prg build/catsynth64.prg build/catsynth.lbl build/catsynth.lst build/catboot.prg build/autoboot.prg

.PHONY: all web packed catboot clean
