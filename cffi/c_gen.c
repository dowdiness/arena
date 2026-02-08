#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef struct {
  int32_t* data;
  int32_t  length;
} GenArray;

GenArray* gen_create(int32_t length) {
  GenArray* g = (GenArray*)malloc(sizeof(GenArray));
  if (!g) return NULL;
  g->data = (int32_t*)calloc((size_t)length, sizeof(int32_t));
  if (!g->data && length > 0) { free(g); return NULL; }
  g->length = length;
  return g;
}

int32_t gen_is_null(GenArray* g) {
  return g == NULL ? 1 : 0;
}

void gen_destroy(GenArray* g) {
  if (g) {
    free(g->data);
    free(g);
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
