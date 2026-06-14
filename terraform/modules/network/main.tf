# Module réseau — Zero Trust networking (TON EDGE : exploite ta spé réseau/télécom).
# Skeleton à compléter. Les commentaires indiquent les décisions de sécurité attendues.

variable "vpc_cidr"    { type = string }
variable "environment" { type = string }

# TODO: VPC avec flow logs activés (traçabilité du trafic).
# TODO: sous-réseaux PRIVÉS par défaut ; sous-réseaux publics = exception justifiée.
# TODO: pas de Security Group autorisant 0.0.0.0/0 en entrée.
# TODO: VPC Endpoints / PrivateLink pour les services managés (pas de trafic Internet).
# TODO: NACLs restrictives + segmentation Est-Ouest (micro-segmentation).
# TODO (bonus seniors): peering/Transit Gateway avec routes minimales nécessaires.

output "vpc_id" {
  description = "ID du VPC du socle."
  value       = null # remplacer par aws_vpc.this.id
}
