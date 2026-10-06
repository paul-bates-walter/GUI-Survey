#ifndef PNG_TEXT_H
#define PNG_TEXT_H

#include <stdbool.h>

#define PNG_TEXT_KEY_MAX 80
#define PNG_TEXT_VALUE_MAX 256

typedef struct {
    char key[PNG_TEXT_KEY_MAX];
    char value[PNG_TEXT_VALUE_MAX];
} PngTextEntry;

int png_text_read(const char *path, PngTextEntry *entries, int max_entries);
bool png_text_write(const char *path, const PngTextEntry *entries, int count);

#endif
