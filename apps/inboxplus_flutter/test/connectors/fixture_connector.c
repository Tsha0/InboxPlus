#define _POSIX_C_SOURCE 200809L
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static atomic_int blocked;
static atomic_int cancelled;
static atomic_int emitted;
static atomic_int increments;

static void pause_millis(long value) {
  struct timespec delay = {.tv_sec = 0, .tv_nsec = value * 1000000};
  nanosleep(&delay, NULL);
}

#ifdef SLOW_START
__attribute__((constructor)) static void slow_start(void) {
  pause_millis(500);
}
#endif

char *inboxplus_request(char *json) {
  if (strstr(json, "\"op\":\"reset\"")) {
    atomic_store(&blocked, 0);
    atomic_store(&cancelled, 0);
    atomic_store(&emitted, 0);
    atomic_store(&increments, 0);
  } else if (strstr(json, "\"op\":\"block\"")) {
    atomic_store(&blocked, 1);
    for (int tick = 0; tick < 700 && !atomic_load(&cancelled); tick++) {
      pause_millis(1);
    }
    atomic_store(&blocked, 0);
    if (atomic_load(&cancelled)) {
      return strdup("{\"ok\":false,\"error\":{\"code\":\"operation_failed\"}}");
    }
  } else if (strstr(json, "\"op\":\"cancel\"") || strstr(json, "\"op\":\"shutdown\"")) {
    atomic_store(&cancelled, 1);
  } else if (strstr(json, "\"op\":\"increment\"")) {
    atomic_fetch_add(&increments, 1);
  } else if (strstr(json, "\"op\":\"state\"")) {
    return strdup(atomic_load(&increments) == 0
      ? "{\"ok\":true,\"data\":{\"increments\":0}}"
      : "{\"ok\":true,\"data\":{\"increments\":1}}");
  } else if (strstr(json, "\"op\":\"failure\"")) {
    return strdup("{\"ok\":false,\"error\":{\"code\":\"private-cookie-value\",\"message\":\"private-message-body\"}}");
  } else if (strstr(json, "\"op\":\"malformed\"")) {
    return strdup("invalid JSON containing private-message-body");
  }
  return strdup("{\"ok\":true,\"data\":{\"abi_version\":1}}");
}

char *inboxplus_poll_event(void) {
  if (atomic_load(&blocked) && !atomic_exchange(&emitted, 1)) {
    return strdup("{\"type\":\"qr\",\"account_id\":\"fixture\",\"code\":\"fixture-qr\"}");
  }
  return NULL;
}

void inboxplus_free(void *pointer) {
  free(pointer);
}
