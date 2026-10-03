#include "CAmid.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
// Both proc rusage and task-info CPU totals use Mach absolute-time ticks.
// Cache only the host timebase; never cache mutable process identity/permissions.
static pthread_once_t amid_timebase_once = PTHREAD_ONCE_INIT;
static mach_timebase_info_data_t amid_timebase;
static void amid_init_timebase(void) {
 if(mach_timebase_info(&amid_timebase)!=KERN_SUCCESS) amid_timebase.denom=0;
}
static int amid_cpu_nanoseconds(uint64_t user,uint64_t system,uint64_t *out) {
 pthread_once(&amid_timebase_once,amid_init_timebase);
 if(amid_timebase.denom==0) return 0;
 __uint128_t nanos=((__uint128_t)user+system)*amid_timebase.numer/amid_timebase.denom;
 if(nanos>UINT64_MAX) return 0;
 *out=(uint64_t)nanos; return 1;
}
int amid_boot(char *out,int capacity) { size_t n=capacity; return sysctlbyname("kern.bootsessionuuid",out,&n,NULL,0); }
int amid_pids(int32_t *pids,int capacity) { int n=proc_listallpids(pids,capacity*sizeof(int32_t)); return n; }
int amid_identity_matches(int32_t pid,uint32_t uid,uint64_t seconds,uint64_t micros) {
 struct proc_bsdinfo b;
 return proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&b,sizeof(b))==sizeof(b)&&b.pbi_uid==uid&&b.pbi_start_tvsec==seconds&&b.pbi_start_tvusec==micros;
}
int amid_process(int32_t pid,AmidProcess *out) {
 memset(out,0,sizeof(*out)); struct proc_bsdinfo b;
 if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&b,sizeof(b))!=sizeof(b)) return errno==EPERM||errno==EACCES?2:3;
 out->pid=pid; out->parent=b.pbi_ppid; out->uid=b.pbi_uid; out->seconds=b.pbi_start_tvsec; out->micros=b.pbi_start_tvusec;
 strlcpy(out->name,b.pbi_name[0]?b.pbi_name:b.pbi_comm,sizeof(out->name));
 proc_pidpath(pid,out->executable,sizeof(out->executable));
 struct rusage_info_v2 r;
 if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t *)&r)==0) { out->cpu_known=amid_cpu_nanoseconds(r.ri_user_time,r.ri_system_time,&out->cpu); out->memory=r.ri_phys_footprint; out->memory_method=1; }
 else { struct proc_taskinfo t; if(proc_pidinfo(pid,PROC_PIDTASKINFO,0,&t,sizeof(t))==sizeof(t)) { out->cpu_known=amid_cpu_nanoseconds(t.pti_total_user,t.pti_total_system,&out->cpu); out->memory=t.pti_resident_size; out->memory_method=2; } }
 struct proc_vnodepathinfo v;
 if(proc_pidinfo(pid,PROC_PIDVNODEPATHINFO,0,&v,sizeof(v))==sizeof(v)) { strlcpy(out->cwd,v.pvi_cdir.vip_path,sizeof(out->cwd)); out->cwd_status=1; }
 else out->cwd_status=errno==EPERM||errno==EACCES?2:3;
 // Reject metadata collected across PID reuse or exit.
 struct proc_bsdinfo check;
 if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&check,sizeof(check))!=sizeof(check)||check.pbi_start_tvsec!=b.pbi_start_tvsec||check.pbi_start_tvusec!=b.pbi_start_tvusec||check.pbi_uid!=b.pbi_uid) return 3;
 return 1;
}
int amid_ports(int32_t pid,AmidPort *ports,int capacity,int *status) {
 *status=1; errno=0; int size=proc_pidinfo(pid,PROC_PIDLISTFDS,0,NULL,0);
 if(size<=0 && errno!=0) { *status=errno==EPERM||errno==EACCES?2:3; return 0; }
 if(size==0) return 0;
 size+=32*sizeof(struct proc_fdinfo); struct proc_fdinfo *fds=malloc(size); if(!fds) { *status=3; return 0; }
 int bytes=proc_pidinfo(pid,PROC_PIDLISTFDS,0,fds,size); if(bytes<=0) { free(fds); *status=3; return 0; }
 int count=0; if(bytes==size) *status=3;
 for(int i=0;i<bytes/(int)sizeof(*fds);i++) if(fds[i].proc_fdtype==PROX_FDTYPE_SOCKET) {
 struct socket_fdinfo s; if(proc_pidfdinfo(pid,fds[i].proc_fd,PROC_PIDFDSOCKETINFO,&s,sizeof(s))!=sizeof(s)) { *status=2; continue; }
 if(s.psi.soi_kind!=SOCKINFO_TCP||s.psi.soi_proto.pri_tcp.tcpsi_state!=TSI_S_LISTEN) continue;
 if(count>=capacity) { *status=3; break; }
 struct in_sockinfo *in=&s.psi.soi_proto.pri_tcp.tcpsi_ini; AmidPort *p=&ports[count]; memset(p,0,sizeof(*p));
 p->family=s.psi.soi_family; p->port=ntohs((uint16_t)in->insi_lport);
 const void *addr=p->family==AF_INET?(const void *)&in->insi_laddr.ina_46.i46a_addr4:(const void *)&in->insi_laddr.ina_6;
 if((p->family==AF_INET||p->family==AF_INET6)&&inet_ntop(p->family,addr,p->address,sizeof(p->address))) count++;
 }
 free(fds); return count;
}
void amid_system(AmidSystem *out) {
 memset(out,0,sizeof(*out)); host_cpu_load_info_data_t c={0}; mach_msg_type_number_t n=HOST_CPU_LOAD_INFO_COUNT;
 mach_port_t host=mach_host_self();
 if(host_statistics(host,HOST_CPU_LOAD_INFO,(host_info_t)&c,&n)==KERN_SUCCESS&&n>=HOST_CPU_LOAD_INFO_COUNT) { out->cpu_known=1; out->user=c.cpu_ticks[CPU_STATE_USER]; out->system=c.cpu_ticks[CPU_STATE_SYSTEM]; out->idle=c.cpu_ticks[CPU_STATE_IDLE]; out->nice=c.cpu_ticks[CPU_STATE_NICE]; }
 vm_statistics64_data_t m={0}; n=HOST_VM_INFO64_COUNT; vm_size_t page=0;
 if(host_page_size(host,&page)==KERN_SUCCESS&&host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&m,&n)==KERN_SUCCESS&&(size_t)n*sizeof(integer_t)>=offsetof(vm_statistics64_data_t,compressor_page_count)+sizeof(m.compressor_page_count)) { out->memory_known=1; out->active=(uint64_t)m.active_count*page; out->inactive=(uint64_t)m.inactive_count*page; out->wired=(uint64_t)m.wire_count*page; out->compressed=(uint64_t)m.compressor_page_count*page; out->free=(uint64_t)m.free_count*page; }
 mach_port_deallocate(mach_task_self(),host);
 struct xsw_usage swap={0}; size_t size=sizeof(swap); if(sysctlbyname("vm.swapusage",&swap,&size,NULL,0)==0&&size>=offsetof(struct xsw_usage,xsu_used)+sizeof(swap.xsu_used)) { out->swap_known=1; out->swap=swap.xsu_used; }

}
int amid_interfaces(AmidInterface *out,int capacity) {
 struct ifaddrs *all; if(getifaddrs(&all)!=0) return -1; int count=0;
 for(struct ifaddrs *a=all;a&&count<capacity;a=a->ifa_next) if(a->ifa_addr&&a->ifa_addr->sa_family==AF_LINK&&a->ifa_data) { struct if_data *d=a->ifa_data; strlcpy(out[count].name,a->ifa_name,64); out[count].received=d->ifi_ibytes; out[count].sent=d->ifi_obytes; count++; }
 freeifaddrs(all); return count;
}

int amid_own_wakeups(uint64_t *interrupts,uint64_t *package_idle) {
 struct rusage_info_v0 usage;
 if(proc_pid_rusage(getpid(),RUSAGE_INFO_V0,(rusage_info_t *)&usage)!=0) return 0;
 *interrupts=usage.ri_interrupt_wkups; *package_idle=usage.ri_pkg_idle_wkups;
 return 1;
}
