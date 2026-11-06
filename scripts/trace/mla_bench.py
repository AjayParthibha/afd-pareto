#!/usr/bin/env python3
"""Time vLLM's Triton MLA decode kernel standalone across num_kv_splits (1 GPU)."""
import torch
import triton
from vllm.v1.attention.ops.triton_decode_attention import decode_attention_fwd

H, LORA, ROPE, PAGE = 16, 512, 64, 16
D = LORA + ROPE
dev = "cuda"
torch.manual_seed(0)


def vllm_splits(ctx, sms):
    return min(triton.next_power_of_2(max(1, ctx // 512)), sms * 2)


def bench(B, ctx, splits):
    pages_per = triton.cdiv(ctx, PAGE)
    cache = torch.randn(B * pages_per + 1, PAGE, 1, D, device=dev, dtype=torch.bfloat16)
    k = cache
    v = cache[..., :LORA]
    q = torch.randn(B, H, D, device=dev, dtype=torch.bfloat16)
    o = torch.zeros(B, H, LORA, device=dev, dtype=torch.bfloat16)
    lse = torch.zeros(B, H, device=dev, dtype=torch.bfloat16)
    perm = torch.randperm(B * pages_per, device=dev, dtype=torch.int32) + 1  # scattered pages
    table = perm.view(B, pages_per)
    seq = torch.full((B,), ctx, device=dev, dtype=torch.int32)
    logits = torch.empty(B, H, splits, LORA + 1, device=dev, dtype=torch.float32)
    one = torch.tensor(1.0, device=dev)

    def run():
        decode_attention_fwd(q, k, v, o, lse, table, seq, logits, splits, D ** -0.5, PAGE,
                             k_scale=one, v_scale=one, is_mla=True)

    for _ in range(3):
        run()
    torch.cuda.synchronize()
    g = torch.cuda.CUDAGraph()
    with torch.cuda.graph(g):
        for _ in range(20):
            run()
    torch.cuda.synchronize()
    st, en = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
    st.record()
    for _ in range(5):
        g.replay()
    en.record()
    torch.cuda.synchronize()
    us = st.elapsed_time(en) * 1e3 / 100
    gbs = B * ctx * D * 2 / (us * 1e-6) / 1e9
    return us, gbs


def main():
    sms = torch.cuda.get_device_properties(0).multi_processor_count
    print("GPU %s, %d SMs" % (torch.cuda.get_device_name(0), sms))
    print("%5s %6s %7s %10s %9s %s" % ("B", "ctx", "splits", "us/call", "GB/s", ""))
    for ctx in (600, 1100, 4200):
        for B in (16, 32, 64, 128):
            base = vllm_splits(ctx, sms)
            best = None
            for s in (1, 2, 4, 8, 16, 32):
                us, gbs = bench(B, ctx, s)
                tag = "<- vLLM default" if s == base else ""
                print("%5d %6d %7d %10.1f %9.0f %s" % (B, ctx, s, us, gbs, tag))
                if best is None or us < best[1]:
                    best = (s, us)
            d_us = bench(B, ctx, base)[0]
            print("   best splits=%d: %.1f us vs default %.1f us -> %.2fx" % (best[0], best[1], d_us, d_us / best[1]))


if __name__ == "__main__":
    main()
