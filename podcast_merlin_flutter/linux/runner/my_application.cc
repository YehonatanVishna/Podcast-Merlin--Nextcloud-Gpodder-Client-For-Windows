#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void copy_file_if_exists(const gchar* src, const gchar* dest) {
  if (g_file_test(src, G_FILE_TEST_EXISTS)) {
    g_autoptr(GFile) src_file = g_file_new_for_path(src);
    g_autoptr(GFile) dest_file = g_file_new_for_path(dest);
    g_file_copy(src_file, dest_file, G_FILE_COPY_OVERWRITE, nullptr, nullptr, nullptr, nullptr);
  }
}

// Ensures .desktop file and icons exist in ~/.local/share for Wayland compositors (KDE Plasma, GNOME Shell)
static void ensure_linux_desktop_integration() {
  gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return;

  const gchar* data_home = g_get_user_data_dir();
  if (data_home == nullptr) {
    g_free(exe_path);
    return;
  }

  g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path);
  g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
  gchar* exe_dir_path = g_file_get_path(exe_dir);

  gchar* logo_png = nullptr;
  gchar* logo_svg = nullptr;

  gchar* candidate_png = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", "logo.png", nullptr);
  gchar* candidate_svg = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", "logo.svg", nullptr);

  if (g_file_test(candidate_png, G_FILE_TEST_EXISTS)) {
    logo_png = candidate_png;
  } else if (g_file_test("assets/images/logo.png", G_FILE_TEST_EXISTS)) {
    g_free(candidate_png);
    logo_png = g_strdup("assets/images/logo.png");
  } else {
    g_free(candidate_png);
  }

  if (g_file_test(candidate_svg, G_FILE_TEST_EXISTS)) {
    logo_svg = candidate_svg;
  } else if (g_file_test("assets/images/logo.svg", G_FILE_TEST_EXISTS)) {
    g_free(candidate_svg);
    logo_svg = g_strdup("assets/images/logo.svg");
  } else {
    g_free(candidate_svg);
  }

  gchar* apps_dir = g_build_filename(data_home, "applications", nullptr);
  gchar* pixmaps_dir = g_build_filename(data_home, "pixmaps", nullptr);
  gchar* icons_hicolor_scalable = g_build_filename(data_home, "icons", "hicolor", "scalable", "apps", nullptr);
  gchar* icons_hicolor_256 = g_build_filename(data_home, "icons", "hicolor", "256x256", "apps", nullptr);
  gchar* icons_hicolor_root = g_build_filename(data_home, "icons", "hicolor", nullptr);

  g_mkdir_with_parents(apps_dir, 0755);
  g_mkdir_with_parents(pixmaps_dir, 0755);
  g_mkdir_with_parents(icons_hicolor_scalable, 0755);
  g_mkdir_with_parents(icons_hicolor_256, 0755);

  gchar* local_index_theme = g_build_filename(icons_hicolor_root, "index.theme", nullptr);
  if (!g_file_test(local_index_theme, G_FILE_TEST_EXISTS)) {
    if (g_file_test("/usr/share/icons/hicolor/index.theme", G_FILE_TEST_EXISTS)) {
      copy_file_if_exists("/usr/share/icons/hicolor/index.theme", local_index_theme);
    }
  }
  g_free(local_index_theme);

  if (logo_png != nullptr) {
    gchar* dest_png1 = g_build_filename(icons_hicolor_256, "com.podcastmerlin.podcast_merlin_flutter.png", nullptr);
    gchar* dest_png2 = g_build_filename(icons_hicolor_256, "podcast_merlin_flutter.png", nullptr);
    gchar* dest_pixmap1 = g_build_filename(pixmaps_dir, "com.podcastmerlin.podcast_merlin_flutter.png", nullptr);
    gchar* dest_pixmap2 = g_build_filename(pixmaps_dir, "podcast_merlin_flutter.png", nullptr);

    copy_file_if_exists(logo_png, dest_png1);
    copy_file_if_exists(logo_png, dest_png2);
    copy_file_if_exists(logo_png, dest_pixmap1);
    copy_file_if_exists(logo_png, dest_pixmap2);

    g_free(dest_png1);
    g_free(dest_png2);
    g_free(dest_pixmap1);
    g_free(dest_pixmap2);
    g_free(logo_png);
  }

  if (logo_svg != nullptr) {
    gchar* dest_svg1 = g_build_filename(icons_hicolor_scalable, "com.podcastmerlin.podcast_merlin_flutter.svg", nullptr);
    gchar* dest_svg2 = g_build_filename(icons_hicolor_scalable, "podcast_merlin_flutter.svg", nullptr);
    gchar* dest_pixmap1 = g_build_filename(pixmaps_dir, "com.podcastmerlin.podcast_merlin_flutter.svg", nullptr);
    gchar* dest_pixmap2 = g_build_filename(pixmaps_dir, "podcast_merlin_flutter.svg", nullptr);

    copy_file_if_exists(logo_svg, dest_svg1);
    copy_file_if_exists(logo_svg, dest_svg2);
    copy_file_if_exists(logo_svg, dest_pixmap1);
    copy_file_if_exists(logo_svg, dest_pixmap2);

    g_free(dest_svg1);
    g_free(dest_svg2);
    g_free(dest_pixmap1);
    g_free(dest_pixmap2);
    g_free(logo_svg);
  }

  gchar* desktop_path1 = g_build_filename(apps_dir, "com.podcastmerlin.podcast_merlin_flutter.desktop", nullptr);
  gchar* desktop_path2 = g_build_filename(apps_dir, "podcast_merlin_flutter.desktop", nullptr);

  gchar* desktop_content = g_strdup_printf(
      "[Desktop Entry]\n"
      "Version=1.0\n"
      "Type=Application\n"
      "Name=Podcast Merlin\n"
      "GenericName=Podcast Client\n"
      "Comment=Nextcloud & gPodder Podcast Client\n"
      "Exec=%s %%U\n"
      "Icon=com.podcastmerlin.podcast_merlin_flutter\n"
      "Terminal=false\n"
      "Categories=AudioVideo;Audio;Player;\n"
      "StartupWMClass=%s\n",
      exe_path, APPLICATION_ID);

  g_file_set_contents(desktop_path1, desktop_content, -1, nullptr);

  gchar* desktop_content2 = g_strdup_printf(
      "[Desktop Entry]\n"
      "Version=1.0\n"
      "Type=Application\n"
      "Name=Podcast Merlin\n"
      "GenericName=Podcast Client\n"
      "Comment=Nextcloud & gPodder Podcast Client\n"
      "Exec=%s %%U\n"
      "Icon=podcast_merlin_flutter\n"
      "Terminal=false\n"
      "Categories=AudioVideo;Audio;Player;\n"
      "StartupWMClass=podcast_merlin_flutter\n",
      exe_path);

  g_file_set_contents(desktop_path2, desktop_content2, -1, nullptr);

  g_spawn_command_line_async(
      "sh -c 'update-desktop-database ~/.local/share/applications 2>/dev/null; "
      "kbuildsycoca6 --noincremental 2>/dev/null; "
      "gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>/dev/null'",
      nullptr);

  g_free(desktop_content);
  g_free(desktop_content2);
  g_free(desktop_path1);
  g_free(desktop_path2);
  g_free(apps_dir);
  g_free(pixmaps_dir);
  g_free(icons_hicolor_scalable);
  g_free(icons_hicolor_256);
  g_free(icons_hicolor_root);
  g_free(exe_dir_path);
  g_free(exe_path);
}

