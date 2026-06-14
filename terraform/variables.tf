variable "aws_region" {
  type        = string
  description = "Région AWS de déploiement du socle."
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  type        = string
  description = "Plage CIDR du VPC. Garde-la étroite — pas de /8 fourre-tout."
}

variable "environment" {
  type        = string
  description = "Nom de l'environnement (prod, staging...)."
}
