module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${local.name}"
  kubernetes_version = "1.36"
  enable_irsa        = true

  addons = {
    coredns = {}

    eks-pod-identity-agent = {
      before_compute = true
    }

    kube-proxy = {}

    vpc-cni = {
      before_compute = true
    }
  }

  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m7i-flex.large"]
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 1
      desired_size = 1

      bootstrap_extra_args = <<-EOT
        [settings.host-containers.admin]
        enabled = false

        [settings.host-containers.control]
        enabled = true

        [settings.kernel]
        lockdown = "integrity"
      EOT
    }

    llm = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m7i-flex.large"]
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 1
      desired_size = 1

      labels = {
        role     = "llm"
        workload = "llm"
      }

      taints = {
        llm = {
          key    = "workload"
          value  = "llm"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = local.tags
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.name}-ebs-csi-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn

      namespace_service_accounts = [
        "kube-system:ebs-csi-controller-sa"
      ]
    }
  }

  tags = local.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
}
