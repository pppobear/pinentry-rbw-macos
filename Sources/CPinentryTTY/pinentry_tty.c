#include "pinentry_tty.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/select.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t caught_signal = 0;
static int signal_pipe_read_descriptor = -1;
static volatile sig_atomic_t signal_pipe_write_descriptor = -1;

static const int handled_signals[] = {
    SIGALRM,
    SIGHUP,
    SIGINT,
    SIGPIPE,
    SIGQUIT,
    SIGTERM,
    SIGTSTP,
    SIGTTIN,
    SIGTTOU,
};

static void record_signal(int signal_number) {
    int saved_errno = errno;
    if (caught_signal == 0) {
        caught_signal = signal_number;
    }
    int descriptor = signal_pipe_write_descriptor;
    if (descriptor >= 0) {
        unsigned char byte = (unsigned char)signal_number;
        (void)write(descriptor, &byte, 1);
    }
    errno = saved_errno;
}

static int ensure_signal_pipe(void) {
    if (signal_pipe_read_descriptor >= 0 && signal_pipe_write_descriptor >= 0) {
        return 0;
    }
    int descriptors[2];
    if (pipe(descriptors) != 0) {
        return -1;
    }
    for (size_t index = 0; index < 2; index++) {
        if (fcntl(descriptors[index], F_SETFD, FD_CLOEXEC) != 0
            || fcntl(descriptors[index], F_SETFL, O_NONBLOCK) != 0) {
            int saved_errno = errno;
            close(descriptors[0]);
            close(descriptors[1]);
            errno = saved_errno;
            return -1;
        }
    }
    signal_pipe_read_descriptor = descriptors[0];
    signal_pipe_write_descriptor = descriptors[1];
    return 0;
}

static void drain_signal_pipe(void) {
    int saved_errno = errno;
    unsigned char bytes[32];
    while (read(signal_pipe_read_descriptor, bytes, sizeof(bytes)) > 0) {
    }
    errno = saved_errno;
}

static int write_all(int descriptor, const char *bytes, size_t count) {
    size_t offset = 0;
    while (offset < count) {
        ssize_t written = write(descriptor, bytes + offset, count - offset);
        if (written > 0) {
            offset += (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR && caught_signal == 0) {
            continue;
        }
        return -1;
    }
    return 0;
}

static int remaining_timeout(
    const struct timespec *deadline,
    struct timespec *remaining
) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return -1;
    }
    if (now.tv_sec > deadline->tv_sec
        || (now.tv_sec == deadline->tv_sec && now.tv_nsec >= deadline->tv_nsec)) {
        return 0;
    }
    remaining->tv_sec = deadline->tv_sec - now.tv_sec;
    remaining->tv_nsec = deadline->tv_nsec - now.tv_nsec;
    if (remaining->tv_nsec < 0) {
        remaining->tv_sec--;
        remaining->tv_nsec += 1000000000L;
    }
    return 1;
}

