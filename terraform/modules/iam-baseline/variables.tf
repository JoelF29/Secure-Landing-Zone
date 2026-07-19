variable "environment" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "enable_access_analyzer" {
  type        = bool
  default     = true
  description = "Active l'IAM Access Analyzer. À désactiver uniquement pour les environnements de test où ce service n'est pas émulé (ex: LocalStack)."
}