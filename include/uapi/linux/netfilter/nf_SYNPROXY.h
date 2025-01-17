/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _NF_SYNPROXY_H
#define _NF_SYNPROXY_H

#include <linux/types.h>

#define NF_SYNPROXY_OPT_MSS		0x01
#define NF_SYNPROXY_OPT_WSCALE		0x02
#define NF_SYNPROXY_OPT_SACK_PERM	0x04
#define NF_SYNPROXY_OPT_TIMESTAMP	0x08
#define NF_SYNPROXY_OPT_ECN		0x10

struct nf_synproxy_info {
	__u8	options;
	__u8	wscale;
	__u16	mss;
};

#endif /* _NF_SYNPROXY_H */
