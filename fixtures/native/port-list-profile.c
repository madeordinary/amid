// Test-only owned-PID comparison. No process scan, connections, or payload inspection.
#include "CAmid.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct Counters { unsigned list, socket, allocations, frees; };
static struct Counters counters;
struct Reply { int bytes, error; };
static struct Reply replies[8];
static int mock, replyCount, replyIndex, mockSockets, socketFailure, allocationFailure;
static void check(int condition, const char *label) {
 if(!condition) { fprintf(stderr,"Owned-port fixture failed: %s\n",label); exit(1); }
}
// Only collectors.c is compiled with symbol rewrites. These delegates call real APIs,
// avoiding recursion; numbers count libproc calls, not internal kernel operations.
int profile_pidinfo(int pid,int flavor,uint64_t arg,void *buffer,int size) {
 counters.list++;
 if(!mock) return proc_pidinfo(pid,flavor,arg,buffer,size);
 check(flavor==PROC_PIDLISTFDS && replyIndex<replyCount,"mock list sequence");
 struct Reply reply=replies[replyIndex++]; errno=reply.error;
 if(buffer && reply.bytes>0) {
  int slots=(reply.bytes<size?reply.bytes:size)/(int)sizeof(struct proc_fdinfo);
  struct proc_fdinfo *fds=buffer;
  for(int i=0;i<slots;i++) { fds[i].proc_fd=i+10; fds[i].proc_fdtype=i<mockSockets?PROX_FDTYPE_SOCKET:PROX_FDTYPE_VNODE; }
 }
 return reply.bytes;
}
int profile_pidfdinfo(int pid,int fd,int flavor,void *buffer,int size) {
 counters.socket++;
 if(!mock) return proc_pidfdinfo(pid,fd,flavor,buffer,size);
 if(socketFailure) { errno=EPERM; return 0; }
 check(flavor==PROC_PIDFDSOCKETINFO && size==(int)sizeof(struct socket_fdinfo),"mock socket shape");
 struct socket_fdinfo *s=buffer; memset(s,0,sizeof(*s));
 s->psi.soi_kind=SOCKINFO_TCP; s->psi.soi_family=AF_INET;
 s->psi.soi_proto.pri_tcp.tcpsi_state=TSI_S_LISTEN;
 s->psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport=htons(8123);
 s->psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4.s_addr=htonl(INADDR_LOOPBACK);
 return sizeof(*s);
}
void *profile_malloc(size_t size) { counters.allocations++; return mock && allocationFailure?NULL:malloc(size); }
void profile_free(void *ptr) { if(ptr) counters.frees++; free(ptr); }

