#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <aclapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <cwchar>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kNotificationMessage = WM_APP + 1;
const UINT kClosePreparedMessage = RegisterWindowMessageW(L"com.inboxplus.app.close-prepared");
constexpr UINT kNextNotificationMessage = WM_APP + 2;
constexpr wchar_t kStartupKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const UINT kTaskbarCreatedMessage = RegisterWindowMessageW(L"TaskbarButtonCreated");

HICON unread_icon(int count) {
  BITMAPINFO bitmap{};
  bitmap.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap.bmiHeader.biWidth = 32;
  bitmap.bmiHeader.biHeight = -32;
  bitmap.bmiHeader.biPlanes = 1;
  bitmap.bmiHeader.biBitCount = 32;
  bitmap.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HDC canvas = CreateCompatibleDC(nullptr);
  if (canvas == nullptr) return nullptr;
  HBITMAP color = CreateDIBSection(canvas, &bitmap, DIB_RGB_COLORS, &pixels, nullptr, 0);
  BYTE mask_bits[128];
  std::fill_n(mask_bits, 128, static_cast<BYTE>(0xff));
  for (int y = 0; y < 32; y++) {
    for (int x = 0; x < 32; x++) {
      const int dx = x - 16;
      const int dy = y - 16;
      if (dx * dx + dy * dy <= 256) mask_bits[y * 4 + x / 8] &= static_cast<BYTE>(~(0x80 >> (x % 8)));
    }
  }
  HBITMAP mask = CreateBitmap(32, 32, 1, 1, mask_bits);
  if (color == nullptr || mask == nullptr) {
    if (color != nullptr) DeleteObject(color);
    if (mask != nullptr) DeleteObject(mask);
    DeleteDC(canvas);
    return nullptr;
  }
  auto* argb = static_cast<DWORD*>(pixels);
  std::fill_n(argb, 32 * 32, 0);
  const auto previous = SelectObject(canvas, color);
  HFONT font = CreateFontW(-21, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
      DEFAULT_PITCH, L"Segoe UI");
  const auto previous_font = SelectObject(canvas, font);
  SetTextColor(canvas, RGB(255, 255, 255));
  SetBkMode(canvas, TRANSPARENT);
  RECT rect{0, 0, 32, 32};
  const auto label = count > 99 ? std::wstring(L"99+") : std::to_wstring(count);
  DrawTextW(canvas, label.c_str(), -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  for (int y = 0; y < 32; y++) {
    for (int x = 0; x < 32; x++) {
      const int dx = x - 16;
      const int dy = y - 16;
      if (dx * dx + dy * dy <= 256) argb[y * 32 + x] |= 0xff000000;
      else argb[y * 32 + x] = 0;
    }
  }
  SelectObject(canvas, previous_font);
  SelectObject(canvas, previous);
  DeleteObject(font);
  ICONINFO info{TRUE, 0, 0, mask, color};
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(mask);
  DeleteObject(color);
  DeleteDC(canvas);
  return icon;
}

std::wstring startup_command() {
  std::vector<wchar_t> path(32768);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return {};
  return L"\"" + std::wstring(path.data(), length) + L"\"";
}

std::string launch_at_login_status() {
  HKEY key;
  const LSTATUS opened = RegOpenKeyExW(HKEY_CURRENT_USER, kStartupKey, 0, KEY_QUERY_VALUE, &key);
  if (opened == ERROR_FILE_NOT_FOUND) return "off";
  if (opened != ERROR_SUCCESS) return "unavailable";
  DWORD type = 0;
  DWORD bytes = 0;
  LSTATUS status = RegQueryValueExW(key, L"Inbox+", nullptr, &type, nullptr, &bytes);
  std::vector<wchar_t> command(bytes / sizeof(wchar_t) + 1, L'\0');
  if (status == ERROR_SUCCESS && type == REG_SZ) {
    status = RegQueryValueExW(key, L"Inbox+", nullptr, &type, reinterpret_cast<BYTE*>(command.data()), &bytes);
  }
  RegCloseKey(key);
  if (status == ERROR_FILE_NOT_FOUND) return "off";
  if (status != ERROR_SUCCESS) return "unavailable";
  const auto expected = startup_command();
  if (expected.empty()) return "unavailable";
  return type == REG_SZ && std::wstring(command.data()) == expected ? "on" : "off";
}

bool set_launch_at_login(bool enabled) {
  HKEY key;
  const LSTATUS opened = enabled
      ? RegCreateKeyExW(HKEY_CURRENT_USER, kStartupKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr)
      : RegOpenKeyExW(HKEY_CURRENT_USER, kStartupKey, 0, KEY_SET_VALUE, &key);
  if (!enabled && opened == ERROR_FILE_NOT_FOUND) return true;
  if (opened != ERROR_SUCCESS) return false;
  const auto command = startup_command();
  const LSTATUS status = enabled && !command.empty()
      ? RegSetValueExW(key, L"Inbox+", 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)))
      : enabled ? ERROR_BAD_PATHNAME : RegDeleteValueW(key, L"Inbox+");
  RegCloseKey(key);
  return status == ERROR_SUCCESS || (!enabled && status == ERROR_FILE_NOT_FOUND);
}
const flutter::EncodableValue* argument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
  if (map == nullptr) return nullptr;
  const auto value = map->find(flutter::EncodableValue(key));
  return value == map->end() ? nullptr : &value->second;
}

