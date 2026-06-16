variable "vpc_cidr" {
  type        = string
  description = "Plage CIDR du VPC. Garde-la étroite"
  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) >= 16 && var.vpc_cidr != "0.0.0.0/0"
    error_message = "La plage CIDR du VPC doit être d'au moins 16 bits (ex: /16)."
  }
}

variable "environment" {
  type        = string
  description = "Nom de l'environnement (prod, staging...)."
}

variable "azs" {
  type        = list(string)
  description = "Liste des zones de disponibilité à utiliser pour le VPC."
}