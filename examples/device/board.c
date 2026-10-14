/* The GPIO line of device.goose, through the kernel's GPIO character device
   (uAPI v2, Linux 5.10+), which needs an ioctl that Goose can't make. The line
   is requested once, before the workers start, and every worker then sets and
   reads it through the descriptor kept here.

   Without a line, and on platforms other than Linux, the line is simulated: a
   value kept here, so the example runs anywhere. Every function returns 0 or
   a value on success and -errno on failure. */
#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

#ifdef __linux__
#include <fcntl.h>
#include <linux/gpio.h>
#include <sys/ioctl.h>
#include <unistd.h>
#endif

/* A Goose const u8[:]: data isn't NUL-terminated. Packed as Goose packs it:
   12 bytes on a 32-bit target and 16 on a 64-bit one. */
#pragma pack(push, 1)
typedef struct {
    const uint8_t *data;
    int64_t len;
} board_bytes;
#pragma pack(pop)
_Static_assert(sizeof(board_bytes) == sizeof(void *) + 8, "board_bytes is not packed");

static int line_fd = -1;
static _Atomic int simulated;

int32_t board_gpio_open(board_bytes chip, int32_t line) {
#ifdef __linux__
    char path[256];
    if (chip.len <= 0 || chip.len >= (int64_t)sizeof path || line < 0) return -EINVAL;
    memcpy(path, chip.data, (size_t)chip.len);
    path[chip.len] = 0;
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) return -errno;
    struct gpio_v2_line_request req;
    memset(&req, 0, sizeof req);
    req.offsets[0] = (uint32_t)line;
    req.num_lines = 1;
    req.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
    strncpy(req.consumer, "goose-http", sizeof req.consumer - 1);
    int r = ioctl(fd, GPIO_V2_GET_LINE_IOCTL, &req);
    int err = errno;
    close(fd);
    if (r < 0) return -err;
    line_fd = req.fd;
    return 0;
#else
    (void)chip;
    (void)line;
    return -ENOSYS;
#endif
}

uint8_t board_gpio_simulated(void) { return line_fd < 0; }

int32_t board_gpio_set(uint8_t on) {
#ifdef __linux__
    if (line_fd >= 0) {
        struct gpio_v2_line_values v = { .bits = on ? 1 : 0, .mask = 1 };
        return ioctl(line_fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &v) < 0 ? -errno : 0;
    }
#endif
    atomic_store(&simulated, on ? 1 : 0);
    return 0;
}

int32_t board_gpio_get(void) {
#ifdef __linux__
    if (line_fd >= 0) {
        struct gpio_v2_line_values v = { .bits = 0, .mask = 1 };
        if (ioctl(line_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &v) < 0) return -errno;
        return (int32_t)(v.bits & 1);
    }
#endif
    return atomic_load(&simulated);
}
