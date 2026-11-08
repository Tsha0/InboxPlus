#ifndef INBOXPLUS_CONNECTORS_H
#define INBOXPLUS_CONNECTORS_H

#ifdef __cplusplus
extern "C" {
#endif

char *inboxplus_request(char *json);
char *inboxplus_poll_event(void);
void inboxplus_free(void *pointer);

#ifdef __cplusplus
}
#endif

#endif
