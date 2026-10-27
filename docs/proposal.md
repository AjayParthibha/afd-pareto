# **Improving the LLM Serving Pareto Frontier with AFD on GPUs**

We will first select an A100-compatible AFD implementation, MoE model, and workload. Then, we will deploy both a colocated baseline and an AFD configuration, check their outputs for correctness, and record software versions and launch configurations.

Next, we will measure throughput and latency across different request loads and a small set of feasible GPU configurations. We will investigate attention-to-FFN GPU allocation, expert batch size, maximum batch wait, and microbatch overlap where supported. Using Nsight Systems, we will examine communication, computation, and idle time to identify where AFD helps or loses.

Based on the initial results, we propose implementing one targeted optimization informed by our profiling, keeping in mind Eric’s guidance and the capabilities of the chosen codebase. We will compare the optimized implementation against the original AFD system and a tuned colocated baseline. Our evaluation will include throughput-latency Pareto plots and a discussion of the workloads and settings under which each approach performs best.

**Milestones:**

* **October 26-November 2:** Confirm the model, code revision, GPU budget, workload, and metrics; establish working colocated and AFD runs and perform correctness checks. First milestone is a startup week to get ready for later milestones.  
* **November 3-8:** Collect initial benchmark results and profiler traces; identify a bottleneck and begin the optimization.  
* **November 9:** Present initial comparisons, the identified bottleneck, and progress on the optimization at the midpoint presentation.  
* **November 10-23:** Complete the optimization and run controlled experiments across selected configurations and workloads.  
* **November 24-December 1:** Repeat key measurements, generate Pareto plots, and prepare reproducible scripts, workload cards, and traces for a potential CCL-Bench contribution.  
* **December 2-7:** Finalize the analysis, documentation, and poster for the December 7 presentation.

## **Proposed responsibilities:**

* **Ajay:** Lead environment setup, GPU allocation, and deployment of the colocated and AFD systems.  
* **Arihant:** Lead workload preparation, benchmark automation, and baseline measurements.  
* **Aditya:** Lead profiling and implementation of the selected optimization, with support from the team.  
* **Logan:** Lead result analysis, Pareto plots, and preparation of CCL-Bench artifacts.