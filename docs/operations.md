# Operations Guide

This document covers the setup, verification, troubleshooting, and cleanup workflow for `eks-llm-playground`.

The environment is split into three layers:

```text
Terraform
   ↓
AWS / EKS infrastructure

Kubernetes
   ↓
Cluster resources

Helm
   ↓
Ollama and Open WebUI
```

I keep those layers separate so infrastructure changes and application changes don't have to happen through the same deployment path.

## Prerequisites

Before starting, I expect the following tools to be available locally:

* AWS CLI
* Terraform
* kubectl
* Helm

AWS credentials also need to be configured for an account with permission to create the resources used by the project.

The default region is:

```text
us-east-2
```

## 1. Validate Terraform

Before creating anything:

```bash
terraform fmt -recursive
terraform init
terraform validate
```

Review the proposed infrastructure:

```bash
terraform plan
```

I prefer checking the plan before every apply rather than treating `terraform apply` as the first validation step.

## 2. Create the infrastructure

Run:

```bash
terraform apply
```

Terraform creates the AWS networking and EKS infrastructure.

The environment includes:

* VPC
* public, private, and intra subnets
* EKS cluster
* Bottlerocket managed node groups
* IAM resources
* EKS add-ons
* EBS CSI support

After the apply completes, check the outputs:

```bash
terraform output
```

The project exposes:

```text
cluster_name
cluster_endpoint
region
```

## 3. Configure kubectl

Update the local kubeconfig using the Terraform outputs:

```bash
aws eks update-kubeconfig \
  --region "$(terraform output -raw region)" \
  --name "$(terraform output -raw cluster_name)"
```

Confirm the active context:

```bash
kubectl config current-context
```

Then verify access to the cluster:

```bash
kubectl get nodes
```

The EKS managed nodes should appear once they have joined the cluster.

## 4. Verify the node groups

Check all nodes:

```bash
kubectl get nodes -o wide
```

Check the dedicated LLM nodes:

```bash
kubectl get nodes -l role=llm
```

To view labels:

```bash
kubectl get nodes --show-labels
```

The LLM nodes should have:

```text
role=llm
workload=llm
```

To check the taints:

```bash
kubectl describe node <llm-node-name>
```

Look for:

```text
workload=llm:NoSchedule
```

Ollama and Open WebUI use matching tolerations so they can run on these nodes.

## 5. Verify EKS add-ons

Check the cluster add-ons:

```bash
aws eks list-addons \
  --cluster-name "$(terraform output -raw cluster_name)"
```

The EBS CSI driver should be present.

You can also check its workloads from Kubernetes:

```bash
kubectl get pods -n kube-system | grep ebs
```

The EBS CSI controller and node components should be running before deploying workloads that require persistent volumes.

## 6. Create the GP3 StorageClass

Apply the StorageClass:

```bash
kubectl apply -f kubernetes/storage-class.yaml
```

Verify it:

```bash
kubectl get storageclass
```

Then inspect the specific class:

```bash
kubectl get storageclass gp3-csi
```

Expected characteristics include:

```text
Provisioner: ebs.csi.aws.com
Volume type: gp3
Filesystem: ext4
Volume binding: WaitForFirstConsumer
Expansion: enabled
```

Both Ollama and Open WebUI explicitly request this StorageClass.

## 7. Deploy the applications

The Helm configuration lives under:

```text
helm/
```

Ollama and Open WebUI are installed as separate Helm releases.

Follow:

```text
helm/README.md
```

for the application deployment commands.

After deployment, I normally check:

```bash
kubectl get pods -n llm
kubectl get svc -n llm
kubectl get pvc -n llm
```

The expected Helm releases are:

```text
ollama
open-webui
```

Check them with:

```bash
helm list -n llm
```

## 8. Verify workload placement

Check where the applications were scheduled:

```bash
kubectl get pods -n llm -o wide
```

Ollama and Open WebUI should run on nodes matching:

```text
role=llm
```

If a pod remains Pending, inspect it:

```bash
kubectl describe pod -n llm <pod-name>
```

I usually check scheduling before application logs because a container can't start correctly if Kubernetes hasn't found somewhere to run it.

## 9. Verify persistent storage

Check the PVCs:

```bash
kubectl get pvc -n llm
```

The claims should eventually become:

```text
Bound
```

If a PVC remains Pending:

```bash
kubectl describe pvc -n llm <pvc-name>
```

Then verify:

```bash
kubectl get storageclass gp3-csi
kubectl get pods -n kube-system | grep ebs
```

Things I check first are:

