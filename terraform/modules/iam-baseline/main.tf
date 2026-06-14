# Module IAM baseline — moindre privilège.
# Skeleton à compléter.

variable "environment" { type = string }

# TODO: rôles scopés par fonction (pas de politique "*:*").
# TODO: fédération OIDC pour le CI/CD (pas de clés d'accès statiques long-terme).
# TODO: politique de mot de passe / MFA obligatoire.
# TODO: séparation des privilèges de déchiffrement KMS.
