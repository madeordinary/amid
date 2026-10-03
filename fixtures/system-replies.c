/* Deterministic injected replies; no host/process metadata is collected. */
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

static kern_return_t cpu_result, vm_result, page_result;
static int swap_result;
static mach_msg_type_number_t cpu_count, vm_count;
static size_t swap_size;
static int zero_values, failures, deallocations;
static kern_return_t owned_host_statistics(host_t host, host_flavor_t flavor, host_info_t info, mach_msg_type_number_t *count) {
 (void)host; assert(flavor == HOST_CPU_LOAD_INFO);
 host_cpu_load_info_data_t value = {{0}};
 if(!zero_values) for(int i=0;i<CPU_STATE_MAX;i++) value.cpu_ticks[i]=77;
 memcpy(info,&value,sizeof(value)); *count=cpu_count; return cpu_result;
}
static kern_return_t owned_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) {
 (void)host; assert(flavor == HOST_VM_INFO64);
 vm_statistics64_data_t value = {0};
 if(!zero_values) { value.active_count=2; value.inactive_count=3; value.wire_count=4; value.compressor_page_count=5; value.free_count=6; }
 memcpy(info,&value,sizeof(value)); *count=vm_count; return vm_result;
}
static kern_return_t owned_host_page_size(host_t host, vm_size_t *page) { (void)host; *page=4096; return page_result; }
static int owned_sysctlbyname(const char *name, void *out, size_t *size, void *new_value, size_t new_size) {
 assert(strcmp(name,"vm.swapusage")==0); assert(new_value==NULL && new_size==0);
 struct xsw_usage value = {0}; value.xsu_used=zero_values ? 0 : 123;
 memcpy(out,&value,sizeof(value)); *size=swap_size; if(swap_result) errno=EIO; return swap_result;
}
static mach_port_t owned_host_self(void) { return 123; }
static mach_port_t owned_task_self(void) { return 456; }
static kern_return_t owned_deallocate(ipc_space_t task, mach_port_name_t port) {
 assert(task==456 && port==123); deallocations++; return KERN_SUCCESS;
}
/* Include SDK declarations above, then redirect only implementation call sites. */
#define host_statistics owned_host_statistics
#define host_statistics64 owned_host_statistics64
#define host_page_size owned_host_page_size
#define sysctlbyname owned_sysctlbyname
#define mach_host_self owned_host_self
#undef mach_task_self
#define mach_task_self owned_task_self
#define mach_port_deallocate owned_deallocate
#include "../Sources/CAmid/collectors.c"

static void defaults(void) {
 cpu_result=vm_result=page_result=KERN_SUCCESS; swap_result=0;
 cpu_count=HOST_CPU_LOAD_INFO_COUNT; vm_count=HOST_VM_INFO64_COUNT;
 swap_size=sizeof(struct xsw_usage); zero_values=0;
}
static void check(const char *name, int cpu, int memory, int swap) {
 AmidSystem value; amid_system(&value);
 if(value.cpu_known!=cpu || value.memory_known!=memory || value.swap_known!=swap ||
    (!cpu && (value.user || value.system || value.idle || value.nice)) ||
    (!memory && (value.active || value.inactive || value.wired || value.compressed || value.free)) ||
    (!swap && value.swap)) { fprintf(stderr,"FAIL %s known=%d/%d/%d\n",name,value.cpu_known,value.memory_known,value.swap_known); failures++; }
 if(cpu && value.user!=(zero_values ? 0 : 77)) failures++;
 if(memory && value.compressed!=(zero_values ? 0 : 5*4096)) failures++;
 if(swap && value.swap!=(zero_values ? 0 : 123)) failures++;
}
int main(void) {
 const mach_msg_type_number_t needed_vm=(mach_msg_type_number_t)((offsetof(vm_statistics64_data_t,compressor_page_count)+sizeof(((vm_statistics64_data_t *)0)->compressor_page_count)+sizeof(integer_t)-1)/sizeof(integer_t));
 const size_t needed_swap=offsetof(struct xsw_usage,xsu_used)+sizeof(((struct xsw_usage *)0)->xsu_used);
 defaults(); check("full",1,1,1);
 defaults(); cpu_count=HOST_CPU_LOAD_INFO_COUNT-1; check("short CPU",0,1,1);
 defaults(); vm_count=needed_vm-1; check("short VM",1,0,1);
 defaults(); swap_size=needed_swap-1; check("short swap",1,1,0);
 defaults(); vm_count=needed_vm; check("minimum valid older VM",1,1,1);
 defaults(); swap_size=needed_swap; check("minimum valid swap",1,1,1);
 defaults(); cpu_result=vm_result=KERN_FAILURE; swap_result=-1; check("failed APIs",0,0,0);
 defaults(); page_result=KERN_FAILURE; check("failed page size",1,0,1);
 defaults(); zero_values=1; check("legitimate zero",1,1,1);
 assert(deallocations==9);
 if(failures) return 1;
 puts("PASS 9 injected system-reply cases; no host metadata collection"); return 0;
}
