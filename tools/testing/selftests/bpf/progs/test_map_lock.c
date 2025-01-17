// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2019 Facebook
#include <linux/bpf.h>
#include <linux/version.h>
#include "bpf_helpers.h"

#define VAR_NUM 16

struct hmap_elem {
	struct bpf_spin_lock lock;
	int var[VAR_NUM];
};

struct {
	__u32 type;
	__u32 max_entries;
	__u32 *key;
	struct hmap_elem *value;
} hash_map SEC(".maps") = {
	.type = BPF_MAP_TYPE_HASH,
	.max_entries = 1,
};

struct array_elem {
	struct bpf_spin_lock lock;
	int var[VAR_NUM];
};

struct {
	__u32 type;
	__u32 max_entries;
	int *key;
	struct array_elem *value;
} array_map SEC(".maps") = {
	.type = BPF_MAP_TYPE_ARRAY,
	.max_entries = 1,
};

SEC("map_lock_demo")
int bpf_map_lock_test(struct __sk_buff *skb)
{
	struct hmap_elem zero = {}, *val;
	int rnd = bpf_get_prandom_u32();
	int key = 0, err = 1, i;
	struct array_elem *q;

	val = bpf_map_lookup_elem(&hash_map, &key);
	if (!val)
		goto err;
	/* spin_lock in hash map */
	bpf_spin_lock(&val->lock);
	for (i = 0; i < VAR_NUM; i++)
		val->var[i] = rnd;
	bpf_spin_unlock(&val->lock);

	/* spin_lock in array */
	q = bpf_map_lookup_elem(&array_map, &key);
	if (!q)
		goto err;
	bpf_spin_lock(&q->lock);
	for (i = 0; i < VAR_NUM; i++)
		q->var[i] = rnd;
	bpf_spin_unlock(&q->lock);
	err = 0;
err:
	return err;
}
char _license[] SEC("license") = "GPL";
