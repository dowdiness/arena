#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern void* moonbit_make_external_object(void (*)(void*), int);

typedef struct {
  int32_t* data;
  int32_t  length;
} GenArray;

static void gen_finalize(void* self) {
  GenArray* g = (GenArray*)self;
  if (g->data) {
    free(g->data);
    g->data = NULL;
  }
}

GenArray* gen_create(int32_t length) {
  GenArray* g = (GenArray*)moonbit_make_external_object(gen_finalize, sizeof(GenArray));
  if (length > 0) {
    g->data = (int32_t*)calloc((size_t)length, sizeof(int32_t));
    if (!g->data) { abort(); }
  } else {
    g->data = NULL;
  }
  g->length = length;
  return g;
}

void gen_destroy(GenArray* g) {
  if (g->data) {
    free(g->data);
    g->data = NULL;
  }
}

int32_t gen_get(GenArray* g, int32_t index) {
  return g->data[index];
}

void gen_set(GenArray* g, int32_t index, int32_t val) {
  g->data[index] = val;
}

int32_t gen_length(GenArray* g) {
  return g->length;
}
