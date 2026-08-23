# eks-llm-playground

This is a small AWS EKS environment I use to experiment with Kubernetes infrastructure and self-hosted LLM workloads.

The cluster is provisioned with Terraform and uses separate Bottlerocket managed node groups for general cluster workloads and LLM workloads. Ollama and Open WebUI are configured to run on the dedicated LLM nodes.

This is a playground rather than a production reference architecture. I intentionally kept the environment small and use Spot instances to keep the cost reasonable while testing different Kubernetes and AI workload configurations.

## What I'm experimenting with

The main things I wanted to explore with this setup were:

* Provisioning EKS and the surrounding AWS networking with Terraform
* Running Bottlerocket as the worker node operating system
* Separating workloads using Kubernetes labels, taints, and tolerations
* Using the AWS EBS CSI driver for persistent storage
* Running Ollama inside Kubernetes
* Connecting Open WebUI to an Ollama service inside the cluster
* Keeping an experimental EKS environment reasonably inexpensive

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
    │   └── Spot capacity
    │
    └── LLM Node Group
        ├── Bottlerocket
        ├── Spot capacity
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

Persistent storage is handled through the EBS CSI driver:

```text
EBS CSI Driver
      │
      ▼
gp3-csi StorageClass
      │
      ▼
Persistent Volumes
      │
      ├── Ollama model storage
      └── Open WebUI data
```

## Repository layout

```text
.
├── eks.tf
├── main.tf
├── provider.tf
├── variables.tf
├── output.tf
├── ollama-values.yaml
├── openwebui-values.yaml
├── .terraform.lock.hcl
└── README.md
```

### `main.tf`

Creates the AWS networking used by the cluster.

The VPC spans three availability zones and includes public, private, and intra subnets.

### `eks.tf`

Contains most of the EKS configuration, including:

* EKS managed node groups
* Bottlerocket AMIs
* EKS add-ons
* EBS CSI configuration
* IRSA configuration
* Kubernetes storage class
* LLM workload labels and taints

### `ollama-values.yaml`

Helm values for running Ollama on the dedicated LLM node group.

The current configuration:

* Runs one replica
* Uses persistent storage
* Runs CPU-only
* Pulls `llama3.2:1b`
* Uses the `role=llm` node selector
* Tolerates the LLM node taint

### `openwebui-values.yaml`

Helm values for Open WebUI.

Open WebUI is scheduled on the same dedicated LLM node group and connects to Ollama using the internal Kubernetes service address.

## EKS configuration

The cluster uses managed Bottlerocket node groups.

I split the nodes into two groups because I wanted to keep the AI workload separate from general cluster workloads.

### System nodes

The system node group is intended for normal cluster workloads.

It currently uses Spot capacity because the environment is for testing.

### LLM nodes

The LLM node group has:

```text
role=llm
workload=llm
```

and a taint:

```text
workload=llm:NoSchedule
```

The Ollama and Open WebUI configurations include matching node selectors and tolerations.

This keeps those workloads from being scheduled onto other nodes accidentally.

## Storage

The cluster enables the AWS EBS CSI driver and creates a GP3-backed Kubernetes StorageClass.

The StorageClass uses:

```text
Provisioner: ebs.csi.aws.com
Volume type: gp3
Filesystem: ext4
Volume binding: WaitForFirstConsumer
Expansion: enabled
```

The goal was to give Ollama and Open WebUI persistent storage without tying the application configuration directly to an individual EC2 instance.

## Why Bottlerocket?

I wanted to use Bottlerocket here because it is designed specifically for container workloads and has a smaller operating surface than a traditional general-purpose Linux image.

For this environment, I also disable the Bottlerocket admin host container and enable kernel lockdown in integrity mode.

This isn't meant to demonstrate every Bottlerocket security option. It was mainly an opportunity to work with Bottlerocket-managed EKS nodes instead of the more common Amazon Linux worker nodes.

## Why Spot instances?

Both node groups currently use Spot capacity.

That's a deliberate cost decision for this repo.

For a playground where the cluster can be recreated, interruptions are acceptable. I would not use this exact setup unchanged for a production LLM service where workload availability or predictable capacity mattered.

A production design would need to account for things like:

* Spot interruption handling
* multiple replicas
* PodDisruptionBudgets
* multiple availability zones
* autoscaling
* on-demand capacity where needed
* workload recovery
* model startup time
* persistent storage behavior

## Prerequisites

You'll need:

* AWS account
* AWS CLI
* Terraform
* kubectl
* Helm
* AWS credentials configured locally

The AWS region defaults to:

```text
us-east-2
```

You can change that in `variables.tf` or pass a different value when running Terraform.

## Terraform

Initialize the project:

```bash
terraform init
```

Review the configuration:

```bash
terraform plan
```

Apply the infrastructure:

```bash
terraform apply
```

The Kubernetes and Helm providers in this repo use the local kubeconfig file:

```text
~/.kube/config
```

Because of that, make sure your local Kubernetes context is configured for the EKS cluster before using resources that depend on the Kubernetes provider.

After the EKS cluster is available, the kubeconfig can be updated with AWS CLI:

```bash
aws eks update-kubeconfig \
  --region us-east-2 \
  --name <cluster-name>
```

Then verify access:

```bash
kubectl get nodes
```

You should see the Bottlerocket worker nodes registered with the cluster.

## Checking the node groups

To see node labels:

```bash
kubectl get nodes --show-labels
```

To inspect the LLM nodes specifically:

```bash
kubectl get nodes -l role=llm
```

To check the taints:

```bash
kubectl describe node <llm-node-name>
```

The dedicated LLM nodes should include the `workload=llm:NoSchedule` taint.

## Ollama

`ollama-values.yaml` contains the values I use for the Ollama workload.

The configuration currently runs:

```text
llama3.2:1b
```

and uses persistent storage for model data and cache.

The workload is intentionally CPU-only for now:

```yaml
ollama:
  gpu:
    enabled: false
```

This keeps the playground inexpensive and lets me test the Kubernetes side of the setup without requiring GPU instances.

For larger models or serious inference workloads, I would move this to GPU-backed nodes and revisit CPU, memory, storage, scheduling, and autoscaling requirements.

## Open WebUI

Open WebUI provides the frontend for interacting with Ollama.

The configured Ollama endpoint is:

```text
http://ollama.llm.svc.cluster.local:11434
```

That keeps communication between Open WebUI and Ollama inside the Kubernetes cluster rather than exposing Ollama directly.

## Things I would change for production

This repo is intentionally not presented as a production-ready platform.

If I were building this for production, some of the first areas I would revisit are:

* private EKS API access
* stronger network controls
* workload identity and IAM permissions
* secrets management
* ingress and TLS
* autoscaling
* highly available node capacity
* monitoring and alerting
* application health checks
* resource requests and limits
* PodDisruptionBudgets
* backup and restore
* GPU scheduling if larger models are required
* GitOps-based application deployment
* cost monitoring

The current goal is to keep the environment understandable enough that I can change pieces, break things, and rebuild it quickly.

## Cleanup

EKS environments can generate AWS charges even when you're not actively using them.

When you're finished experimenting, remove the infrastructure:

```bash
terraform destroy
```

Always review the destroy plan before confirming it.

## What I'm working on next

A few things I'd like to experiment with next:

* GPU-backed Ollama nodes
* Karpenter for node provisioning
* Prometheus and Grafana monitoring
* model inference metrics
* Kubernetes autoscaling
* GitOps deployment
* interruption handling for Spot nodes
* comparing self-hosted models with managed inference services

The repo will probably change as I test those ideas. That's the reason I called it a playground.

