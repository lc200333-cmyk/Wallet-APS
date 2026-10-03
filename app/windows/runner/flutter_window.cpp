#include "flutter_window.h"

#include <algorithm>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) {
    return L"Wallet APS";
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return L"Wallet APS";
  }
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}
}  // namespace

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "wallet_aps/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "startDrag") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ReleaseCapture();
            SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          }
          result->Success();
        } else if (call.method_name() == "showLogin") {
          SetLoginWindowMode();
          result->Success();
        } else if (call.method_name() == "showLoginExpanded") {
          SetLoginWindowMode(true);
          result->Success();
        } else if (call.method_name() == "showMain") {
          const auto* title =
              std::get_if<std::string>(call.arguments());
          SetMainWindowMode(
              Utf16FromUtf8(title == nullptr ? std::string() : *title));
          result->Success();
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
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetLoginWindowMode(bool expanded) {
  SetWindowMode(true, expanded);
}

void FlutterWindow::SetMainWindowMode(const std::wstring&) {
  SetWindowMode(false, false, L"Wallet APS");
}

void FlutterWindow::SetWindowMode(bool login, bool expanded,
                                  const std::wstring& title) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  RECT current_bounds{};
  GetWindowRect(hwnd, &current_bounds);
  const bool preserve_login_position = login && login_mode_;

  SetWindowLongPtr(hwnd, GWL_STYLE,
                   login ? WS_POPUP : WS_OVERLAPPEDWINDOW);
  // Use Unicode escapes so the taskbar title does not depend on the compiler's
  // source-file code page.
  SetWindowText(hwnd,
                login ? L"\u041F\u0430\u0440\u043E\u043B\u044C"
                      : title.c_str());

  const double scale = GetDpiForWindow(hwnd) / 96.0;
  int width = static_cast<int>((login ? 562 : 1280) * scale);
  const int login_height = expanded ? 650 : 590;
  // The classic SPB Wallet layout is intentionally taller than a 16:9
  // dashboard. Keep the initial desktop proportions of the W1 reference.
  int height = static_cast<int>((login ? login_height : 1010) * scale);

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  const int work_width = work.right - work.left;
  const int work_height = work.bottom - work.top;
  width = std::min(width, work_width);
  height = std::min(height, work_height);
  const int centered_x = work.left + (work_width - width) / 2;
  const int centered_y = work.top + (work_height - height) / 2;
  const int x = preserve_login_position
                    ? std::clamp(current_bounds.left, work.left,
                                 work.right - width)
                    : centered_x;
  const int y = preserve_login_position
                    ? std::clamp(current_bounds.top, work.top,
                                 work.bottom - height)
                    : centered_y;

  SetWindowPos(hwnd, HWND_TOP, x, y, width, height,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  login_mode_ = login;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Let Flutter clear app-owned clipboard data and save the vault before the
  // native window is destroyed. The Dart side then terminates the process.
  if (message == WM_CLOSE && window_channel_) {
    window_channel_->InvokeMethod(
        "requestClose", std::make_unique<flutter::EncodableValue>());
    return 0;
  }

  // The login window is frameless. Let the Win32 host classify its top strip
  // as HTCAPTION before Flutter gets a chance to consume WM_NCHITTEST. This
  // keeps the window draggable with a mouse, pen, or touch gesture.
  if (message == WM_NCHITTEST) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
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
