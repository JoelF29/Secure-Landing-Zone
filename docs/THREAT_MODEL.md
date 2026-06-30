# Threat Model — Secure Multi-Cloud Landing Zone (Projet 1)

> Modèle de menace de la **fondation** : state, réseau, identité, chiffrement, audit et pipeline de déploiement. Les menaces de couche applicative et runtime (WAF, conteneurs) sont traitées dans les Projets 2 à 4.
>
> **À personnaliser :** chaque ligne ci-dessous décrit *ton* architecture. Relis-la, confirme qu'elle correspond à ton implémentation réelle, et assure-toi de pouvoir **défendre chaque contrôle à l'oral**. Un threat model que tu ne sais pas expliquer ne vaut rien en entretien.

---

## 1. Périmètre (scope)

**Couvert :** backend de state Terraform (S3), VPC segmenté 3 tiers + routing + NACL + SG + VPC endpoints + flow logs, baseline IAM, fédération OIDC GitHub↔AWS, rôles plan/apply, clé KMS, CloudTrail, AWS Config, pipeline CI/CD GitOps.

**Hors périmètre (assumé par d'autres projets ou couches) :** vulnérabilités applicatives (Projet 2 — SAST/DAST), sécurité runtime des conteneurs (Projet 3), WAF/protection applicative en périmètre (workload futur), sécurité physique et du substrat AWS (responsabilité du fournisseur).

**Hypothèses :** compte AWS unique dédié au projet ; root protégé par MFA ; les workloads (RDS, Fargate) seront déployés dans les tiers déjà segmentés.

---

## 2. Frontières de confiance (trust boundaries)

1. **Internet ↔ plateforme** — tout trafic entrant est non fiable par défaut.
2. **Tier public ↔ tier app ↔ tier data** — chaque tier est une zone de confiance distincte ; le franchissement est explicitement contrôlé.
3. **GitHub Actions ↔ AWS** — un système externe (le CI) obtient un accès temporaire à AWS via une identité fédérée.
4. **Développeur ↔ pipeline** — un humain propose des changements (PR) mais ne déploie pas directement ; le pipeline est l'autorité de déploiement.

---

## 3. Actifs à protéger

| Actif | Pourquoi c'est critique |
|---|---|
| State Terraform | Contient l'état de toute l'infra et parfois des secrets en clair. |
| Clé KMS (CMK) | Compromise = déchiffrement de tout ce qu'elle protège. |
| Rôles IAM (apply) | Le droit de modifier l'infra. |
| Logs d'audit (CloudTrail) | Si altérés, plus aucune investigation possible. |
| Tier data (futur RDS) | La donnée elle-même, l'objectif final d'un attaquant. |

---

## 4. Profils d'attaquant

- **Opportuniste externe** — scanne Internet à la recherche de ressources mal configurées (bucket public, port ouvert).
- **Ciblé externe** — vise spécifiquement ton compte (vol de credentials, exploitation d'un service exposé).
- **Chaîne d'approvisionnement** — une dépendance ou une Action GitHub compromise tente de pivoter vers AWS.
- **Vol d'identité** — un secret ou une clé qui fuite donne un accès illégitime.

---

## 5. Analyse par chemin d'attaque (objectif → technique → contrôle → STRIDE)

| Objectif de l'attaquant | Technique | Contrôle en place (où, quel lab) | STRIDE | Risque résiduel |
|---|---|---|---|---|
| Trouver une cible exposée | Scan de ports/services Internet | Tiers app & data privés, aucun ingress `0.0.0.0/0` sur les SG ; seul le futur LB sera exposé (Lab 02) | I / S | Faible |
| Atteindre directement la base | Accès réseau au tier data | Tier data sans route `0.0.0.0/0` : inatteignable depuis Internet *par construction* (Lab 02) | I | Très faible |
| Voler des credentials de déploiement | Exfiltrer une clé statique du CI | **Aucune clé statique** : OIDC, jetons temporaires ~1 h (Lab 03) | S | Faible |
| Détourner le rôle de déploiement | Faire assumer le rôle depuis un autre repo/fork | Deux rôles distincts : `plan` (lecture seule, trust policy scopée à `pull_request`) et `apply` (écriture, scopé à `ref:refs/heads/main`) — un fork ou une branche non autorisée ne peut assumer ni l'un ni l'autre (Lab 03/05) | E | Faible |
| Déployer du code malveillant | Pousser une config dangereuse | Gates bloquants (Checkov/tfsec/gitleaks/OPA) sur PR + revue humaine + approbation d'environnement avant apply (Lab 05) | T | Faible–moyen |
| Mouvement latéral après compromission | Pivoter d'un service à l'autre | Micro-segmentation : SG référencés par ID, NACL stateless deny-by-default (Lab 02) | E | Moyen |
| Exfiltrer la donnée | Sortir les données vers Internet | Egress contrôlé (NAT pour app uniquement), data sans route sortante, trafic AWS via VPC endpoints privés (Lab 02) | I | Faible |
| Lire les secrets au repos | Accéder au state ou aux volumes | Chiffrement KMS (CMK avec rotation), state en bucket durci, secrets jamais en clair — gitleaks en CI (Lab 01/04/05) | I | Faible |
| Effacer ses traces | Altérer/supprimer les logs | CloudTrail multi-région + **validation d'intégrité** (tamper-evident), logs chiffrés en bucket durci versionné (Lab 04) | R | Faible |
| Maintenir un accès furtif | Modifier la conf sans être vu | CloudTrail journalise tout appel d'API ; AWS Config détecte la dérive de baseline (Lab 04) | R / T | Moyen |

> *Remplace les niveaux de « risque résiduel » par ton propre jugement après avoir terminé l'implémentation — c'est l'exercice qui te fait penser comme un défenseur.*

---

## 6. Le parcours d'un attaquant (narration)

Un attaquant scanne Internet : il ne voit rien d'exploitable, tout est privé. S'il franchissait un jour le périmètre applicatif (futur WAF/LB), il tomberait sur la segmentation : un conteneur compromis ne peut pas se déplacer latéralement (SG par ID), son rôle IAM minimal limite le rayon de souffle, et surtout — il ne peut **rien exfiltrer**, car le tier data n'a aucune route vers Internet. En parallèle, chacun de ses gestes est journalisé dans un CloudTrail infalsifiable. Et il ne peut pas non plus passer par le pipeline : sans clé statique à voler, et avec un rôle de déploiement scopé à la branche `main` derrière une revue humaine, la voie CI/CD est fermée.

---

## 7. Risques résiduels & travaux futurs (l'honnêteté = maturité)

Le moindre privilège du rôle `apply` reste perfectible (Terraform exige des droits larges) — piste : permissions boundary stricte, séparation plan/apply déjà en place. Pas encore de WAF ni de protection applicative (workload pas déployé — Projet futur). Sécurité runtime des conteneurs non couverte (Projet 3). Compte unique : une architecture multi-comptes (Organizations) renforcerait l'isolation en prod. Détection encore passive : les alarmes temps réel et l'auto-remédiation arrivent au Projet 4.

Savoir énoncer ces limites **sans qu'on te les demande** est précisément ce qui distingue un ingénieur sécurité d'un exécutant.

