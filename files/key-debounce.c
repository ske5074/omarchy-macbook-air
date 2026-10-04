// interception-tools filter: drops key chatter from worn butterfly switches.
//
// A chattering key sends press, release, press within a few milliseconds of a
// single tap. This drops any press that arrives within the threshold of that
// key's last release, along with the release that follows it.
//
// Usage: intercept -g $DEVNODE | key-debounce [ms] | uinput -d $DEVNODE
// The threshold defaults to 30 ms.

#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>

static long long event_ms(const struct input_event *ev) {
  return (long long)ev->input_event_sec * 1000 + ev->input_event_usec / 1000;
}

int main(int argc, char **argv) {
  long long threshold = argc > 1 ? atoll(argv[1]) : 30;
  static long long last_release[KEY_CNT];
  static unsigned char dropping[KEY_CNT];
  struct input_event ev;

  setbuf(stdin, NULL);
  setbuf(stdout, NULL);

  while (fread(&ev, sizeof ev, 1, stdin) == 1) {
    if (ev.type == EV_KEY && ev.code < KEY_CNT) {
      if (ev.value == 1 && last_release[ev.code] &&
          event_ms(&ev) - last_release[ev.code] < threshold) {
        dropping[ev.code] = 1;
        continue;
      }
      if (dropping[ev.code]) {
        // Swallow the dropped press's repeats and release.
        if (ev.value == 0) dropping[ev.code] = 0;
        continue;
      }
      if (ev.value == 0) last_release[ev.code] = event_ms(&ev);
    }
    if (fwrite(&ev, sizeof ev, 1, stdout) != 1) return 1;
  }
  return 0;
}
