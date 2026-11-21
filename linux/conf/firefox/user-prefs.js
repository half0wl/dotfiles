// Block sites from overriding browser/extension shortcuts (e.g. Ctrl+. for containers)
user_pref("permissions.default.shortcuts", 2);

// Disable GTK emoji picker so Ctrl+. reaches the containers extension in text fields
user_pref("widget.gtk.native-emoji-dialog", false);

// KDE Plasma global menu (Wayland)
// Needs: sudo apt install appmenu-gtk3-module libdbusmenu-gtk3-4
user_pref("widget.gtk.global-menu.enabled", true);
user_pref("widget.gtk.global-menu.wayland.enabled", true);
user_pref("widget.gtk.native-context-menus", true);