static int stack_ports(int32_t pid,AmidPort *ports,int capacity,int *status) {
 struct proc_fdinfo stack[128]; struct proc_fdinfo *fds=stack;
 int size=sizeof(stack); int allocated=0;
 *status=1; errno=0;
 int bytes=profile_pidinfo(pid,PROC_PIDLISTFDS,0,stack,size);
 if(bytes<0 || bytes>size || (bytes>0 && bytes%(int)sizeof(*fds)!=0)) { *status=3; return 0; }
 if(bytes==0 && errno!=0) { *status=errno==EPERM||errno==EACCES?2:3; return 0; }
 // Saturation is ambiguous. Empty retries the original path to preserve its policy.
 if(bytes==size || bytes==0) {
  errno=0; size=profile_pidinfo(pid,PROC_PIDLISTFDS,0,NULL,0);
  if(size<=0 && errno!=0) { *status=errno==EPERM||errno==EACCES?2:3; return 0; }
  if(size==0) return 0;
  if(size<0 || size%(int)sizeof(*fds)!=0 || size>INT_MAX-32*(int)sizeof(*fds)) { *status=3; return 0; }
  size+=32*sizeof(*fds); fds=profile_malloc(size);
  if(!fds) { *status=3; return 0; } allocated=1;
  errno=0; bytes=profile_pidinfo(pid,PROC_PIDLISTFDS,0,fds,size);
  if(bytes<=0 || bytes>size || bytes%(int)sizeof(*fds)!=0) { profile_free(fds); *status=3; return 0; }
 }
 int count=0; if(bytes==size) *status=3;
 for(int i=0;i<bytes/(int)sizeof(*fds);i++) if(fds[i].proc_fdtype==PROX_FDTYPE_SOCKET) {
  struct socket_fdinfo s;
  if(profile_pidfdinfo(pid,fds[i].proc_fd,PROC_PIDFDSOCKETINFO,&s,sizeof(s))!=sizeof(s)) { *status=2; continue; }
  if(s.psi.soi_kind!=SOCKINFO_TCP||s.psi.soi_proto.pri_tcp.tcpsi_state!=TSI_S_LISTEN) continue;
  if(count>=capacity) { *status=3; break; }
  struct in_sockinfo *in=&s.psi.soi_proto.pri_tcp.tcpsi_ini;
  AmidPort *p=&ports[count]; memset(p,0,sizeof(*p)); p->family=s.psi.soi_family; p->port=ntohs((uint16_t)in->insi_lport);
  const void *addr=p->family==AF_INET?(const void *)&in->insi_laddr.ina_46.i46a_addr4:(const void *)&in->insi_laddr.ina_6;
  if((p->family==AF_INET||p->family==AF_INET6)&&inet_ntop(p->family,addr,p->address,sizeof(p->address))) count++;
 }
 if(allocated) profile_free(fds);
 return count;
}
static void setup(struct Reply *values,int count,int sockets) {
 memcpy(replies,values,count*sizeof(*values)); replyCount=count; replyIndex=0; mockSockets=sockets;
 mock=1; socketFailure=0; allocationFailure=0; counters=(struct Counters){0};
}
static void expected(struct Reply *values,int count,int sockets,int failSocket,int failAllocation,int capacity,int expectedCount,int expectedStatus,unsigned calls,unsigned allocations) {
 setup(values,count,sockets); socketFailure=failSocket; allocationFailure=failAllocation;
 AmidPort ports[4]; int status=0; int found=stack_ports(1,ports,capacity,&status);
 check(found==expectedCount && status==expectedStatus,"candidate result policy");
 check(replyIndex==replyCount && counters.list==calls && counters.allocations==allocations,"candidate operation bounds");
 check(counters.frees==(allocations && !failAllocation?1u:0u),"candidate allocation ownership");
}
static void deterministic(void) {
 int unit=sizeof(struct proc_fdinfo), full=128*unit;
 struct Reply fit[]={{2*unit,0}}; expected(fit,1,1,0,0,4,1,1,1,0);
 struct Reply boundary[]={{full,0},{129*unit,0},{129*unit,0}}; expected(boundary,3,1,0,0,4,1,1,3,1);
 struct Reply saturated[]={{full,0},{128*unit,0},{160*unit,0}}; expected(saturated,3,0,0,0,4,0,3,3,1);
 struct Reply shrunk[]={{full,0},{128*unit,0},{unit,0}}; expected(shrunk,3,1,0,0,4,1,1,3,1);
 struct Reply empty[]={{0,0},{0,0}}; expected(empty,2,0,0,0,4,0,1,2,0);
 struct Reply refillEmpty[]={{full,0},{128*unit,0},{0,0}}; expected(refillEmpty,3,0,0,0,4,0,3,3,1);
 struct Reply denied[]={{0,EPERM}}; expected(denied,1,0,0,0,4,0,2,1,0);
 struct Reply gone[]={{0,ESRCH}}; expected(gone,1,0,0,0,4,0,3,1,0);
 struct Reply malformed[]={{unit+1,0}}; expected(malformed,1,0,0,0,4,0,3,1,0);
 struct Reply oversized[]={{full+unit,0}}; expected(oversized,1,0,0,0,4,0,3,1,0);
 struct Reply overflow[]={{full,0},{INT_MAX-(INT_MAX%unit),0}}; expected(overflow,2,0,0,0,4,0,3,2,0);
 struct Reply noMemory[]={{full,0},{128*unit,0}}; expected(noMemory,2,0,0,1,4,0,3,2,1);
 expected(fit,1,1,1,0,4,0,2,1,0);
 expected(fit,1,2,0,0,1,1,3,1,0);
 // Compare current production routine only for valid replies, not malformed inputs.
 AmidPort a[4],b[4]; int sa,sb;
 struct Reply baseline[]={{2*unit,0},{2*unit,0}}; setup(baseline,2,1);
 int na=amid_ports(1,a,4,&sa); setup(fit,1,1); int nb=stack_ports(1,b,4,&sb);
 check(na==nb && sa==sb && memcmp(a,b,na*sizeof(*a))==0,"valid baseline parity");
 mock=0;
}
struct Measurement { double cpu,wall; unsigned calls; unsigned checksum; struct Counters operations; int cpuKnown; };
static double wall(void) { struct timespec t; check(clock_gettime(CLOCK_MONOTONIC,&t)==0,"monotonic clock"); return t.tv_sec+t.tv_nsec/1e9; }
static int cpu(double *value) { struct rusage r; if(getrusage(RUSAGE_SELF,&r)!=0) return 0; *value=r.ru_utime.tv_sec+r.ru_stime.tv_sec+(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1e6; return *value>=0; }
static struct Measurement measure(int candidate) {
 counters=(struct Counters){0}; double before=0,after=0; int known=cpu(&before); double start=wall(); unsigned checksum=0;
 for(int i=0;i<1000;i++) { AmidPort ports[64]; int status; int n=candidate?stack_ports(getpid(),ports,64,&status):amid_ports(getpid(),ports,64,&status); check(status==1,"owned enumeration coverage"); checksum+=(unsigned)n; }
 double elapsed=wall()-start; known=cpu(&after)&&known&&after>=before;
 return (struct Measurement){.cpu=after-before,.wall=elapsed,.calls=1000,.checksum=checksum,.operations=counters,.cpuKnown=known};
}
static void ownedParity(void) {
 AmidPort baseline[64],candidate[64]; int baselineStatus,candidateStatus;
 int a=amid_ports(getpid(),baseline,64,&baselineStatus);
 int b=stack_ports(getpid(),candidate,64,&candidateStatus);
 check(a==b && baselineStatus==candidateStatus && baselineStatus==1,"owned endpoint coverage parity");
 check(memcmp(baseline,candidate,a*sizeof(*baseline))==0,"owned exact endpoint parity");
}
static void printMeasurement(struct Measurement m) {
 printf("{\"calls\":%u,\"ownCPUSeconds\":",m.calls); if(m.cpuKnown) printf("%.9f",m.cpu); else printf("null");
 printf(",\"wallSeconds\":%.9f,\"listenerCountChecksum\":%u,\"listCalls\":%u,\"socketCalls\":%u,\"allocations\":%u,\"frees\":%u}",m.wall,m.checksum,m.operations.list,m.operations.socket,m.operations.allocations,m.operations.frees);
}
int main(void) {
 deterministic();
 int listener=socket(AF_INET,SOCK_STREAM,0); check(listener>=0,"owned socket");
 struct sockaddr_in address={.sin_len=sizeof(address),.sin_family=AF_INET,.sin_port=0,.sin_addr={.s_addr=htonl(INADDR_LOOPBACK)}};
 check(bind(listener,(struct sockaddr *)&address,sizeof(address))==0 && listen(listener,1)==0,"owned listen");
 ownedParity();
 struct Measurement results[4]; results[0]=measure(0); results[1]=measure(1);
 check(results[0].checksum==results[1].checksum && results[0].checksum>=1000,"low-FD parity");
 int owned[256]; for(int i=0;i<256;i++) { owned[i]=open("/dev/null",O_RDONLY); check(owned[i]>=0,"owned high-FD setup"); }
 ownedParity();
 results[2]=measure(0); results[3]=measure(1);
 check(results[2].checksum==results[3].checksum && results[2].checksum>=1000,"high-FD parity");
 for(int i=0;i<256;i++) close(owned[i]); close(listener);
 printf("{\"scope\":\"Test-local stack candidate; own PID only, no connections or payloads. Counts are libproc calls/user allocations, not kernel internal syscalls. Fixed baseline-then-candidate order; no whole-app claim.\",\"deterministicCasesPassed\":15,\"shapes\":[");
 for(int i=0;i<2;i++) { if(i) printf(","); printf("{\"ownedExtraFDs\":%d,\"baseline\":",i?256:0); printMeasurement(results[i*2]); printf(",\"stackCandidate\":"); printMeasurement(results[i*2+1]); printf("}"); }
 printf("]}\n"); return 0;
}
