// Owned, naturally bounded History verification workload. No sockets or signals.
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static double monotonic(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) { perror("monotonic clock"); exit(1); }
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

static void rest_until(double deadline) {
    for (;;) {
        double remaining = deadline - monotonic();
        if (remaining <= 0) return;
        struct timespec t = { .tv_sec = (time_t)remaining,
            .tv_nsec = (long)((remaining - (double)(time_t)remaining) * 1e9) };
        if (nanosleep(&t, NULL) != 0 && errno != EINTR) { perror("nanosleep"); exit(1); }
    }
}

static double cpu_seconds(const struct rusage *r) {
    return (double)r->ru_utime.tv_sec + (double)r->ru_utime.tv_usec / 1e6
        + (double)r->ru_stime.tv_sec + (double)r->ru_stime.tv_usec / 1e6;
}

static void record(const char *phase, double began, double previous_cpu, size_t mapped,
                   double *current_cpu) {
    struct timespec utc;
    struct rusage usage;
    if (clock_gettime(CLOCK_REALTIME, &utc) != 0 || getrusage(RUSAGE_SELF, &usage) != 0) {
        perror("own reference counters"); exit(1);
    }
    *current_cpu = cpu_seconds(&usage);
    if (*current_cpu < previous_cpu || usage.ru_maxrss < 0) {
        fputs("Invalid own reference counters\n", stderr); exit(1);
    }
    printf("{\"phase\":\"%s\",\"pid\":%d,\"uid\":%u,\"utcSeconds\":%.9f,"
           "\"elapsedSeconds\":%.6f,\"ownCPUSeconds\":%.6f,\"phaseCPUSeconds\":%.6f,"
           "\"mappedBytes\":%zu,\"lifetimePeakRSSBytes\":%ld}\n",
           phase, getpid(), (unsigned)getuid(), (double)utc.tv_sec + (double)utc.tv_nsec / 1e9,
           monotonic() - began, *current_cpu, *current_cpu - previous_cpu, mapped, usage.ru_maxrss);
    if (fflush(stdout) != 0 || ferror(stdout)) { perror("phase log"); exit(1); }
}

int main(void) {
    const size_t bytes = 64u * 1024u * 1024u;
    double began = monotonic(), cpu = 0, previous;
    record("baseline-start", began, 0, 0, &cpu);
    previous = cpu;
    rest_until(began + 60);
    record("baseline-complete", began, previous, 0, &cpu);
    unsigned char *memory = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                                 MAP_PRIVATE | MAP_ANON, -1, 0);
    if (memory == MAP_FAILED) { perror("64 MiB mmap"); return 1; }
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) { fputs("Page size unavailable\n", stderr); munmap(memory, bytes); return 1; }
    for (size_t offset = 0; offset < bytes; offset += (size_t)page) memory[offset] = 1;
    record("burst-start", began, cpu, bytes, &cpu);
    previous = cpu;
    volatile uint64_t accumulator = 1;
    while (monotonic() < began + 120) {
        for (unsigned i = 0; i < 10000; i++) accumulator = accumulator * 6364136223846793005ULL + 1;
    }
    record("burst-complete", began, previous, bytes, &cpu);
    if (munmap(memory, bytes) != 0) { perror("munmap"); return 1; }
    record("cooldown-start", began, cpu, 0, &cpu);
    previous = cpu;
    rest_until(began + 180);
    record("complete", began, previous, 0, &cpu);
    return 0;
}
