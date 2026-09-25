#define _GNU_SOURCE

#include <ctype.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define STATE_NAME "omaid-sudo-request"
#define SOCKET_NAME "omaid-face-auth.sock"
#define MAX_MESSAGE 512

static int valid_user(const char *value) {
    if (value == NULL || *value == '\0') {
        return 0;
    }

    for (const unsigned char *cursor = (const unsigned char *)value; *cursor != '\0'; cursor++) {
        if (!isalnum(*cursor) && *cursor != '_' && *cursor != '-' && *cursor != '.') {
            return 0;
        }
    }

    return 1;
}

static int runtime_path(char *buffer, size_t size, uid_t uid, const char *name) {
    if (snprintf(buffer, size, "/run/user/%lu/%s", (unsigned long)uid, name) >= (int)size) {
        return -1;
    }

    return 0;
}

static int drop_privileges(const char *user, uid_t uid, gid_t gid) {
    if (geteuid() != 0) {
        return geteuid() == uid ? 0 : -1;
    }

    if (uid == 0) {
        return 0;
    }

    if (initgroups(user, gid) != 0) {
        return -1;
    }

    if (setgid(gid) != 0) {
        return -1;
    }

    return setuid(uid) == 0 ? 0 : -1;
}

static int is_enrolled(const char *user) {
    pid_t child = fork();
    if (child < 0) {
        return 0;
    }

    if (child == 0) {
        int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDIN_FILENO);
            dup2(null_fd, STDOUT_FILENO);
            dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) {
                close(null_fd);
            }
        }

        execl("/usr/bin/facelock", "facelock", "is-enrolled", "--quiet", "--user", user, (char *)NULL);
        _exit(127);
    }

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        return 0;
    }

    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int send_event(uid_t uid, const char *event, const char *user, const char *request) {
    char socket_path[256];
    if (runtime_path(socket_path, sizeof(socket_path), uid, SOCKET_NAME) != 0) {
        return -1;
    }

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof(address.sun_path)) {
        return -1;
    }
    strcpy(address.sun_path, socket_path);

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        return -1;
    }

    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return -1;
    }

    char message[MAX_MESSAGE];
    int length = snprintf(
        message,
        sizeof(message),
        "{\"event\":\"%s\",\"service\":\"sudo\",\"user\":\"%s\",\"request\":\"%s\"}\n",
        event,
        user,
        request
    );

    if (length <= 0 || length >= (int)sizeof(message)) {
        close(fd);
        return -1;
    }

    ssize_t written = 0;
    while (written < length) {
        ssize_t result = write(fd, message + written, (size_t)(length - written));
        if (result <= 0) {
            close(fd);
            return -1;
        }
        written += result;
    }

    close(fd);
    return 0;
}

static int read_request(uid_t uid, char *buffer, size_t size) {
    char path[256];
    if (runtime_path(path, sizeof(path), uid, STATE_NAME) != 0) {
        return -1;
    }

    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return -1;
    }

    struct stat metadata;
    if (fstat(fd, &metadata) != 0 || !S_ISREG(metadata.st_mode)) {
        close(fd);
        return -1;
    }

    ssize_t length = read(fd, buffer, size - 1);
    close(fd);
    if (length <= 0) {
        return -1;
    }

    buffer[length] = '\0';
    while (length > 0 && (buffer[length - 1] == '\n' || buffer[length - 1] == '\r')) {
        buffer[--length] = '\0';
    }

    return 0;
}

static int write_request(uid_t uid, const char *request) {
    char path[256];
    if (runtime_path(path, sizeof(path), uid, STATE_NAME) != 0) {
        return -1;
    }

    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) {
        return -1;
    }

    size_t length = strlen(request);
    ssize_t written = write(fd, request, length);
    close(fd);
    return written == (ssize_t)length ? 0 : -1;
}

static void remove_request(uid_t uid) {
    char path[256];
    if (runtime_path(path, sizeof(path), uid, STATE_NAME) == 0) {
        unlink(path);
    }
}

static void make_request(uid_t uid, char *buffer, size_t size) {
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) {
        now.tv_sec = 0;
        now.tv_nsec = 0;
    }

    snprintf(buffer, size, "%ld-%ld-%lu", (long)now.tv_sec, (long)now.tv_nsec, (unsigned long)uid);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        return 0;
    }

    const char *event = argv[1];
    if (strcmp(event, "begin") != 0 && strcmp(event, "fallback") != 0 && strcmp(event, "end") != 0) {
        return 0;
    }

    const char *service = getenv("PAM_SERVICE");
    const char *user_name = getenv("PAM_USER");
    if (service == NULL || strcmp(service, "sudo") != 0 || !valid_user(user_name)) {
        return 0;
    }

    struct passwd *account = getpwnam(user_name);
    if (account == NULL) {
        return 0;
    }

    uid_t uid = account->pw_uid;
    gid_t gid = account->pw_gid;

    if (strcmp(event, "begin") == 0) {
        if (access("/usr/lib/security/pam_facelock.so", R_OK) != 0) {
            return 0;
        }

        if (drop_privileges(user_name, uid, gid) != 0 || !is_enrolled(user_name)) {
            return 0;
        }

        char request[96];
        make_request(uid, request, sizeof(request));
        if (send_event(uid, event, user_name, request) == 0) {
            write_request(uid, request);
        }
        return 0;
    }

    char request[96];
    if (read_request(uid, request, sizeof(request)) != 0) {
        return 0;
    }

    if (drop_privileges(user_name, uid, gid) != 0) {
        return 0;
    }

    send_event(uid, event, user_name, request);
    if (strcmp(event, "end") == 0) {
        remove_request(uid);
    }

    return 0;
}
