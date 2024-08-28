enum xdp_action {
	XDP_ABORTED = 0,
	XDP_DROP,
	XDP_PASS,
	XDP_TX,
	XDP_REDIRECT,
};


typedef unsigned int __u32;
typedef unsigned short __u16;
struct xdp_md {
	__u32 data;
	__u32 data_end;
	__u32 data_meta;
	__u32 ingress_ifindex;
	__u32 rx_queue_index;
	__u32 egress_ifindex;
};

#define ETH_P_IPV6 0x86DD

struct ethhdr {
	unsigned char h_dest[6];
	unsigned char h_source[6];
	__u16         h_proto;
}; //__attribute__((packed));

#undef htons
#define htons(a) __builtin_bswap32(a)
static long (* const bpf_trace_printk)(const char *fmt, __u32 fmt_size, ...) = (void *) 6;
#ifdef BPF_NO_GLOBAL_DATA
#define BPF_PRINTK_FMT_MOD
#else 
#define BPF_PRINTK_FMT_MOD static const
#endif 

#undef bpf_printk
#define __bpf_printk(fmt, ...)				\
{							\
	BPF_PRINTK_FMT_MOD char ____fmt[] = fmt;	\
	bpf_trace_printk(____fmt, sizeof(____fmt),	\
			 ##__VA_ARGS__);		\
}

#undef SEC
#define SEC(A) __attribute__ ((section(A),used))

SEC("xdp")
int packet_count_ctx(struct xdp_md *ctx) {
	__u32 *data = (__u32*)ctx->data;
        __u32 *data_end = (__u32*)ctx->data_end;
	struct ethhdr *eth = data;
        __u16 h_proto;

        if (data + sizeof(struct ethhdr) > data_end)
	   return XDP_DROP;

        h_proto = eth->h_proto;

        if (h_proto == htons(ETH_P_IPV6))
	   return XDP_DROP;

	return XDP_PASS;
}

char LICENSE[] SEC("license") = "Dual BSD/GPL";






