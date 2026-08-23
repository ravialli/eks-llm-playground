# eks-llm-playground

A small AWS EKS environment I use to experiment with Kubernetes infrastructure and self-hosted LLM workloads.

Terraform provisions the AWS networking, EKS cluster, Bottlerocket node groups, IAM resources, and EBS CSI support. Ollama and Open WebUI run separately on a dedicated LLM node group.

This is a playground rather than a production reference architecture. I keep it small, use Spot capacity, and deliberately separate the infrastructure and application layers so I can change things without rebuilding everything.

## What I'm experimenting with

* EKS and AWS networking with Terraform
* Bottlerocket worker nodes
* Kubernetes labels, taints, and tolerations
* Dedicated nodes for LLM workloads
* EBS-backed persistent storage
* Ollama on Kubernetes
* Open WebUI communicating with Ollama through Kubernetes DNS
* Cost-conscious infrastructure for experimentation

## Architecture

```text
AWS
│
├── VPC
│   ├── Public subnets
│   ├── Private subnets
│   └── Intra subnets
│
└── Amazon EKS
    │
    ├── System Node Group
    │   ├── Bottlerocket
    │   └── Spot
    │
    └── LLM Node Group
        ├── Bottlerocket
        ├── Spot
        ├── role=llm
        └── workload=llm
             │
             ├── Ollama
             │   └── llama3.2:1b
             │
             └── Open WebUI
                  │
                  └── Ollama service
```

Persistent application data is stored on GP3 EBS volumes through the AWS EBS CSI driver.

```text
EBS CSI
   │
   ▼
gp3-csi StorageClass
   │
   ▼
Persistent Volumes
   │
   ├── Ollama model data
   └── Open WebUI data
```

## A few design choices

### Dedicated LLM nodes

The LLM node group is labeled with:

```text
role=llm
workload=llm
```

and uses:

```text
workload=llm:NoSchedule
```

as a taint.

The Ollama and Open WebUI configurations contain matching node selectors and tolerations. I use this to keep the LLM workloads separated from general cluster workloads.

### Bottlerocket

I wanted to use Bottlerocket instead of a general-purpose Linux worker image because it is purpose-built for running containers.

This also gave me a chance to experiment with Bottlerocket configuration such as disabling the admin host container and enabling kernel lockdown.

### Spot capacity

Both node groups use Spot instances.

That's intentional for this project. The environment is disposable and can be rebuilt, so I prefer keeping experimentation costs down.

For a production service, I would use a more deliberate mix of capacity types and design for interruption handling and availability.

### Infrastructure and applications stay separate

I don't manage the LLM applications through Terraform.

```text
Terraform
├── VPC
├── EKS
├── Node groups
├── IAM
└── EBS CSI

        ↓

Kubernetes
└── gp3-csi StorageClass

        ↓

Helm
├── Ollama
└── Open WebUI
```

That separation makes it easier to experiment with the application layer without tying every change to a Terraform deployment.

## Repository layout

```text
.
├── eks.tf
├── main.tf
├── provider.tf
├── variables.tf
├── output.tf
│
├── kubernetes/
│   └── storage-class.yaml
│
├── helm/
│   ├── README.md
│   ├── ollama-values.yaml
│   └── openwebui-values.yaml
│
├── docs/
│   └── OPERATIONS.md
│
├── .terraform.lock.hcl
├── LICENSE
└── README.md
```

## Quick start

Create the infrastructure:

```bash
terraform init
terraform plan
terraform apply
```

Configure access to EKS:

```bash
aws eks update-kubeconfig \
  --region "$(terraform output -raw region)" \
  --name "$(terraform output -raw cluster_name)"
```

Verify the cluster:

```bash
kubectl get nodes
```

Create the StorageClass:

```bash
kubectl apply -f kubernetes/storage-class.yaml
```

Then deploy Ollama and Open WebUI using the configuration under `helm/`.

For the full setup, verification, troubleshooting, and cleanup workflow, see:

**[Operations guide](docs/OPERATIONS.md)**

For application-specific Helm details, see:

**[Helm guide](helm/README.md)**

## Current model

The playground currently uses:

```text
llama3.2:1b
```

It's intentionally small and CPU-friendly. The goal here is primarily Kubernetes experimentation rather than inference benchmarking.

## Production considerations

This repo is deliberately not presented as production-ready.

If I were turning this into a production platform, I'd revisit network exposure, secrets management, IAM, autoscaling, high availability, monitoring, resource limits, disruption handling, GitOps, backups, and GPU scheduling for larger models.

## Next experiments

I'm interested in trying a few things next:

* Karpenter
* GPU-backed LLM nodes
* Prometheus and Grafana
* inference metrics
* autoscaling
* GitOps
* Spot interruption handling
* self-hosted versus managed inference

The repo will change as I test those ideas. That's the reason I called it a playground.

