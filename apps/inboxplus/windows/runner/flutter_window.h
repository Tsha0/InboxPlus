#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>
#include <deque>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> native_channel_;
  bool has_unfinished_work_ = false;
  bool notification_icon_added_ = false;
  bool notification_active_ = false;
  std::deque<flutter::EncodableMap> notifications_;
  std::optional<flutter::EncodableMap> displayed_notification_route_;
  std::optional<flutter::EncodableMap> pending_notification_route_;
  bool close_pending_ = false;
  bool close_prepared_ = false;
  bool quit_requested_ = false;
  int unread_count_ = 0;
  bool UpdateUnreadBadge();
  bool ShowNextNotification();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
