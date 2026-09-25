#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define AUTH_BINARY "/usr/bin/facelock"
#define CONFIG_FILE "/etc/facelock/config.toml"
#define IO_TIMEOUT_MS 2000
#define AUTH_TIMEOUT_SECS 15
#define REQUEST_CAPACITY 256
#define ID_CAPACITY 64
#define LISTEN_FDS_START 3
#define LISTEN_FDS_MAX 64

static volatile sig_atomic_t stop_requested = 0;

static void handle_signal(int signal_number) {
    (void)signal_number;
    stop_requested = 1;
}

static bool valid_request_id(const char *id) {
    size_t length = strlen(id);
    if (length == 0 || length >= ID_CAPACITY) return false;

    for (size_t index = 0; index < length; index++) {
        unsigned char character = (unsigned char)id[index];
        if (!isalnum(character) && character != '-' && character != '_' && character != '.') {
            return false;
        }
    }

    return true;
}

static int receive_request(int client, char *buffer, size_t capacity) {
    size_t used = 0;
    struct timespec started;
    clock_gettime(CLOCK_MONOTONIC, &started);

    while (used + 1 < capacity) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long elapsed = (now.tv_sec - started.tv_sec) * 1000L + (now.tv_nsec - started.tv_nsec) / 1000000L;
        if (elapsed >= IO_TIMEOUT_MS) return -1;

        struct pollfd descriptor = {
            .fd = client,
            .events = POLLIN,
            .revents = 0,
        };
        int poll_result = poll(&descriptor, 1, IO_TIMEOUT_MS - (int)elapsed);
        if (poll_result < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (poll_result == 0) return -1;
        if ((descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0 && used == 0) return -1;

        ssize_t received = recv(client, buffer + used, capacity - used - 1, 0);
        if (received > 0) {
            used += (size_t)received;
            buffer[used] = '\0';
            if (memchr(buffer, '\n', used) != NULL) return (int)used;
            continue;
        }
        if (received == 0) return -1;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
        return -1;
    }

    return -1;
}

static bool parse_request(char *buffer, char request_id[ID_CAPACITY]) {
    char *newline = strchr(buffer, '\n');
    if (newline == NULL) return false;
    *newline = '\0';

    size_t length = strlen(buffer);
    if (length > 0 && buffer[length - 1] == '\r') buffer[length - 1] = '\0';
    if (strncmp(buffer, "AUTH ", 5) != 0) return false;

    char *id = buffer + 5;
    if (!valid_request_id(id)) return false;
    if (id[0] == '\0') return false;

    size_t id_length = strlen(id);
    if (id_length >= ID_CAPACITY) return false;
    memcpy(request_id, id, id_length + 1);
    return true;
}

static bool send_all(int client, const char *data, size_t length) {
    size_t sent = 0;

    while (sent < length) {
        ssize_t result = send(client, data + sent, length - sent, MSG_NOSIGNAL);
        if (result > 0) {
            sent += (size_t)result;
            continue;
        }
        if (result < 0 && (errno == EINTR)) continue;
        if (result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd descriptor = {
                .fd = client,
                .events = POLLOUT,
                .revents = 0,
            };
            if (poll(&descriptor, 1, 1000) > 0) continue;
        }
        return false;
    }

    return true;
}

static bool send_result(int client, const char *request_id, const char *result) {
    char response[REQUEST_CAPACITY];
    int length = snprintf(response, sizeof(response), "%s %s\n", result, request_id);
    if (length < 0 || (size_t)length >= sizeof(response)) return false;
    return send_all(client, response, (size_t)length);
}

static pid_t spawn_authentication(const char *user) {
    pid_t child = fork();
    if (child < 0) return -1;

    if (child == 0) {
        prctl(PR_SET_PDEATHSIG, SIGTERM);
        if (getppid() == 1) _exit(127);

        int null_device = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_device < 0) _exit(127);
        dup2(null_device, STDIN_FILENO);
        dup2(null_device, STDOUT_FILENO);
        dup2(null_device, STDERR_FILENO);
        if (null_device > STDERR_FILENO) close(null_device);

        char *arguments[] = {
            (char *)AUTH_BINARY,
            (char *)"auth",
            (char *)"--user",
            (char *)user,
            (char *)"--config",
            (char *)CONFIG_FILE,
            NULL,
        };
        char *environment[] = {
            (char *)"PATH=/usr/bin:/bin",
            (char *)"HOME=/root",
            (char *)"USER=root",
            (char *)"LOGNAME=root",
            NULL,
        };
        execve(AUTH_BINARY, arguments, environment);
        _exit(127);
    }

    return child;
}

