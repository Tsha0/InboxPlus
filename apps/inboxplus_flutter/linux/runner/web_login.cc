#include "web_login.h"

#include <webkit2/webkit2.h>

#include <memory>
#include <string>

namespace {
struct LoginSession : std::enable_shared_from_this<LoginSession> {
  FlMethodCall* call;
  GtkWidget* window = nullptr;
  WebKitWebView* view = nullptr;
  WebKitWebContext* context;
  std::string platform;
  std::string domain;
  std::string url;
  bool finished = false;
  bool capturing = false;
  guint capture_timer = 0;

  LoginSession(FlMethodCall* method_call, const std::string& network)
      : call(FL_METHOD_CALL(g_object_ref(method_call))),
        context(webkit_web_context_new_ephemeral()), platform(network),
        domain(network == "instagram" ? "instagram.com" : "facebook.com"),
        url(network == "instagram" ? "https://www.instagram.com/accounts/login/"
                                     : "https://www.facebook.com/login/") {}

  ~LoginSession() {
    g_object_unref(call);
    g_object_unref(context);
  }

  bool owns_domain(const char* value) const {
    if (value == nullptr) return false;
    std::string host(value);
    while (!host.empty() && host.front() == '.') host.erase(0, 1);
    g_autofree gchar* lower = g_ascii_strdown(host.c_str(), -1);
    host = lower;
    return host == domain ||
        (host.size() > domain.size() &&
         host.compare(host.size() - domain.size() - 1, domain.size() + 1,
                      "." + domain) == 0);
  }

  bool allowed_uri(const char* uri) const {
    if (uri == nullptr) return false;
    g_autoptr(GUri) parsed = g_uri_parse(uri, G_URI_FLAGS_NONE, nullptr);
    return parsed != nullptr &&
        g_strcmp0(g_uri_get_scheme(parsed), "https") == 0 &&
        owns_domain(g_uri_get_host(parsed));
  }

  void finish(FlValue* credentials, const char* error) {
    if (finished) return;
    auto retained = shared_from_this();
    finished = true;
    if (capture_timer != 0) {
      g_source_remove(capture_timer);
      capture_timer = 0;
    }
    g_autoptr(FlMethodResponse) response = credentials != nullptr
        ? FL_METHOD_RESPONSE(fl_method_success_response_new(credentials))
        : FL_METHOD_RESPONSE(fl_method_error_response_new(error, nullptr, nullptr));
    fl_method_call_respond(retained->call, response, nullptr);
    GtkWidget* closing_window = window;
    window = nullptr;
    if (view != nullptr) webkit_web_view_stop_loading(view);
    view = nullptr;
    if (closing_window != nullptr) gtk_widget_destroy(closing_window);
  }

  void capture() {
    if (finished || capturing || view == nullptr ||
        !allowed_uri(webkit_web_view_get_uri(view))) return;
    capturing = true;
    auto* retained = new std::shared_ptr<LoginSession>(shared_from_this());
    webkit_cookie_manager_get_cookies(webkit_web_context_get_cookie_manager(context),
        url.c_str(), nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
          std::unique_ptr<std::shared_ptr<LoginSession>> retained_session(
              static_cast<std::shared_ptr<LoginSession>*>(data));
          auto session = *retained_session;
          session->capturing = false;
          g_autoptr(GError) error = nullptr;
          GList* cookies = webkit_cookie_manager_get_cookies_finish(
              WEBKIT_COOKIE_MANAGER(object), result, &error);
          g_autoptr(FlValue) values = fl_value_new_map();
          if (!session->finished && error == nullptr) {
            for (GList* item = cookies; item != nullptr; item = item->next) {
              auto* cookie = static_cast<SoupCookie*>(item->data);
              const char* name = soup_cookie_get_name(cookie);
              const char* value = soup_cookie_get_value(cookie);
              const bool declared = session->platform == "instagram"
                  ? g_strcmp0(name, "sessionid") == 0 ||
                    g_strcmp0(name, "csrftoken") == 0 ||
                    g_strcmp0(name, "ds_user_id") == 0
                  : g_strcmp0(name, "xs") == 0 ||
                    g_strcmp0(name, "c_user") == 0 ||
                    g_strcmp0(name, "datr") == 0;
              GDateTime* expires = soup_cookie_get_expires(cookie);
              g_autoptr(GDateTime) now = g_date_time_new_now_utc();
              if (declared && value != nullptr && *value != '\0' &&
                  soup_cookie_get_secure(cookie) &&
                  session->owns_domain(soup_cookie_get_domain(cookie)) &&
                  (expires == nullptr || g_date_time_compare(expires, now) > 0)) {
                fl_value_set_string_take(values, name, fl_value_new_string(value));
              }
            }
            const bool complete = session->platform == "instagram"
                ? fl_value_lookup_string(values, "sessionid") != nullptr &&
                  fl_value_lookup_string(values, "csrftoken") != nullptr &&
                  fl_value_lookup_string(values, "ds_user_id") != nullptr
                : fl_value_lookup_string(values, "xs") != nullptr &&
                  fl_value_lookup_string(values, "c_user") != nullptr &&
                  fl_value_lookup_string(values, "datr") != nullptr;
            if (complete) session->finish(values, nullptr);
          }
          g_list_free_full(cookies, [](gpointer cookie) {
            soup_cookie_free(static_cast<SoupCookie*>(cookie));
          });
        }, retained);
  }
};

