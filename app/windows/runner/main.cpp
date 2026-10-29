#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shlobj.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
void SetRegistryString(HKEY root, const std::wstring& subkey,
                       const wchar_t* name, const std::wstring& value) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(root, subkey.c_str(), 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, name, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(value.c_str()),
                 static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

void RegisterSwlFileAssociation() {
  wchar_t executable[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, executable, MAX_PATH) == 0) {
    return;
  }
  const std::wstring classes = L"Software\\Classes\\";
  const std::wstring prog_id = L"WalletAPSDesign.swl";
  // Offer Design in Open With without replacing the stable default handler.
  SetRegistryString(HKEY_CURRENT_USER,
                    classes + L".swl\\OpenWithProgids", prog_id.c_str(), L"");
  SetRegistryString(HKEY_CURRENT_USER, classes + prog_id, nullptr,
                    L"Wallet APS Design database");
  SetRegistryString(HKEY_CURRENT_USER,
                    classes + prog_id + L"\\DefaultIcon", nullptr,
                    L"\"" + std::wstring(executable) + L"\",0");
  SetRegistryString(HKEY_CURRENT_USER,
                    classes + prog_id + L"\\shell\\open\\command", nullptr,
                    L"\"" + std::wstring(executable) + L"\" \"%1\"");
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RegisterSwlFileAssociation();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(0, 0);
  // Password window: the 562 x 642 design at 75 %.
  Win32Window::Size size(422, 482);
  if (!window.Create(L"Wallet APS Design", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
