module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0" # or latest compatible

  role_name_prefix = "${local.name}-ebs-csi-"

  # This attaches the AWS-managed AmazonEBSCSIDriverPolicy
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      # This is the SA name the EKS addon uses by default
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

resource "kubernetes_storage_class_v1" "gp3_csi" {
  metadata {
    name = "gp3-csi"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner  = "ebs.csi.aws.com"
  reclaim_policy       = "Delete"
  volume_binding_mode  = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type  = "gp3"
    fsType = "ext4"
  }
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${local.name}-bottlerocket"
  kubernetes_version = "1.33"
  enable_irsa = true

  # EKS Addons
  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    aws-ebs-csi-driver = {
    most_recent = true
    service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
   }
  }

  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m7i-flex.large"]
      capacity_type = "SPOT"

      min_size = 1
      max_size = 1
      # This value is ignored after the initial creation
      # https://github.com/bryantbiggs/eks-desired-size-hack
      desired_size = 1

      # This is not required - demonstrates how to pass additional configuration
      # Ref https://bottlerocket.dev/en/os/1.19.x/api/settings/
      bootstrap_extra_args = <<-EOT
        [settings.host-containers.admin]
        enabled = false

        [settings.host-containers.control]
        enabled = true

        # extra args added
        [settings.kernel]
        lockdown = "integrity"
      EOT
    }

    llm = {
    ami_type       = "BOTTLEROCKET_x86_64"
    instance_types = ["m7i-flex.large"]  

    capacity_type  = "SPOT"         

    min_size       = 1
    max_size       = 1
    desired_size   = 1            

    labels = {
      "role"     = "llm"
      "workload" = "llm"
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