std::wstring utf16(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (length == 0) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::wstring final_path(HANDLE file) {
  const DWORD length = GetFinalPathNameByHandleW(file, nullptr, 0,
      FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (length == 0) return {};
  std::wstring result(length, L'\0');
  const DWORD written = GetFinalPathNameByHandleW(file, result.data(), length,
      FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (written == 0 || written >= length) return {};
  result.resize(written);
  return result;
}

bool protect_path(const std::string& input, int mode) {
  if (mode != 0700 && mode != 0600) return false;
  const std::wstring path = utf16(input);
  if (path.empty() || path.find(L'\0') != std::wstring::npos) return false;
  PWSTR roaming = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT,
                                 nullptr, &roaming))) return false;
  const std::wstring support = std::wstring(roaming) + L"\\com.inboxplus\\Inbox+";
  CoTaskMemFree(roaming);
  HANDLE root = CreateFileW(support.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr);
  if (root == INVALID_HANDLE_VALUE) return false;
  const std::wstring root_path = final_path(root);
  CloseHandle(root);
  if (root_path.empty()) return false;
  HANDLE file = CreateFileW(path.c_str(), READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  bool success = false;
  HANDLE token = nullptr;
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  PACL acl = nullptr;
  do {
    FILE_ATTRIBUTE_TAG_INFO attributes{};
    if (!GetFileInformationByHandleEx(file, FileAttributeTagInfo, &attributes,
                                     sizeof(attributes))) break;
    if ((attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) break;
    const bool directory = (attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    if ((directory && mode != 0700) || (!directory && mode != 0600)) break;
    const std::wstring resolved = final_path(file);
    if (resolved.size() < root_path.size() ||
        CompareStringOrdinal(resolved.c_str(), static_cast<int>(root_path.size()),
                             root_path.c_str(), static_cast<int>(root_path.size()),
                             TRUE) != CSTR_EQUAL ||
        (resolved.size() > root_path.size() && resolved[root_path.size()] != L'\\')) break;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) break;
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    if (size == 0) break;
    std::vector<BYTE> token_data(size);
    if (!GetTokenInformation(token, TokenUser, token_data.data(), size, &size)) break;
    auto* user = reinterpret_cast<TOKEN_USER*>(token_data.data());
    PSID owner = nullptr;
    if (GetSecurityInfo(file, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                        &owner, nullptr, nullptr, nullptr, &descriptor) != ERROR_SUCCESS ||
        !EqualSid(owner, user->User.Sid)) break;
    EXPLICIT_ACCESSW access{};
    access.grfAccessPermissions = FILE_ALL_ACCESS;
    access.grfAccessMode = SET_ACCESS;
    access.grfInheritance = directory ? SUB_CONTAINERS_AND_OBJECTS_INHERIT : NO_INHERITANCE;
    access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
    access.Trustee.TrusteeType = TRUSTEE_IS_USER;
    access.Trustee.ptstrName = static_cast<LPWSTR>(user->User.Sid);
    if (SetEntriesInAclW(1, &access, nullptr, &acl) != ERROR_SUCCESS) break;
    success = SetSecurityInfo(file, SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
        nullptr, nullptr, acl, nullptr) == ERROR_SUCCESS;
  } while (false);
  if (acl != nullptr) LocalFree(acl);
  if (descriptor != nullptr) LocalFree(descriptor);
  if (token != nullptr) CloseHandle(token);
  CloseHandle(file);
  return success;
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  native_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "inboxplus/native",
          &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "capabilities") {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("web_login_platforms"),
               flutter::EncodableValue(flutter::EncodableList{})},
              {flutter::EncodableValue("launch_at_login_status"), flutter::EncodableValue(launch_at_login_status())},
          }));
        } else if (method == "setLaunchAtLogin") {
          const auto* value = argument(call, "enabled");
          const auto* enabled = value == nullptr ? nullptr : std::get_if<bool>(value);
          if (enabled == nullptr) result->Error("invalid_arguments");
          else if (!set_launch_at_login(*enabled)) result->Error("launch_at_login_failed");
          else result->Success(flutter::EncodableValue(flutter::EncodableMap{{flutter::EncodableValue("status"), flutter::EncodableValue(launch_at_login_status())}}));
        } else if (method == "setUnreadBadge") {
          const auto* value = argument(call, "count");
          const auto* count = value == nullptr ? nullptr : std::get_if<int32_t>(value);
          if (count == nullptr || *count < 0) result->Error("invalid_arguments");
          else {
            unread_count_ = *count;
            if (UpdateUnreadBadge()) result->Success();
            else result->Error("badge_unavailable");
          }
        } else if (method == "requestQuit") {
          quit_requested_ = true;
          PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "webLogin") {
          result->Error("web_login_unavailable");
        } else if (method == "cancelWebLogin") {
          result->Success();
        } else if (method == "legacyProfileStatus") {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("has_legacy_profile"), flutter::EncodableValue(false)},
              {flutter::EncodableValue("profile_names"), flutter::EncodableValue(flutter::EncodableList{})},
          }));
        } else if (method == "setHasUnfinishedWork") {
          const auto* value = argument(call, "value");
          const auto* unfinished = value == nullptr ? nullptr : std::get_if<bool>(value);
          if (unfinished == nullptr) result->Error("invalid_arguments");
          else {
            has_unfinished_work_ = *unfinished;
            result->Success();
          }
        } else if (method == "protectPath") {
          const auto* path_value = argument(call, "path");
          const auto* mode_value = argument(call, "mode");
          const auto* path = path_value == nullptr ? nullptr : std::get_if<std::string>(path_value);
          const auto* mode = mode_value == nullptr ? nullptr : std::get_if<int32_t>(mode_value);
          if (path == nullptr || mode == nullptr) result->Error("invalid_arguments");
          else if (protect_path(*path, *mode)) result->Success(flutter::EncodableValue(true));
          else result->Error("path_protection_failed");
        } else if (method == "requestNotificationPermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "notificationStatus") {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("status"), flutter::EncodableValue("unavailable")},
              {flutter::EncodableValue("can_open_settings"), flutter::EncodableValue(true)}}));
        } else if (method == "openNotificationSettings") {
          if (reinterpret_cast<INT_PTR>(ShellExecuteW(GetHandle(), L"open", L"ms-settings:notifications", nullptr, nullptr, SW_SHOWNORMAL)) > 32) {
            result->Success();
          } else result->Error("notification_settings_unavailable");
        } else if (method == "takeNotificationRoute") {
          if (pending_notification_route_) {
            auto route = std::move(*pending_notification_route_);
            pending_notification_route_.reset();
            result->Success(flutter::EncodableValue(std::move(route)));
          } else result->Success();
        } else if (method == "notify") {
          const auto* values = call.arguments() == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(call.arguments());
          if (values == nullptr) result->Error("invalid_arguments");
          else {
            notifications_.push_back(*values);
            if (ShowNextNotification()) result->Success();
            else result->Error("notification_unavailable");
          }
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (notification_icon_added_) {
    NOTIFYICONDATAW icon{};
    icon.cbSize = sizeof(icon);
    icon.hWnd = GetHandle();
    icon.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &icon);
    notification_icon_added_ = false;
  }
  native_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kClosePreparedMessage) {
    if (!close_pending_) return 0;
    close_pending_ = false;
    if (wparam == 1) {
      if (lparam == 1) {
        close_prepared_ = true;
        PostMessageW(hwnd, WM_CLOSE, 0, 0);
      } else if (quit_requested_ || !notification_icon_added_) {
        PostMessageW(hwnd, WM_CLOSE, 0, 0);
      } else {
        EnableWindow(hwnd, TRUE);
        ShowWindow(hwnd, SW_HIDE);
      }
    } else {
      quit_requested_ = false;
      EnableWindow(hwnd, TRUE);
      MessageBoxW(hwnd, L"Your changes could not be saved. Keep Inbox+ open and try again.",
                  L"Inbox+", MB_OK | MB_ICONWARNING);
    }
    return 0;
  }
  if (message == kTaskbarCreatedMessage) {
    notification_icon_added_ = false;
    notification_active_ = false;
    displayed_notification_route_.reset();
    UpdateUnreadBadge();
    PostMessageW(hwnd, kNextNotificationMessage, 0, 0);
    return 0;
  }
  if (message == kNextNotificationMessage) {
    ShowNextNotification();
    return 0;
  }
  if (message == kNotificationMessage) {
    if (lparam == NIN_BALLOONUSERCLICK || lparam == WM_LBUTTONUP) {
      if (lparam == NIN_BALLOONUSERCLICK && displayed_notification_route_) {
        pending_notification_route_ = std::move(displayed_notification_route_);
        displayed_notification_route_.reset();
        native_channel_->InvokeMethod("notificationActivated", nullptr);
      }
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
    if (lparam == NIN_BALLOONUSERCLICK || lparam == NIN_BALLOONHIDE || lparam == NIN_BALLOONTIMEOUT) {
      notification_active_ = false;
      displayed_notification_route_.reset();
      PostMessageW(hwnd, kNextNotificationMessage, 0, 0);
    }
    if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, 1, L"Open Inbox+");
      AppendMenuW(menu, MF_STRING, 2, L"Quit Inbox+");
      POINT point;
      GetCursorPos(&point);
      SetForegroundWindow(hwnd);
      const UINT selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      if (selected == 1) { ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd); }
      if (selected == 2) { quit_requested_ = true; PostMessageW(hwnd, WM_CLOSE, 0, 0); }
    }
    return 0;
  }
  if (message == WM_CLOSE && !close_prepared_) {
    if (close_pending_) return 0;
    if (quit_requested_ && has_unfinished_work_ &&
        MessageBoxW(hwnd,
            L"You have unfinished drafts or pending sends. Close Inbox+?",
            L"Inbox+", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES) {
      quit_requested_ = false;
      return 0;
    }
    if (native_channel_ == nullptr) return 0;
    close_pending_ = true;
    EnableWindow(hwnd, FALSE);
    const bool terminating = quit_requested_ || !notification_icon_added_;
    auto reply = [hwnd, terminating](bool prepared) {
      if (IsWindow(hwnd)) PostMessageW(hwnd, kClosePreparedMessage, prepared ? 1 : 0, terminating ? 1 : 0);
    };
    native_channel_->InvokeMethod(
        terminating ? "prepareToTerminate" : "prepareToClose", nullptr,
        std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
            [reply](const flutter::EncodableValue* result) {
              const bool* prepared = result == nullptr ? nullptr : std::get_if<bool>(result);
              reply(prepared != nullptr && *prepared);
            },
            [reply](const std::string&, const std::string&, const flutter::EncodableValue*) {
              reply(false);
            }, [reply]() { reply(false); }));
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::UpdateUnreadBadge() {
  HICON badge = unread_count_ > 0 ? unread_icon(unread_count_) : nullptr;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = GetHandle();
  icon.uID = 1;
  icon.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
  icon.uCallbackMessage = kNotificationMessage;
  icon.hIcon = badge != nullptr ? badge : LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  const auto tip = unread_count_ > 0 ? L"Inbox+, " + std::to_wstring(unread_count_) + L" unread" : std::wstring(L"Inbox+");
  wcsncpy_s(icon.szTip, tip.c_str(), _TRUNCATE);
  const bool displayed = Shell_NotifyIconW(notification_icon_added_ ? NIM_MODIFY : NIM_ADD, &icon) != FALSE;
  if (displayed) notification_icon_added_ = true;
  ITaskbarList3* taskbar = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar)))) {
    if (SUCCEEDED(taskbar->HrInit())) taskbar->SetOverlayIcon(GetHandle(), badge, tip.c_str());
    taskbar->Release();
  }
  if (badge != nullptr) DestroyIcon(badge);
  return displayed;
}