```text
StorageClass exists
EBS CSI components are healthy
pod has a schedulable node
AWS permissions are correct
PVC events do not show provisioning errors
```

Because the StorageClass uses `WaitForFirstConsumer`, volume provisioning is tied to workload scheduling.

## 10. Verify Ollama

Check the Ollama workload:

```bash
kubectl get pods -n llm
```

Check logs:

```bash
kubectl logs -n llm deployment/ollama -f
```

If the chart version generates a different workload name, find the actual pod first:

```bash
kubectl get pods -n llm
```

Then:

```bash
kubectl logs -n llm <ollama-pod-name> -f
```

The current configuration uses:

```text
llama3.2:1b
```

The model is intentionally CPU-friendly for this playground.

## 11. Verify Open WebUI to Ollama connectivity

Check the Ollama service:

```bash
kubectl get svc -n llm
```

Check its endpoints:

```bash
kubectl get endpoints -n llm ollama
```

Open WebUI is configured to reach Ollama through:

```text
http://ollama.llm.svc.cluster.local:11434
```

If Open WebUI cannot connect, I check the layers in this order:

```text
Ollama pod
   ↓
Ollama service
   ↓
service endpoints
   ↓
Kubernetes DNS
   ↓
Open WebUI configuration
```

Then check Open WebUI logs:

```bash
kubectl logs -n llm deployment/open-webui -f
```

## 12. Access Open WebUI

I don't expose Open WebUI publicly by default.

For local access:

```bash
kubectl port-forward -n llm svc/open-webui 8080:80
```

Then open:

```text
http://localhost:8080
```

If the chart created a different service name:

```bash
kubectl get svc -n llm
```

and port-forward the actual service.

## Troubleshooting

### Pod is Pending

Start with:

```bash
kubectl describe pod -n llm <pod-name>
```

Then check:

```bash
kubectl get nodes -l role=llm
kubectl get nodes --show-labels
```

I look for:

```text
missing role=llm label
taint/toleration mismatch
insufficient CPU or memory
PVC provisioning problems
unavailable Spot capacity
```

### Pod is restarting

Check current logs:

```bash
kubectl logs -n llm <pod-name>
```

For the previous container instance:

```bash
kubectl logs -n llm <pod-name> --previous
```

Also inspect events:

```bash
kubectl describe pod -n llm <pod-name>
```

### PVC is Pending

Run:

```bash
kubectl describe pvc -n llm <pvc-name>
kubectl get storageclass gp3-csi
kubectl get pods -n kube-system | grep ebs
```

The PVC events usually provide the fastest clue.

### Ollama service has no endpoints

Check:

```bash
kubectl get pods -n llm
kubectl get svc -n llm
kubectl get endpoints -n llm ollama
```

A service without endpoints usually means the selector isn't matching a healthy pod.

### Spot node disappeared

Because this environment uses Spot capacity, node interruption is expected.

Check:

```bash
kubectl get nodes
kubectl get pods -A -o wide
```

For this playground I accept that risk.

For a production environment I would add interruption handling and a more resilient capacity strategy.

## Useful checks

Cluster:

```bash
kubectl cluster-info
kubectl get nodes
```

Applications:

```bash
kubectl get pods -n llm
kubectl get svc -n llm
kubectl get pvc -n llm
```

Events:

```bash
kubectl get events -n llm --sort-by=.lastTimestamp
```

Helm:

```bash
helm list -n llm
helm status ollama -n llm
helm status open-webui -n llm
```

Terraform:

```bash
terraform output
terraform state list
```

## Cleanup

I remove the application layer before destroying the AWS infrastructure.

First uninstall Open WebUI:

```bash
helm uninstall open-webui -n llm
```

Then Ollama:

```bash
helm uninstall ollama -n llm
```

Check for persistent volume claims:

```bash
kubectl get pvc -n llm
```

Helm may leave them intentionally.

If I want to permanently remove the stored model and application data:

```bash
kubectl delete pvc --all -n llm
```

I only run that when I know I no longer need the data.

Then remove the namespace:

```bash
kubectl delete namespace llm
```

Finally, from the repository root:

```bash
terraform plan -destroy
```

Review the plan, then:

```bash
terraform destroy
```

I verify the AWS resources are gone afterward rather than assuming a successful command means every dependency disappeared cleanly.

## Notes

This environment is intentionally optimized for experimentation rather than availability.

That affects several decisions in the repo, especially:

```text
Spot capacity
single-node groups
CPU-only inference
single application replicas
local port forwarding
limited external exposure
```

Those are useful trade-offs for a playground, but they should not be copied blindly into a production design.

