#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <ifaddrs.h>
static unsigned char reply[2048]; static size_t length,reported; static int race,fail;
static int mock_sysctl(int *mib,u_int n,void *out,size_t *size,void *newp,size_t newlen) {
 assert(newp==NULL&&newlen==0);assert(n==6&&mib[0]==CTL_NET&&mib[1]==PF_LINK&&mib[2]==NETLINK_GENERIC&&mib[3]==IFMIB_IFALLDATA&&mib[4]==0&&mib[5]==IFDATA_GENERAL);
 if(fail){errno=EPERM;return -1;} if(!out){*size=length;return 0;}
 if(race){errno=ENOMEM;return -1;} assert(*size>=length);memcpy(out,reply,length);*size=reported?reported:length;return 0;
}
static int mock_getifaddrs(struct ifaddrs **out) {
 static struct ifaddrs a; static struct sockaddr address; static struct if_data data;
 memset(&a,0,sizeof(a));memset(&address,0,sizeof(address));memset(&data,0,sizeof(data));
 address.sa_family=AF_LINK;a.ifa_addr=&address;a.ifa_name="test1";a.ifa_data=&data;
 data.ifi_ibytes=123;data.ifi_obytes=456;*out=&a;return 0;
}
static void mock_freeifaddrs(struct ifaddrs *a){(void)a;}
#define getifaddrs mock_getifaddrs
#define freeifaddrs mock_freeifaddrs
#define sysctl mock_sysctl
#include COLLECTOR_SOURCE
#undef sysctl
static void reset(void){memset(reply,0,sizeof(reply));length=reported=0;race=fail=0;}
static void append(unsigned index,uint64_t rx,uint64_t tx){struct ifmibdata m={0};snprintf(m.ifmd_name,sizeof(m.ifmd_name),"test%u",index);m.ifmd_data.ifi_ibytes=rx;m.ifmd_data.ifi_obytes=tx;memcpy(reply+length,&m,sizeof(m));length+=sizeof(m);}
static int cases;
#define CHECK(label,condition) do { cases++; if(!(condition)) { fprintf(stderr,"FAIL %s\n",label); return 1; } } while(0)
int main(void) {
 AmidInterface out[2],before[2]; memset(out,0xa5,sizeof(out)); memcpy(before,out,sizeof(out));
 reset(); append(1,UINT64_C(4294967296)+123,UINT64_C(8589934592)+456);
 CHECK("full 64-bit counters",amid_interfaces(out,2)==1&&out[0].received==UINT64_C(4294967296)+123&&out[0].sent==UINT64_C(8589934592)+456);
 reset(); append(1,0,0); CHECK("legitimate zero",amid_interfaces(out,2)==1&&out[0].received==0&&out[0].sent==0);
 reset(); length=3; CHECK("short sizing reply",amid_interfaces(out,2)==-1);
 reset(); append(1,1,2); reported=length-1; CHECK("short data reply",amid_interfaces(out,2)==-1);
 reset(); append(1,1,2); reported=length+sizeof(struct ifmibdata); CHECK("oversized data reply",amid_interfaces(out,2)==-1);
 reset(); append(1,1,2); append(2,3,4); CHECK("capacity overflow",amid_interfaces(out,1)==-1);
 reset(); append(1,1,2); append(1,3,4); CHECK("duplicate names",amid_interfaces(out,2)==-1);
 reset(); append(1,1,2); memset(reply,'a',IFNAMSIZ); CHECK("unterminated name",amid_interfaces(out,2)==-1);
 reset(); append(1,1,2); reply[0]=0; CHECK("empty name",amid_interfaces(out,2)==-1);
 reset(); append(1,1,2); race=1; CHECK("size race",amid_interfaces(out,2)==-1);
 race=0; CHECK("next sample recovery",amid_interfaces(out,2)==1&&out[0].received==1&&out[0].sent==2);
 reset(); fail=1; CHECK("permission denial",amid_interfaces(out,2)==-1);
 reset(); CHECK("empty interface list",amid_interfaces(out,2)==0);
 CHECK("zero capacity",amid_interfaces(out,0)==-1);
 CHECK("null output",amid_interfaces(NULL,2)==-1);
 reset(); append(1,1,2); append(2,3,4); reply[sizeof(struct ifmibdata)]=0; memcpy(out,before,sizeof(out));
 CHECK("whole reply validation",amid_interfaces(out,2)==-1&&memcmp(out,before,sizeof(out))==0);
 reset(); append(1,1,2); append(2,UINT64_MAX,4);
 CHECK("multiple interfaces and maximum counter",amid_interfaces(out,2)==2&&strcmp(out[0].name,"test1")==0&&strcmp(out[1].name,"test2")==0&&out[1].received==UINT64_MAX);
 reported=sizeof(struct ifmibdata); CHECK("interface list shrink",amid_interfaces(out,2)==1&&out[0].received==1);
 printf("PASS %d injected interface-reply cases; no host metadata collection\n",cases); return 0;
}
