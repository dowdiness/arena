#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern void* moonbit_make_external_object(void (*)(void*), int);

typedef struct {
  char*    base;
  int32_t  offset;
  int32_t  capacity;
} BumpArena;

static void bump_finalize(void* self) {
  BumpArena* a = (BumpArena*)self;
  if (a->base) {
    free(a->base);
    a->base = NULL;
  }
}

BumpArena* bump_create(int32_t capacity) {
  BumpArena* a = (BumpArena*)moonbit_make_external_object(bump_finalize, sizeof(BumpArena));
  if (capacity > 0) {
    a->base = (char*)calloc(1, (size_t)capacity);
    if (!a->base) { abort(); }
  } else {
    a->base = NULL;
  }
  a->offset = 0;
  a->capacity = capacity;
  return a;
}

void bump_destroy(BumpArena* a) {
  if (a->base) {
    free(a->base);
    a->base = NULL;
  }
}

/* Returns byte offset on success, -1 on failure */
int32_t bump_alloc(BumpArena* a, int32_t size, int32_t align) {
  if (size <= 0 || align <= 0) return -1;
  int32_t remainder = a->offset % align;
  int32_t padding = (remainder == 0) ? 0 : align - remainder;
  if (padding > a->capacity - a->offset) return -1;
  int32_t aligned = a->offset + padding;
  if (size > a->capacity - aligned) return -1;
  a->offset = aligned + size;
  return aligned;
}

void bump_reset(BumpArena* a) {
  a->offset = 0;
}

int32_t bump_capacity(BumpArena* a) {
  return a->capacity;
}

int32_t bump_used(BumpArena* a) {
  return a->offset;
}

void bump_write_i32(BumpArena* a, int32_t offset, int32_t val) {
  memcpy(a->base + offset, &val, 4);
}

int32_t bump_read_i32(BumpArena* a, int32_t offset) {
  int32_t val;
  memcpy(&val, a->base + offset, 4);
  return val;
}

void bump_write_f64(BumpArena* a, int32_t offset, double val) {
  memcpy(a->base + offset, &val, 8);
}

double bump_read_f64(BumpArena* a, int32_t offset) {
  double val;
  memcpy(&val, a->base + offset, 8);
  return val;
}

void bump_write_byte(BumpArena* a, int32_t offset, int32_t val) {
  a->base[offset] = (char)(unsigned char)val;
}

int32_t bump_read_byte(BumpArena* a, int32_t offset) {
  return (int32_t)(unsigned char)a->base[offset];
}
