#ifndef GUI_SURVEY_NATIVE_DIALOG_H
  #define GUI_SURVEY_NATIVE_DIALOG_H
  #include <stdbool.h>
  #include <stddef.h>

  bool dialog_open_png(char *buffer, size_t buffer_size);
  bool dialog_save_png(char *buffer, size_t buffer_size);
#endif