bool FlutterWindow::ShowNextNotification() {
  if (notification_active_ || notifications_.empty()) return true;
  const auto values = std::move(notifications_.front());
  notifications_.pop_front();
  auto value = [&values](const char* key) -> const flutter::EncodableValue* {
    const auto found = values.find(flutter::EncodableValue(key));
    return found == values.end() ? nullptr : &found->second;
  };
  const auto* title_value = value("title");
  const auto* body_value = value("body");
  const auto* sound_value = value("sound");
  const auto* route_value = value("route");
  const auto* title = title_value == nullptr ? nullptr : std::get_if<std::string>(title_value);
  const auto* body = body_value == nullptr ? nullptr : std::get_if<std::string>(body_value);
  const auto* sound = sound_value == nullptr ? nullptr : std::get_if<bool>(sound_value);
  const auto* route = route_value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(route_value);
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = GetHandle();
  icon.uID = 1;
  icon.uFlags = NIF_ICON | NIF_TIP | NIF_INFO | NIF_MESSAGE;
  icon.uCallbackMessage = kNotificationMessage;
  icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon.szTip, L"Inbox+");
  wcsncpy_s(icon.szInfoTitle, utf16(title == nullptr ? "Inbox+" : *title).c_str(), _TRUNCATE);
  wcsncpy_s(icon.szInfo, utf16(body == nullptr ? "New message" : *body).c_str(), _TRUNCATE);
  icon.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
  if (sound != nullptr && !*sound) icon.dwInfoFlags |= NIIF_NOSOUND;
  if (!Shell_NotifyIconW(notification_icon_added_ ? NIM_MODIFY : NIM_ADD, &icon)) return false;
  notification_icon_added_ = true;
  // Submit one balloon at a time so a later message cannot replace its click route.
  notification_active_ = true;
  if (route != nullptr) displayed_notification_route_ = *route;
  return true;
}
