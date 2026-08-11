#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] :
        "/sys/bus/pci/devices/0000:01:00.0/resource0";
    const uint32_t expected = 0xa5c37e19u;
    const size_t map_len = 4096;
    int fd = open(path, O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return 2;
    }
    volatile uint32_t *bar = mmap(NULL, map_len, PROT_READ | PROT_WRITE,
                                  MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) {
        fprintf(stderr, "mmap %s: %s\n", path, strerror(errno));
        close(fd);
        return 2;
    }

    uint32_t signature = bar[0];
    uint32_t version = bar[1];
    uint32_t link_state = bar[2];
    uint32_t before = bar[0x40 / sizeof(uint32_t)];
    bar[0x40 / sizeof(uint32_t)] = expected;
    uint32_t scratch = bar[0x40 / sizeof(uint32_t)];
    uint32_t bar_ur = bar[0x30 / sizeof(uint32_t)];
    uint32_t bar_ca = bar[0x34 / sizeof(uint32_t)];
    uint32_t bar_axi_error = bar[0x38 / sizeof(uint32_t)];
    printf("BAR_MMAP signature=%08x version=%08x link=%08x before=%08x "
           "scratch=%08x ur=%08x ca=%08x axi=%08x\n",
           signature, version, link_state, before, scratch,
           bar_ur, bar_ca, bar_axi_error);

    munmap((void *)bar, map_len);
    close(fd);
    if (signature != 0x50434945u || version != 0x00010000u ||
        scratch != expected) {
        fprintf(stderr, "BAR_MMAP_FAIL\n");
        return 1;
    }
    puts("BAR_MMAP_PASS");
    return 0;
}
