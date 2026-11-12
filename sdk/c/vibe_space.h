#ifndef VIBE_SPACE_H
#define VIBE_SPACE_H
#include <stdint.h>
/* Host copies at most 1 MiB into guest-owned linear memory. No libc or WASI. */
#define VIBE_MAX_MESSAGE 1048576u
static unsigned char vibe_input[VIBE_MAX_MESSAGE];
__attribute__((export_name("vibe_alloc")))
uint32_t vibe_alloc(uint32_t length) {
  if (length > VIBE_MAX_MESSAGE) __builtin_trap();
  return (uint32_t)(uintptr_t)vibe_input;
}
__attribute__((export_name("omni_alloc")))
uint32_t omni_alloc(uint32_t length) {
  return vibe_alloc(length);
}
static uint64_t vibe_result(const char *json, uint32_t length) {
  if (length > VIBE_MAX_MESSAGE) __builtin_trap();
  return ((uint64_t)length << 32) | (uint32_t)(uintptr_t)json;
}
uint64_t omni_invoke(uint32_t pointer, uint32_t length);
__attribute__((export_name("vibe_invoke")))
uint64_t vibe_invoke(uint32_t pointer, uint32_t length) {
  return omni_invoke(pointer, length);
}
/* Implement this entrypoint and return vibe_result(valid_json, byte_length). */
#define VIBE_INVOKE __attribute__((export_name("omni_invoke"))) uint64_t omni_invoke(uint32_t pointer, uint32_t length)
#endif