std::weak_ptr<LoginSession> active_login;
}

void inboxplus_cancel_web_login() {
  if (auto session = active_login.lock()) session->finish(nullptr, "login_cancelled");
}

void inboxplus_web_login(GtkApplication* application, FlMethodCall* call) {
  FlValue* arguments = fl_method_call_get_args(call);
  FlValue* network = fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(arguments, "platform") : nullptr;
  const char* platform = network != nullptr && fl_value_get_type(network) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(network) : nullptr;
  auto previous = active_login.lock();
  if (platform == nullptr ||
      (g_strcmp0(platform, "instagram") != 0 && g_strcmp0(platform, "messenger") != 0) ||
      (previous != nullptr && !previous->finished)) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("web_login_unavailable", nullptr, nullptr));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  auto session = std::make_shared<LoginSession>(call, platform);
  active_login = session;
  GtkWindow* parent = gtk_application_get_active_window(application);
  session->window = gtk_application_window_new(application);
  gtk_window_set_title(GTK_WINDOW(session->window),
      session->platform == "instagram" ? "Sign in to Instagram" : "Sign in to Messenger");
  gtk_window_set_default_size(GTK_WINDOW(session->window), 520, 720);
  if (parent != nullptr) gtk_window_set_transient_for(GTK_WINDOW(session->window), parent);
  gtk_window_set_destroy_with_parent(GTK_WINDOW(session->window), TRUE);
  session->view = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(session->context));
  gtk_container_add(GTK_CONTAINER(session->window), GTK_WIDGET(session->view));
  g_signal_connect(session->context, "download-started", G_CALLBACK(+[](
      WebKitWebContext*, WebKitDownload* download, gpointer) {
    webkit_download_cancel(download);
  }), nullptr);
  g_signal_connect(session->view, "permission-request", G_CALLBACK(+[](
      WebKitWebView*, WebKitPermissionRequest* request, gpointer) -> gboolean {
    webkit_permission_request_deny(request);
    return TRUE;
  }), nullptr);
  g_object_set_data_full(G_OBJECT(session->window), "inboxplus-login",
      new std::shared_ptr<LoginSession>(session), [](gpointer data) {
        delete static_cast<std::shared_ptr<LoginSession>*>(data);
      });
  g_signal_connect(session->window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    static_cast<LoginSession*>(data)->finish(nullptr, "login_cancelled");
  }), session.get());
  g_signal_connect(session->view, "decide-policy", G_CALLBACK(+[](
      WebKitWebView*, WebKitPolicyDecision* decision,
      WebKitPolicyDecisionType type, gpointer data) -> gboolean {
    auto* login = static_cast<LoginSession*>(data);
    if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
      webkit_policy_decision_ignore(decision);
      return TRUE;
    }
    if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
      auto* navigation = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
      WebKitNavigationAction* action = webkit_navigation_policy_decision_get_navigation_action(navigation);
      const char* uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
      if (!login->allowed_uri(uri)) {
        webkit_policy_decision_ignore(decision);
        return TRUE;
      }
    }
    return FALSE;
  }), session.get());
  g_signal_connect(session->view, "web-process-terminated", G_CALLBACK(+[](
      WebKitWebView*, WebKitWebProcessTerminationReason, gpointer data) {
    static_cast<LoginSession*>(data)->finish(nullptr, "login_failed");
  }), session.get());
  session->capture_timer = g_timeout_add_full(G_PRIORITY_DEFAULT, 500,
      [](gpointer data) -> gboolean {
        auto login = *static_cast<std::shared_ptr<LoginSession>*>(data);
        login->capture();
        return login->finished ? G_SOURCE_REMOVE : G_SOURCE_CONTINUE;
      }, new std::shared_ptr<LoginSession>(session), [](gpointer data) {
        delete static_cast<std::shared_ptr<LoginSession>*>(data);
      });
  gtk_widget_show_all(session->window);
  webkit_web_view_load_uri(session->view, session->url.c_str());
}
