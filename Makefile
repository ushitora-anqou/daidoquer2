all: priv/check_sjis.so priv/volume_filter.so

priv/%.so: c_src/%.c
	cc -shared -fPIC -o $@ $<