int pinentry_read_secret(
    int descriptor,
    const char *prompt,
    char *buffer,
    size_t buffer_size,
    uint32_t timeout_seconds,
    int *error_number
) {
    const size_t signal_count = sizeof(handled_signals) / sizeof(handled_signals[0]);
    struct sigaction previous_actions[sizeof(handled_signals) / sizeof(handled_signals[0])];
    struct sigaction action;
    struct termios original_termios;
    struct termios hidden_termios;
    sigset_t handled_set;
    sigset_t original_mask;
    sigset_t active_mask;
    struct timespec deadline;
    size_t installed_actions = 0;
    size_t length = 0;
    int terminal_changed = 0;
    int status = PINENTRY_TTY_ERROR;
    int saved_errno = 0;
    int signal_to_forward = 0;
    int input_too_long = 0;
    int has_deadline = 0;

    if (error_number != NULL) {
        *error_number = 0;
    }
    if (descriptor < 0 || prompt == NULL || buffer == NULL || buffer_size < 2) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return PINENTRY_TTY_ERROR;
    }
    if (ensure_signal_pipe() != 0) {
        if (error_number != NULL) {
            *error_number = errno == 0 ? EIO : errno;
        }
        return PINENTRY_TTY_ERROR;
    }
    if (descriptor >= FD_SETSIZE || signal_pipe_read_descriptor >= FD_SETSIZE) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return PINENTRY_TTY_ERROR;
    }
    drain_signal_pipe();
    buffer[0] = '\0';
    caught_signal = 0;

    sigemptyset(&handled_set);
    for (size_t index = 0; index < signal_count; index++) {
        sigaddset(&handled_set, handled_signals[index]);
    }
    if (sigprocmask(SIG_BLOCK, &handled_set, &original_mask) != 0) {
        saved_errno = errno;
        goto cleanup_without_mask;
    }

    memset(&action, 0, sizeof(action));
    action.sa_handler = record_signal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    for (size_t index = 0; index < signal_count; index++) {
        if (sigaction(handled_signals[index], &action, &previous_actions[index]) != 0) {
            saved_errno = errno;
            goto cleanup;
        }
        installed_actions++;
    }

    if (tcgetattr(descriptor, &original_termios) != 0) {
        saved_errno = errno;
        goto cleanup;
    }
    hidden_termios = original_termios;
    hidden_termios.c_lflag &= (tcflag_t)~(ECHO | ECHONL);
    if (tcsetattr(descriptor, TCSAFLUSH, &hidden_termios) != 0) {
        saved_errno = errno;
        goto cleanup;
    }
    terminal_changed = 1;

    active_mask = original_mask;
    for (size_t index = 0; index < signal_count; index++) {
        sigdelset(&active_mask, handled_signals[index]);
    }
    if (timeout_seconds > 0) {
        if (clock_gettime(CLOCK_MONOTONIC, &deadline) != 0) {
            saved_errno = errno;
            goto cleanup;
        }
        deadline.tv_sec += timeout_seconds;
        has_deadline = 1;
    }

    if (write_all(descriptor, prompt, strlen(prompt)) != 0) {
        saved_errno = errno;
        status = PINENTRY_TTY_ERROR;
        goto cleanup;
    }

    for (;;) {
        fd_set read_set;
        struct timespec remaining;
        struct timespec *timeout = NULL;
        if (has_deadline) {
            int remaining_status = remaining_timeout(&deadline, &remaining);
            if (remaining_status < 0) {
                saved_errno = errno;
                status = PINENTRY_TTY_ERROR;
                break;
            }
            if (remaining_status == 0) {
                status = PINENTRY_TTY_TIMED_OUT;
                break;
            }
            timeout = &remaining;
        }

        FD_ZERO(&read_set);
        FD_SET(descriptor, &read_set);
        FD_SET(signal_pipe_read_descriptor, &read_set);
        int max_descriptor = descriptor > signal_pipe_read_descriptor
            ? descriptor
            : signal_pipe_read_descriptor;
        int ready = pselect(max_descriptor + 1, &read_set, NULL, NULL, timeout, &active_mask);
        if (ready == 0) {
            status = PINENTRY_TTY_TIMED_OUT;
            break;
        }
        if (ready < 0) {
            if (errno == EINTR && caught_signal != 0) {
                goto classify_signal;
            }
            if (errno == EINTR) {
                continue;
            }
            saved_errno = errno;
            status = PINENTRY_TTY_ERROR;
            break;
        }
        if (FD_ISSET(signal_pipe_read_descriptor, &read_set)) {
            drain_signal_pipe();
            if (caught_signal != 0) {
                goto classify_signal;
            }
            continue;
        }

        unsigned char byte = 0;
        ssize_t count = read(descriptor, &byte, 1);
        if (count == 1) {
            if (byte == '\n' || byte == '\r') {
                if (input_too_long) {
                    saved_errno = EMSGSIZE;
                    status = PINENTRY_TTY_ERROR;
                } else if (length == 0) {
                    status = PINENTRY_TTY_CANCELLED;
                } else {
                    buffer[length] = '\0';
                    status = PINENTRY_TTY_SUCCESS;
                }
                break;
            }
            if (byte == '\0') {
                saved_errno = EILSEQ;
                status = PINENTRY_TTY_ERROR;
                break;
            }
            if (length + 1 < buffer_size) {
                buffer[length++] = (char)byte;
            } else {
                input_too_long = 1;
            }
            continue;
        }
        if (count == 0) {
            status = PINENTRY_TTY_CANCELLED;
            break;
        }
        if (errno == EINTR) {
            if (caught_signal != 0) {
                goto classify_signal;
            }
            continue;
        }
        saved_errno = errno;
        status = PINENTRY_TTY_ERROR;
        break;
    }
    goto cleanup;

classify_signal:
    if (caught_signal == SIGINT) {
        status = PINENTRY_TTY_CANCELLED;
    } else if (caught_signal != 0) {
        signal_to_forward = caught_signal;
        status = PINENTRY_TTY_INTERRUPTED;
    } else {
        status = PINENTRY_TTY_ERROR;
        if (saved_errno == 0) {
            saved_errno = EINTR;
        }
    }

cleanup:
    (void)sigprocmask(SIG_BLOCK, &handled_set, NULL);
    if (terminal_changed) {
        if (tcsetattr(descriptor, TCSAFLUSH, &original_termios) != 0 && status == PINENTRY_TTY_SUCCESS) {
            saved_errno = errno;
            status = PINENTRY_TTY_ERROR;
        }
        (void)write_all(descriptor, "\n", 1);
    }
    while (installed_actions > 0) {
        installed_actions--;
        (void)sigaction(
            handled_signals[installed_actions],
            &previous_actions[installed_actions],
            NULL
        );
    }
    if (caught_signal == SIGINT) {
        status = PINENTRY_TTY_CANCELLED;
    } else if (caught_signal != 0 && signal_to_forward == 0) {
        signal_to_forward = caught_signal;
        status = PINENTRY_TTY_INTERRUPTED;
    }
    (void)sigprocmask(SIG_SETMASK, &original_mask, NULL);
    if (signal_to_forward != 0) {
        (void)raise(signal_to_forward);
    }

cleanup_without_mask:
    if (status == PINENTRY_TTY_ERROR && saved_errno == 0) {
        saved_errno = errno == 0 ? EIO : errno;
    }
    if (error_number != NULL) {
        *error_number = saved_errno;
    }
    return status;
}
