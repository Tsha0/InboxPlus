#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#include <libayatana-appindicator/app-indicator.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>

#include <cstdlib>
#include <string>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#ifdef INBOXPLUS_LINUX_WEB_LOGIN
#include "web_login.h"
#endif

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean has_unfinished_work;
  gboolean quit_requested;
  gboolean indicator_connected;
  AppIndicator* indicator;
  FlValue* pending_notification_route;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static GtkWindow* inbox_window(MyApplication* self) {
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(self));
  return windows == nullptr ? nullptr : GTK_WINDOW(windows->data);
}

static void request_quit(MyApplication* self) {
  self->quit_requested = TRUE;
  GtkWindow* window = inbox_window(self);
  if (window != nullptr) gtk_window_close(window);
}

static std::string startup_command() {
  char path[PATH_MAX + 1];
  const ssize_t length = readlink("/proc/self/exe", path, PATH_MAX);
  if (length <= 0 || length >= PATH_MAX) return {};
  std::string result = "\"";
  for (ssize_t index = 0; index < length; index++) {
    const char value = path[index];
    if (value == '\n' || value == '\r') return {};
    if (value == '\\' || value == '"' || value == '$' || value == '`') result += '\\';
    if (value == '%') result += '%';
    result += value;
  }
  return result + "\"";
}

static const gchar* launch_at_login_status() {
  g_autofree gchar* path = g_build_filename(g_get_user_config_dir(), "autostart", "com.inboxplus.app.desktop", nullptr);
  struct stat metadata;
  if (lstat(path, &metadata) != 0) return errno == ENOENT ? "off" : "unavailable";
  if (!S_ISREG(metadata.st_mode) || metadata.st_uid != getuid()) return "unavailable";
  g_autoptr(GKeyFile) entry = g_key_file_new();
  if (!g_key_file_load_from_file(entry, path, G_KEY_FILE_NONE, nullptr)) return "unavailable";
  g_autofree gchar* command = g_key_file_get_string(entry, "Desktop Entry", "Exec", nullptr);
  const auto expected = startup_command();
  if (expected.empty()) return "unavailable";
  const gboolean hidden = g_key_file_get_boolean(entry, "Desktop Entry", "Hidden", nullptr);
  return !hidden && command != nullptr && expected == command ? "on" : "off";
}

static gboolean set_launch_at_login(gboolean enabled) {
  g_autofree gchar* directory = g_build_filename(g_get_user_config_dir(), "autostart", nullptr);
  if (enabled && g_mkdir_with_parents(directory, 0700) != 0) return FALSE;
  g_autofree gchar* path = g_build_filename(directory, "com.inboxplus.app.desktop", nullptr);
  struct stat metadata;
  if (lstat(path, &metadata) == 0) {
    if (!S_ISREG(metadata.st_mode) || metadata.st_uid != getuid()) return FALSE;
  } else if (errno != ENOENT) return FALSE;
  if (!enabled) return g_unlink(path) == 0 || errno == ENOENT;
  const auto command = startup_command();
  if (command.empty()) return FALSE;
  g_autoptr(GKeyFile) entry = g_key_file_new();
  g_key_file_set_string(entry, "Desktop Entry", "Type", "Application");
  g_key_file_set_string(entry, "Desktop Entry", "Name", "Inbox+");
  g_key_file_set_string(entry, "Desktop Entry", "Exec", command.c_str());
  g_key_file_set_boolean(entry, "Desktop Entry", "Terminal", FALSE);
  gsize length;
  g_autofree gchar* contents = g_key_file_to_data(entry, &length, nullptr);
  return g_file_set_contents_full(path, contents, static_cast<gssize>(length),
      static_cast<GFileSetContentsFlags>(G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE), 0600, nullptr);
}

static gboolean protect_path(const gchar* path, gint64 mode) {
  if (!g_path_is_absolute(path)) return FALSE;
  const int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0) return FALSE;

  struct stat metadata;
  gboolean protected_path = FALSE;
  if (fstat(descriptor, &metadata) == 0 && metadata.st_uid == getuid() &&
      ((S_ISDIR(metadata.st_mode) && mode == 0700) ||
       (S_ISREG(metadata.st_mode) && mode == 0600))) {
    const std::string descriptor_path =
        "/proc/self/fd/" + std::to_string(descriptor);
    char resolved_path[PATH_MAX + 1];
    const ssize_t path_length =
        readlink(descriptor_path.c_str(), resolved_path, PATH_MAX);
    g_autofree gchar* support_path =
        g_build_filename(g_get_user_data_dir(), APPLICATION_ID, nullptr);
    char* support_root = realpath(support_path, nullptr);
    if (path_length > 0 && support_root != nullptr) {
      resolved_path[path_length] = '\0';
      const std::string root(support_root);
      const std::string target(resolved_path);
      if (target == root || target.compare(0, root.size() + 1, root + "/") == 0) {
        protected_path = fchmod(descriptor, static_cast<mode_t>(mode)) == 0;
      }
    }
    free(support_root);
  }
  close(descriptor);
  return protected_path;
}

