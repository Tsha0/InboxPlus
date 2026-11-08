#ifndef INBOXPLUS_WEB_LOGIN_H_
#define INBOXPLUS_WEB_LOGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void inboxplus_web_login(GtkApplication* application, FlMethodCall* call);
void inboxplus_cancel_web_login();

#endif
