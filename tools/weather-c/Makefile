# The C baseline of apps/Weather (weather.c, docs/apps.md): make, then ./weather
weather: weather.c
	$(CC) -O2 -Wall -o $@ $< $$(pkg-config --cflags --libs sdl3 freetype2 libcurl) -lm