// Helper to set window icon using multiple standard sizes for Linux desktop environments
static void set_window_icon(GtkWindow* window) {
  // Ensure Wayland and desktop environment have registered icons and .desktop entries
  ensure_linux_desktop_integration();

  // Set default and window icon names for Wayland / XDG shell integration
  gtk_window_set_default_icon_name(APPLICATION_ID);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  // Append local assets directory to GtkIconTheme search path
  gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path);
    g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
    gchar* exe_dir_path = g_file_get_path(exe_dir);
    gchar* assets_images_dir = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", nullptr);
    if (g_file_test(assets_images_dir, G_FILE_TEST_IS_DIR)) {
      gtk_icon_theme_append_search_path(gtk_icon_theme_get_default(), assets_images_dir);
    }
    g_free(assets_images_dir);
    g_free(exe_dir_path);
    g_free(exe_path);
  }

  gchar* icon_path = nullptr;

  if (g_file_test("assets/images/logo.png", G_FILE_TEST_EXISTS)) {
    icon_path = g_strdup("assets/images/logo.png");
  } else {
    gchar* exe_path2 = g_file_read_link("/proc/self/exe", nullptr);
    if (exe_path2 != nullptr) {
      g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path2);
      g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
      gchar* exe_dir_path = g_file_get_path(exe_dir);
      icon_path = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", "logo.png", nullptr);
      g_free(exe_path2);
      g_free(exe_dir_path);
    }
  }

  if (icon_path != nullptr) {
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      const int sizes[] = {16, 32, 48, 64, 128, 256};
      GList* icon_list = nullptr;
      for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        g_autoptr(GError) error = nullptr;
        GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file_at_scale(
            icon_path, sizes[i], sizes[i], TRUE, &error);
        if (pixbuf != nullptr) {
          icon_list = g_list_append(icon_list, pixbuf);
        }
      }
      if (icon_list != nullptr) {
        gtk_window_set_icon_list(window, icon_list);
        gtk_window_set_default_icon_list(icon_list);
        g_list_free_full(icon_list, g_object_unref);
      }
    }
    g_free(icon_path);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  g_set_application_name("Podcast Merlin");
  g_set_prgname(APPLICATION_ID);

  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
    gtk_header_bar_set_title(header_bar, "Podcast Merlin");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Podcast Merlin");
  }

  // Set Linux taskbar and window icon
  set_window_icon(window);

  gtk_window_set_default_size(window, 1280, 720);

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
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("Podcast Merlin");

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
