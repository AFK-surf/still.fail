// The iOS SDK has getentropy in libSystem but no <sys/random.h>.
#pragma once
#include <stddef.h>
int getentropy(void *buf, size_t len);
