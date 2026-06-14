# Threat Model — Secure Multi-Cloud Landing Zone

Analyse STRIDE des composants principaux. À compléter au fur et à mesure que tu construis le socle.

## Périmètre

- Réseau (VPC/VNet, sous-réseaux, peering, connectivité privée)
- IAM (rôles, politiques, fédération d'identité)
- State Terraform (backend distant)
- Pipeline CI/CD

## STRIDE

| Composant | Menace (STRIDE) | Scénario | Contre-mesure |
|---|---|---|---|
| IAM | **S**poofing | Réutilisation de credentials longue-durée volés | Fédération OIDC, rôles temporaires, MFA, pas de clés statiques |
| Réseau | **T**ampering | Modification de flux Est-Ouest non chiffrés | Chiffrement en transit, network policies, segmentation |
| Logging | **R**epudiation | Action d'API non tracée | CloudTrail/Activity Logs centralisés + immuables |
| State TF | **I**nformation Disclosure | Secrets en clair dans le state | Backend chiffré, accès restreint, pas de secrets en clair |
| Plateforme | **D**enial of Service | Exposition publique d'un service | Pas d'ingress `0.0.0.0/0`, WAF, rate limiting |
| IAM | **E**levation of Privilege | Rôle trop permissif (`*:*`) | Moindre privilège, garde-fous OPA, revue automatisée |

## Hypothèses & limites

> _Documente ici ce que le modèle ne couvre pas (ex. sécurité physique du provider, menaces internes au cloud provider)._

## Références

- CIS Benchmarks (AWS / Azure)
- Cloud provider Well-Architected — pilier Sécurité
