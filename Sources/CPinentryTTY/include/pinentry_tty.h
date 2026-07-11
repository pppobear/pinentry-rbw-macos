#ifndef PINENTRY_TTY_H
#define PINENTRY_TTY_H

#include <stddef.h>
#include <stdint.h>

enum {
    PINENTRY_TTY_SUCCESS = 0,
    PINENTRY_TTY_CANCELLED = 1,
    PINENTRY_TTY_TIMED_OUT = 2,
    PINENTRY_TTY_INTERRUPTED = 3,
    PINENTRY_TTY_ERROR = 4,
};

// Reads one line from an already-open TTY while suppressing echo. The function
// restores terminal settings before returning or forwarding a terminating or
// stop signal. timeout_seconds == 0 disables the timeout.
int pinentry_read_secret(
    int descriptor,
    const char *prompt,
    char *buffer,
    size_t buffer_size,
    uint32_t timeout_seconds,
    int *error_number
);

#endif
