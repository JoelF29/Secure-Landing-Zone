locals {
  tiers = {public = 0, app = 1, data = 2}

  subnets = {
    for pair in setproduct(keys(local.tiers), range(length(var.azs))) :
    "${pair[0]}-${var.azs[pair[1]]}" => {
      tier = pair[0]
      az   = var.azs[pair[1]]
      cidr = cidrsubnet(var.vpc_cidr, 4, local.tiers[pair[0]] * length(var.azs) + pair[1])
    }
  }
}
