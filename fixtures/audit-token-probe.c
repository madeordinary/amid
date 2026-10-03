// Read-only feasibility probe. Called only with an owned fixture PID by its runner.
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <libproc.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
int main(int argc, char **argv) {
    if (argc != 2 && argc != 3) return 2;
    int pid = atoi(argv[1]);
    if (pid <= 0) return 2;
    mach_port_name_t name = MACH_PORT_NULL;
    kern_return_t acquired = task_name_for_pid(mach_task_self(), pid, &name);
    audit_token_t token = {0};
    mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;
    kern_return_t read = acquired == KERN_SUCCESS ? task_info(name, TASK_AUDIT_TOKEN, (task_info_t)&token, &count) : acquired;
    struct proc_bsdinfo info = {0};
    int owned = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) && info.pbi_ppid == getppid() && info.pbi_uid == getuid();
    int delayed = argc == 3 && strcmp(argv[2], "--after-exit") == 0 && owned && read == KERN_SUCCESS;
    int term = argc == 3 && strcmp(argv[2], "--owned-term") == 0 && owned && read == KERN_SUCCESS;
    if (delayed) sleep(9);
    int checked = read == KERN_SUCCESS ? proc_signal_with_audittoken(&token, (term || delayed) ? SIGTERM : 0) : -1;
    int check_errno = checked == -1 ? errno : 0;
    printf("{\"taskNameResult\":%d,\"auditTokenResult\":%d,\"tokenCount\":%u,\"signalAPIResult\":%d,\"signalAPIErrno\":%d}\n", acquired, read, count, checked, check_errno);
    if (name != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), name);
    return 0;
}
