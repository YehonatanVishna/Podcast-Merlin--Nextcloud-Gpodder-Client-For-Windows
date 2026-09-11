#include "my_application.h"

int main(int argc, char** argv) {
#ifdef APPLICATION_ID
  g_set_prgname(APPLICATION_ID);
#endif
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
