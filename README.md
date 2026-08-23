I built this repo as a small EKS environment for experimenting with running local LLM workloads on Kubernetes.

Terraform provisions the AWS networking and EKS cluster, including separate Bottlerocket node groups for system and LLM workloads. Ollama runs on the dedicated LLM nodes, with Open WebUI connecting to it inside the cluster.

The setup is intentionally small and uses Spot instances because this is a playground rather than a production reference architecture.