static int terminate_child(pid_t child) {
    if (child <= 0) return -1;
    if (kill(child, SIGTERM) < 0 && errno != ESRCH) return -1;

    for (int attempt = 0; attempt < 20; attempt++) {
        int status;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) return status;
        if (result < 0) return -1;
        struct timespec delay = {.tv_sec = 0, .tv_nsec = 50000000L};
        nanosleep(&delay, NULL);
    }

    if (kill(child, SIGKILL) < 0 && errno != ESRCH) return -1;
    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    return status;
}

static int wait_for_authentication(pid_t child, int client) {
    time_t deadline = time(NULL) + AUTH_TIMEOUT_SECS;

    for (;;) {
        int status;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) return status;
        if (result < 0) return -1;

        struct pollfd descriptor = {
            .fd = client,
            .events = POLLIN,
            .revents = 0,
        };
        int poll_result = poll(&descriptor, 1, 50);
        if (poll_result > 0 && (descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
            terminate_child(child);
            return -1;
        }
        if (poll_result < 0 && errno != EINTR) {
            terminate_child(child);
            return -1;
        }

        if (time(NULL) >= deadline) {
            terminate_child(child);
            return -1;
        }
    }
}

static const char *result_for_status(int status) {
    if (status < 0) return "ERROR";
    if (!WIFEXITED(status)) return "ERROR";
    int exit_code = WEXITSTATUS(status);
    if (exit_code == 0) return "SUCCESS";
    if (exit_code == 1) return "FAIL";
    return "ERROR";
}

static int create_listener(const char *path) {
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listener < 0) return -1;

    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof(address.sun_path)) {
        close(listener);
        return -1;
    }
    strcpy(address.sun_path, path);
    unlink(path);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(listener, 8) < 0) {
        close(listener);
        return -1;
    }
    chmod(path, 0600);
    return listener;
}

static int activated_listener(void) {
    for (int descriptor = LISTEN_FDS_START; descriptor < LISTEN_FDS_START + LISTEN_FDS_MAX; descriptor++) {
        int value = 0;
        socklen_t length = sizeof(value);
        if (getsockopt(descriptor, SOL_SOCKET, SO_ACCEPTCONN, &value, &length) < 0) continue;
        if (value == 1) return descriptor;
    }
    return -1;
}

static bool peer_is_allowed(int client, uid_t user_id) {
    struct ucred credentials;
    socklen_t length = sizeof(credentials);
    if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credentials, &length) < 0) return false;
    return credentials.uid == user_id;
}

static void serve_client(int client, uid_t user_id, const char *user) {
    if (!peer_is_allowed(client, user_id)) return;

    char buffer[REQUEST_CAPACITY];
    if (receive_request(client, buffer, sizeof(buffer)) < 0) return;

    char request_id[ID_CAPACITY];
    if (!parse_request(buffer, request_id)) return;

    pid_t child = spawn_authentication(user);
    if (child < 0) {
        send_result(client, request_id, "ERROR");
        return;
    }

    int status = wait_for_authentication(child, client);
    if (status >= 0) send_result(client, request_id, result_for_status(status));
}

static int parse_arguments(int argc, char **argv, const char **user, const char **socket_path) {
    *user = NULL;
    *socket_path = NULL;

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--user") == 0 && index + 1 < argc) {
            *user = argv[++index];
        } else if (strcmp(argv[index], "--socket") == 0 && index + 1 < argc) {
            *socket_path = argv[++index];
        } else {
            return -1;
        }
    }

    if (*user == NULL || **user == '\0') return -1;
    struct passwd *account = getpwnam(*user);
    if (account == NULL || account->pw_uid == 0) return -1;
    return (int)account->pw_uid;
}

int main(int argc, char **argv) {
    const char *user;
    const char *socket_path;
    int user_id = parse_arguments(argc, argv, &user, &socket_path);
    if (user_id < 0) return 2;

    struct sigaction action = {
        .sa_handler = handle_signal,
        .sa_flags = 0,
    };
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);

    int listener = socket_path == NULL ? activated_listener() : create_listener(socket_path);
    if (listener < 0) return 1;

    while (!stop_requested) {
        int client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        serve_client(client, (uid_t)user_id, user);
        close(client);
    }

    if (socket_path != NULL) unlink(socket_path);
    close(listener);
    return 0;
}
