variable "aws_region" {
  type        = string
  description = "Région AWS de déploiement du socle."
  default     = "eu-west-3"
}

variable "azs" {
  type        = list(string)
  description = "Liste des zones de disponibilité à utiliser pour le VPC."
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "vpc_cidr" {
  type        = string
  description = "Plage CIDR du VPC. Garde-la étroite, pas de /8 fourre-tout."
}

variable "environment" {
  type        = string
  description = "Nom de l'environnement (prod, staging...)."
}