static void native_method_call_cb(FlMethodChannel*, FlMethodCall* method_call,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "capabilities") == 0) {
    g_autoptr(FlValue) capabilities = fl_value_new_map();
    g_autoptr(FlValue) web_login_platforms = fl_value_new_list();
#ifdef INBOXPLUS_LINUX_WEB_LOGIN
    fl_value_append_take(web_login_platforms, fl_value_new_string("instagram"));
    fl_value_append_take(web_login_platforms, fl_value_new_string("messenger"));
#endif
    fl_value_set_string(capabilities, "web_login_platforms", web_login_platforms);
    fl_value_set_string_take(capabilities, "launch_at_login_status", fl_value_new_string(launch_at_login_status()));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(capabilities));
  } else if (g_strcmp0(method, "takeNotificationRoute") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(self->pending_notification_route));
    g_clear_pointer(&self->pending_notification_route, fl_value_unref);
  } else if (g_strcmp0(method, "setLaunchAtLogin") == 0) {
    FlValue* enabled = fl_value_lookup_string(arguments, "enabled");
    if (enabled == nullptr || fl_value_get_type(enabled) != FL_VALUE_TYPE_BOOL) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("invalid_arguments", nullptr, nullptr));
    } else if (!set_launch_at_login(fl_value_get_bool(enabled))) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("launch_at_login_failed", nullptr, nullptr));
    } else {
      g_autoptr(FlValue) status = fl_value_new_map();
      fl_value_set_string_take(status, "status", fl_value_new_string(launch_at_login_status()));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(status));
    }
  } else if (g_strcmp0(method, "webLogin") == 0) {
#ifdef INBOXPLUS_LINUX_WEB_LOGIN
    inboxplus_web_login(GTK_APPLICATION(self), method_call);
    return;
#else
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "web_login_unavailable", nullptr, nullptr));
#endif
  } else if (g_strcmp0(method, "requestQuit") == 0) {
    request_quit(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setUnreadBadge") == 0) {
    FlValue* count = fl_value_lookup_string(arguments, "count");
    if (count == nullptr || fl_value_get_type(count) != FL_VALUE_TYPE_INT || fl_value_get_int(count) < 0) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("invalid_arguments", nullptr, nullptr));
    } else {
      const gint64 unread = fl_value_get_int(count);
      const auto label = unread > 0 ? std::to_string(unread) : std::string();
      app_indicator_set_label(self->indicator, label.c_str(), "999+");
      GDBusConnection* connection = g_application_get_dbus_connection(G_APPLICATION(self));
      if (connection != nullptr) {
        GVariantBuilder values;
        g_variant_builder_init(&values, G_VARIANT_TYPE_VARDICT);
        g_variant_builder_add(&values, "{sv}", "count", g_variant_new_int64(unread));
        g_variant_builder_add(&values, "{sv}", "count-visible", g_variant_new_boolean(unread > 0));
        g_dbus_connection_emit_signal(connection, nullptr, "/com/inboxplus/app",
            "com.canonical.Unity.LauncherEntry", "Update",
            g_variant_new("(s@a{sv})", "application://com.inboxplus.app.desktop", g_variant_builder_end(&values)), nullptr);
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (g_strcmp0(method, "cancelWebLogin") == 0) {
#ifdef INBOXPLUS_LINUX_WEB_LOGIN
    inboxplus_cancel_web_login();
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "legacyProfileStatus") == 0) {
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string_take(status, "has_legacy_profile", fl_value_new_bool(FALSE));
    fl_value_set_string_take(status, "profile_names", fl_value_new_list());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(status));
  } else if (g_strcmp0(method, "notificationStatus") == 0) {
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string_take(status, "status", fl_value_new_string("unavailable"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(status));
  } else if (g_strcmp0(method, "requestNotificationPermission") == 0) {
    g_autoptr(FlValue) available = fl_value_new_bool(
        g_application_get_dbus_connection(G_APPLICATION(self)) != nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(available));
  } else if (g_strcmp0(method, "notify") == 0) {
    if (g_application_get_dbus_connection(G_APPLICATION(self)) == nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "notification_unavailable", nullptr, nullptr));
    } else {
      FlValue* title = fl_value_lookup_string(arguments, "title");
      FlValue* body = fl_value_lookup_string(arguments, "body");
      g_autoptr(GNotification) notification = g_notification_new(
          title != nullptr && fl_value_get_type(title) == FL_VALUE_TYPE_STRING ? fl_value_get_string(title) : "Inbox+");
      g_notification_set_body(notification,
          body != nullptr && fl_value_get_type(body) == FL_VALUE_TYPE_STRING ? fl_value_get_string(body) : "New message");
      FlValue* route = fl_value_lookup_string(arguments, "route");
      FlValue* account = route != nullptr && fl_value_get_type(route) == FL_VALUE_TYPE_MAP
                            ? fl_value_lookup_string(route, "account_id") : nullptr;
      FlValue* conversation = route != nullptr && fl_value_get_type(route) == FL_VALUE_TYPE_MAP
                                 ? fl_value_lookup_string(route, "conversation_id") : nullptr;
      if (account != nullptr && conversation != nullptr &&
          fl_value_get_type(account) == FL_VALUE_TYPE_STRING &&
          fl_value_get_type(conversation) == FL_VALUE_TYPE_STRING) {
        g_notification_set_default_action_and_target(notification, "app.open-conversation", "(ss)",
            fl_value_get_string(account), fl_value_get_string(conversation));
      } else {
        g_notification_set_default_action(notification, "app.show-inbox");
      }
      g_application_send_notification(G_APPLICATION(self), "new-message",
                                      notification);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (g_strcmp0(method, "setHasUnfinishedWork") == 0) {
    FlValue* value = fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
                         ? fl_value_lookup_string(arguments, "value")
                         : nullptr;
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
      self->has_unfinished_work = fl_value_get_bool(value);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_arguments", nullptr, nullptr));
    }
  } else if (g_strcmp0(method, "protectPath") == 0) {
    FlValue* path = fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
                        ? fl_value_lookup_string(arguments, "path")
                        : nullptr;
    FlValue* mode = fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
                        ? fl_value_lookup_string(arguments, "mode")
                        : nullptr;
    if (path == nullptr || mode == nullptr ||
        fl_value_get_type(path) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(mode) != FL_VALUE_TYPE_INT) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_arguments", nullptr, nullptr));
    } else if (protect_path(fl_value_get_string(path), fl_value_get_int(mode))) {
      g_autoptr(FlValue) protected_path = fl_value_new_bool(TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(protected_path));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "path_protection_failed", nullptr, nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static gboolean window_delete_cb(GtkWidget* window, GdkEvent*, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_object_get_data(G_OBJECT(window), "inboxplus-close-prepared") != nullptr) return FALSE;
  if (g_object_get_data(G_OBJECT(window), "inboxplus-close-pending") != nullptr) return TRUE;
  if (self->has_unfinished_work && (self->quit_requested || !self->indicator_connected)) {
    GtkWidget* dialog = gtk_message_dialog_new(
        GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_NONE,
        "Close Inbox+?");
    gtk_message_dialog_format_secondary_text(
        GTK_MESSAGE_DIALOG(dialog),
        "You have unfinished drafts or pending sends. Keep Inbox+ open to finish them.");
    gtk_dialog_add_buttons(GTK_DIALOG(dialog), "_Keep open", GTK_RESPONSE_CANCEL,
                           "_Close", GTK_RESPONSE_ACCEPT, nullptr);
    gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_CANCEL);
    const gint response = gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
    if (response != GTK_RESPONSE_ACCEPT) { self->quit_requested = FALSE; return TRUE; }
  }
  auto* channel = static_cast<FlMethodChannel*>(
      g_object_get_data(G_OBJECT(window), "inboxplus-native-channel"));
  if (channel == nullptr) return TRUE;
  g_object_set_data(G_OBJECT(window), "inboxplus-close-pending", GINT_TO_POINTER(1));
  gtk_widget_set_sensitive(window, FALSE);
  fl_method_channel_invoke_method(channel, "prepareToClose", nullptr, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        GtkWidget* closing_window = GTK_WIDGET(data);
        g_autoptr(GError) error = nullptr;
        g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
            FL_METHOD_CHANNEL(object), result, &error);
        FlValue* value = response != nullptr && FL_IS_METHOD_SUCCESS_RESPONSE(response)
            ? fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response))
            : nullptr;
        const gboolean prepared = error == nullptr && value != nullptr &&
            fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
        if (gtk_widget_get_realized(closing_window)) {
          MyApplication* app = MY_APPLICATION(gtk_window_get_application(GTK_WINDOW(closing_window)));
          g_object_set_data(G_OBJECT(closing_window), "inboxplus-close-pending", nullptr);
          if (prepared) {
            if (!app->quit_requested && app->indicator_connected) {
              gtk_widget_set_sensitive(closing_window, TRUE);
              gtk_widget_hide(closing_window);
            } else {
              g_object_set_data(G_OBJECT(closing_window), "inboxplus-close-prepared", GINT_TO_POINTER(1));
              gtk_window_close(GTK_WINDOW(closing_window));
            }
          } else {
            app->quit_requested = FALSE;
            gtk_widget_set_sensitive(closing_window, TRUE);
            GtkWidget* dialog = gtk_message_dialog_new(GTK_WINDOW(closing_window),
                GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_OK,
                "Your changes could not be saved. Keep Inbox+ open and try again.");
            gtk_dialog_run(GTK_DIALOG(dialog));
            gtk_widget_destroy(dialog);
          }
        }
        g_object_unref(closing_window);
      }, g_object_ref(window));
  return TRUE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* existing_window = inbox_window(self);
  if (existing_window != nullptr) {
    gtk_window_present(existing_window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  g_signal_connect(window, "delete-event", G_CALLBACK(window_delete_cb), self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Inbox+");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Inbox+");
  }

  gtk_window_set_default_size(window, 1100, 700);
  GdkGeometry geometry = {};
  geometry.min_width = 900;
  geometry.min_height = 600;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* native_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "inboxplus/native", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(native_channel,
                                           native_method_call_cb, self,
                                           nullptr);
  g_object_set_data_full(G_OBJECT(view), "inboxplus-native-channel",
                         native_channel, g_object_unref);
  g_object_set_data(G_OBJECT(window), "inboxplus-native-channel", native_channel);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon = g_build_filename(directory, "share", "icons", "hicolor",
        "512x512", "apps", APPLICATION_ID ".png", nullptr);
    gtk_window_set_default_icon_from_file(icon, nullptr);
    self->indicator = app_indicator_new(APPLICATION_ID, icon, APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  } else {
    self->indicator = app_indicator_new(APPLICATION_ID, "mail-unread", APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  }
  GtkWidget* tray_menu = gtk_menu_new();
  GtkWidget* open_item = gtk_menu_item_new_with_label("Open Inbox+");
  g_signal_connect_swapped(open_item, "activate", G_CALLBACK(g_application_activate), application);
  gtk_menu_shell_append(GTK_MENU_SHELL(tray_menu), open_item);
  GtkWidget* quit_item = gtk_menu_item_new_with_label("Quit Inbox+");
  g_signal_connect_swapped(quit_item, "activate", G_CALLBACK(request_quit), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(tray_menu), quit_item);
  gtk_widget_show_all(tray_menu);
  app_indicator_set_menu(self->indicator, GTK_MENU(tray_menu));
  g_signal_connect(self->indicator, "connection-changed", G_CALLBACK(+[](AppIndicator*, gboolean connected, gpointer data) {
    MyApplication* app = MY_APPLICATION(data);
    app->indicator_connected = connected;
    GtkWindow* window = inbox_window(app);
    if (!connected && window != nullptr && !gtk_widget_get_visible(GTK_WIDGET(window))) gtk_window_present(window);
  }), self);
  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
  GSimpleAction* show_inbox = g_simple_action_new("show-inbox", nullptr);
  g_signal_connect_swapped(show_inbox, "activate",
                            G_CALLBACK(g_application_activate), application);
  g_action_map_add_action(G_ACTION_MAP(application), G_ACTION(show_inbox));
  g_object_unref(show_inbox);
  GSimpleAction* open_conversation = g_simple_action_new("open-conversation", G_VARIANT_TYPE("(ss)"));
  g_signal_connect(open_conversation, "activate", G_CALLBACK(+[](GSimpleAction*, GVariant* parameter, gpointer data) {
    MyApplication* app = MY_APPLICATION(data);
    const gchar* account;
    const gchar* conversation;
    g_variant_get(parameter, "(&s&s)", &account, &conversation);
    g_clear_pointer(&app->pending_notification_route, fl_value_unref);
    app->pending_notification_route = fl_value_new_map();
    fl_value_set_string_take(app->pending_notification_route, "account_id", fl_value_new_string(account));
    fl_value_set_string_take(app->pending_notification_route, "conversation_id", fl_value_new_string(conversation));
    g_application_activate(G_APPLICATION(app));
    GtkWindow* window = inbox_window(app);
    FlMethodChannel* channel = window == nullptr ? nullptr : FL_METHOD_CHANNEL(
        g_object_get_data(G_OBJECT(window), "inboxplus-native-channel"));
    if (channel != nullptr) {
      fl_method_channel_invoke_method(channel, "notificationActivated", nullptr, nullptr, nullptr, nullptr);
    }
  }), self);
  g_action_map_add_action(G_ACTION_MAP(application), G_ACTION(open_conversation));
  g_object_unref(open_conversation);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  g_clear_object(&self->indicator);
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->pending_notification_route, fl_value_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(0), nullptr));
}
