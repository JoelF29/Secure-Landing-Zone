# Secure Multi-Cloud Landing Zone

> Socle de plateforme cloud durci **par design**, déployé entièrement en Infrastructure-as-Code, avec une architecture réseau **Zero Trust** et des garde-fous *policy-as-code*. Zéro click-ops.

![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)
![Security](https://img.shields.io/badge/scan-Checkov%20%7C%20tfsec%20%7C%20Gitleaks-blue)
![Policy](https://img.shields.io/badge/policy--as--code-OPA%2FConftest-green)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF)

---

## Le problème

La plupart des environnements cloud sont montés à la main, sans baseline de sécurité reproductible : IAM trop permissif, réseaux à plat exposés sur `0.0.0.0/0`, logging incomplet, dérive de configuration impossible à auditer. Ce projet répond à une question simple : **« comment poser, en une commande, des fondations cloud que je peux prouver conformes ? »**

## Ce que ça fait

- **Réseau Zero Trust** : VPC/VNet segmentés, sous-réseaux privés par défaut, connectivité privée (PrivateLink / Private Endpoints), aucun flux entrant ouvert au monde sans justification explicite.
- **IAM en moindre privilège** : rôles scopés, pas d'utilisateurs longue-durée, séparation des environnements.
- **Chiffrement par défaut** : clés gérées (KMS / Key Vault), chiffrement au repos et en transit.
- **Observabilité de sécurité** : logging centralisé (CloudTrail / Activity Logs), traçabilité de toutes les actions d'API.
- **Garde-fous automatisés** : chaque `terraform plan` est scanné (Checkov, tfsec) et validé contre des politiques OPA avant tout merge.

## Architecture

![Architecture](docs/architecture.svg)

> _À compléter : remplace `docs/architecture.svg` par ton schéma (flux réseau, zones de confiance, comptes/abonnements). Un schéma clair vaut dix paragraphes pour un recruteur._

## Décisions de sécurité (le « pourquoi »)

| Décision | Justification |
|---|---|
| Sous-réseaux privés par défaut | Réduction de la surface d'attaque ; l'exposition publique est l'exception explicite, pas le défaut. |
| Pas d'ingress `0.0.0.0/0` | Principe Zero Trust : tout flux entrant est nommé et justifié. |
| Connectivité privée (PrivateLink) | Le trafic vers les services managés ne transite jamais par l'Internet public. |
| Chiffrement KMS géré | Rotation des clés et séparation des rôles de déchiffrement. |
| State chiffré + verrouillé (backend distant) | Empêche la fuite de secrets et les corruptions de state concurrentes. |

> Ce tableau est ce qui te distingue : il prouve que tu **raisonnes** sécurité, pas que tu empiles des ressources.

## Reproduire en une commande

```bash
# Pré-requis : Terraform >= 1.7, credentials cloud configurés en variables d'env
make init      # initialise le backend distant chiffré
make scan      # Checkov + tfsec + Gitleaks (doit passer avant tout déploiement)
make plan      # plan d'exécution
make apply     # déploie le socle
make destroy   # nettoie tout
```

## Structure du repo

```
.
├── terraform/
│   ├── providers.tf            # providers multi-cloud + backend distant chiffré
│   ├── main.tf                 # composition des modules
│   ├── variables.tf
│   ├── environments/prod/      # tfvars par environnement
│   └── modules/
│       ├── network/            # segmentation, Zero Trust networking
│       └── iam-baseline/       # rôles en moindre privilège
├── policies/opa/               # garde-fous policy-as-code (Rego)
├── .github/workflows/          # CI : scan sécurité bloquant
├── docs/                       # schémas d'architecture
├── THREAT_MODEL.md             # modèle de menace STRIDE
└── Makefile
```

## Modèle de menace

Voir [`THREAT_MODEL.md`](THREAT_MODEL.md) — analyse STRIDE des principaux composants et des contre-mesures associées.

## Résultats mesurables

> _À remplir au fil du projet — c'est ce qui fait basculer dans le top 1 % :_
> - `N` règles de configuration durcies vs. baseline par défaut
> - `0` finding critique Checkov/tfsec sur le `main`
> - `X` politiques OPA appliquées comme garde-fous bloquants

## Place dans le portfolio

Ce projet est le **socle** d'un portfolio Cloud Security en 4 volets :

1. **Secure Landing Zone** _(ce repo)_ — construire sûr
2. **DevSecOps CI/CD pipeline** — livrer sûr (déploie *sur* ce socle)
3. **Kubernetes hardening + runtime detection** — faire tourner sûr
4. **CSPM + auto-remédiation** — détecter, répondre, prouver la conformité (surveille *ce socle*)

## Licence

MIT
