enum xdp_action {
	XDP_ABORTED = 0,
	XDP_DROP,
	XDP_PASS,
	XDP_TX,
	XDP_REDIRECT,
};

typedef unsigned int __u32;

struct xdp_md {
	__u32 data;
	__u32 data_end;
	__u32 data_meta;
	__u32 ingress_ifindex;
	__u32 rx_queue_index;
	__u32 egress_ifindex;
};

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

__u32 counter = 0;

SEC("xdp")
int packet_count(struct xdp_md *ctx) {
	//bpf_printk("%d", counter);
	counter = counter + 1;
	return XDP_PASS;
}

char LICENSE[] SEC("license") = "Dual BSD/GPL";






