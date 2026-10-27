# **Proposal: [https\://docs.google.com/document/d/1ol\_GylNxxgKMbrGl-8Uzf0-gVIuBwt77YS3USzk3uhk/edit?usp=sharing](https://docs.google.com/document/d/1ol_GylNxxgKMbrGl-8Uzf0-gVIuBwt77YS3USzk3uhk/edit?usp=sharing)**

# **Improving the LLM serving Pareto frontier with AFD on GPUs**

* **Team:** Team 32 — Ajay Parthibha, Arihant Swain, Aditya Nandyal, logan prosser

* **Advisor:** Eric Ding — ericding@cs.cornell.edu — GitHub @EricDinging

* **Compute:** A100 on Perlmutter

## **Background**

A transformer processes a prompt in a parallel prefill phase, then generates output tokens sequentially during decode. Each layer combines attention, which reads previous tokens through a key/value (KV) cache, with a feed-forward network (FFN). In a mixture-of-experts (MoE) model, a router selects a few FFN experts per token. All expert weights must remain accessible even though each token uses only a subset.

Attention and expert computation have different resource needs. Attention depends on context length and KV-cache traffic, while expert efficiency depends on how many tokens reach each expert. Colocating both on the same GPUs couples their memory budgets and parallelism choices. Attention–FFN disaggregation (AFD) separates them into device groups, allowing independent allocation and pooling expert work from multiple attention workers.

The tradeoff is an M-N activation dispatch and combine at every model layer. Small batches may spend more time communicating or waiting than they save in expert computation. Microbatch overlap could improve this balance. The questions:

* Which GPU settings—attention/FFN split ratio, expert batch size, maximum batch wait, and microbatch overlap—most improve AFD serving efficiency?

* For the same model, workload, and GPU budget, when does tuned AFD improve the throughput/latency Pareto frontier over colocated serving?

## **Objective**

* Deploy colocated and AFD systems using representative workloads and MoE models.

* Implement one or several optimization: expert-as-a-service, dynamic attention/FFN ratio scaling, or propose new optimizations.

* Find the best serving frontier across GPU settings and explain where AFD helps or loses.

## **Example deliverables**

* CCL-Bench pull request with the optimization, launch configurations, workload cards, example traces, and scripts reproducing Pareto plots.

* Create a section on CCL-Bench leaderboard on AFD serving performance. For one inference workload and model pair, report the performance of different hardware platform \- serving system \- system configuration combinations.

* Pareto plots.

* Optimizations on top of the vLLM afd codebase.

## **Code and tools**

* [CCL-bench guide](https://github.com/cornell-sysphotonics/ccl-bench)

[vLLM AFD plugin](https://github.com/vllm-project/afd-plugin), NCCL, and Nsight Systems. Confirm A100 compatibility before choosing the implementation; current DeepEP requirements target newer GPUs.

* [MegaScale-Infer](https://arxiv.org/abs/2504.02263): independent attention/FFN scaling and microbatch pipelining.

* [AFD performance boundaries](https://arxiv.org/abs/2602.09721): when disaggregation helps or loses against conventional EP.

* [FastAFD](https://github.com/hao-ai-lab/FastAFD): an overlap/communication design reference; its Blackwell deployment is outside the required hardware scope.