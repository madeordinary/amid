#ifndef CAMID_H
#define CAMID_H
#include <stdint.h>
#define AMID_PATH 4096
typedef struct { int32_t pid,parent; uint32_t uid; uint64_t seconds,micros,cpu,memory; int cpu_known,memory_method,cwd_status; char executable[AMID_PATH],name[256],cwd[AMID_PATH]; } AmidProcess;
typedef struct { uint16_t port; int family; char address[64]; } AmidPort;
typedef struct { uint64_t user,system,idle,nice,active,inactive,wired,compressed,free,swap; int cpu_known,memory_known,swap_known,pressure; } AmidSystem;
typedef struct { char name[64]; uint64_t received,sent; } AmidInterface;
int amid_pids(int32_t *pids,int capacity);
int amid_process(int32_t pid,AmidProcess *out);
int amid_identity_matches(int32_t pid,uint32_t uid,uint64_t seconds,uint64_t micros);
int amid_ports(int32_t pid,AmidPort *ports,int capacity,int *status);
void amid_system(AmidSystem *out);
int amid_interfaces(AmidInterface *out,int capacity);
int amid_own_wakeups(uint64_t *interrupts,uint64_t *package_idle);
int amid_boot(char *out,int capacity);
#endif
