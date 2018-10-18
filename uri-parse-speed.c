#include "uri_parser.h"
#include <stdio.h>
#include <string.h>

#define UNUSED(x) (void)(x)

int main(int argc, char **argv) {
  UNUSED(argc);
  UNUSED(argv);

  char buf[1024*16];
  char *l = NULL;
  const char *error_at = NULL;
  uri_t *u = uri_new();
  while ( (l = fgets(buf, sizeof(buf), stdin)) ) {
    int len = strlen(l);
    if (len > 0 && l[len-1] == '\n') { l[len-1] = 0; }
    if (uri_parse(u, buf, len-1, &error_at)) {
      uri_normalize(u);
    } else if (error_at) {
      fprintf(stderr, "error for %s at %s\n", buf, error_at);
    }
    uri_clear(u);
  }
  uri_free(u);
  return 0;
}
