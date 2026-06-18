# Composition du socle à partir des modules. Chaque module est durci par défaut.

module "network" {
  source      = "./modules/network"
  vpc_cidr    = var.vpc_cidr
  environment = var.environment
  azs         = var.azs
  # Principe Zero Trust : aucun ingress public n'est passé ici par défaut.
}


module "iam_baseline" {
  source      = "./modules/iam-baseline"
  environment = var.environment
  github_org  = var.github_org
  github_repo = var.github_repo
}
