# Lab 02 — Module réseau VPC sécurisé (Zero Trust networking)

> **Objectif :** construire toi-même le cœur de ta plateforme : un VPC segmenté en 3 tiers sur 2 zones de disponibilité, où l'isolation se prouve par l'**absence de route**, pas par un firewall qu'on peut contourner. C'est le projet où ton ADN réseau/télécom fait la différence.

**Durée estimée :** 4 – 6 h (étalées sur plusieurs sessions, un commit par brique).
**Prérequis :** Lab 01 terminé (backend de state S3 opérationnel, `terraform init` migré). Tu travailles désormais dans `terraform/modules/network/`.

---

## Comment utiliser ce document avec Claude Code

Même principe que le Lab 01 : Claude Code est ton **coach**, pas ton solveur. Reprends la consigne « guide-moi, ne code pas à ma place, ne révèle la référence que si je bloque ». La différence ici : le réseau a beaucoup de pièces interconnectées, donc valide chaque brique (`terraform plan`) **avant** de passer à la suivante.

---

## Partie 0 — Ce qu'on construit, et pourquoi

**La cible :** un VPC avec trois tiers, chacun réparti sur deux AZ pour la résilience.

| Tier | Rôle | Accès Internet |
|---|---|---|
| **public** | uniquement le load balancer (Lab futur) | entrant via Internet Gateway |
| **app** | les conteneurs (Lab 03) | sortant seulement, via NAT |
| **data** | la base de données (Lab futur) | **aucun** — isolé total |

**Les 3 principes Zero Trust networking à incarner :**

1. **Isolation par l'absence de route.** Le tier data n'a littéralement aucune route vers `0.0.0.0/0`. Même si un attaquant compromet la base, il ne peut rien exfiltrer : il n'y a pas de chemin. C'est plus fort qu'un firewall.
2. **Defense in depth.** Deux couches complémentaires : les NACLs (niveau sous-réseau, *stateless*, première barrière) **et** les Security Groups (niveau ressource, *stateful*, moindre privilège).
3. **Micro-segmentation Est-Ouest.** Les Security Groups se référencent **entre eux par leur ID**, jamais par un CIDR large. « Le SG de la base accepte le port 5432 uniquement depuis le SG de l'app » — pas depuis une plage d'adresses.

> Garde le schéma d'architecture (`docs/architecture.svg`) sous les yeux pendant tout le lab : c'est le plan que tu construis.

---

## Le primer qui compte : planifier tes CIDR

Avant d'écrire la moindre ressource, tu dois **planifier ton adressage**. C'est exactement là que ton background réseau te distingue : la plupart des candidats balancent un `/16` au hasard. Toi, tu découpes proprement.

Pour un VPC en `10.20.0.0/20` (4096 adresses), tu peux tailler 16 sous-réseaux `/24` avec la fonction `cidrsubnet`. Avec 3 tiers × 2 AZ = 6 sous-réseaux, tu as de la marge pour grandir.

`cidrsubnet("10.20.0.0/20", 4, n)` ajoute 4 bits (→ des `/24`) et renvoie le n-ième bloc : `n=0` → `10.20.0.0/24`, `n=1` → `10.20.1.0/24`, etc.

Tu **n'écriras pas** ces 6 CIDR à la main : tu les **calcules** dans un bloc `locals` avec une boucle. C'est le signal de maturité (ajouter un tier ou une AZ ne casse rien).

---

## Partie 1 — Construction, brique par brique (= tes commits)

### Étape 1 — Variables, validation et locals

**Pourquoi :** poser les entrées propres dès le départ, et calculer l'adressage par code.

**Ta mission (a) — variables avec garde-fous.** Dans `variables.tf`, déclare `vpc_cidr`, `environment`, et une liste `azs`. Ajoute des blocs `validation` : refuser un CIDR trop large (un `/8` n'a rien à faire ici) et **refuser explicitement** `0.0.0.0/0` comme `vpc_cidr`.

**Indice :** un bloc `validation { condition = ... error_message = ... }` dans la variable. Pour tester le préfixe, `split("/", var.vpc_cidr)[1]` te donne la taille du masque.

**Ta mission (b) — le calcul des sous-réseaux.** Dans `main.tf` (ou un `locals.tf`), construis une map `tier-az → { tier, az, cidr }`.

**Vérifie-toi (référence — après essai) :** voici le pattern `for_each` à comprendre, pas juste à copier :

```hcl
locals {
  tiers = { public = 0, app = 1, data = 2 } # ordre = position dans l'adressage

  subnets = {
    for pair in setproduct(keys(local.tiers), range(length(var.azs))) :
    "${pair[0]}-${var.azs[pair[1]]}" => {
      tier = pair[0]
      az   = var.azs[pair[1]]
      cidr = cidrsubnet(var.vpc_cidr, 4, local.tiers[pair[0]] * length(var.azs) + pair[1])
    }
  }
}
```

Demande à Claude Code de t'expliquer **chaque ligne** (`setproduct`, le calcul de l'index `cidr`) jusqu'à ce que tu puisses la réécrire seul. C'est ça, l'apprentissage.

---

### Étape 2 — Le VPC + DNS + Flow Logs

**Pourquoi :** on active la **traçabilité dès la première ressource**. Les flow logs alimenteront ton Projet 4 (détection). « Log first » est un réflexe de défenseur.

**Ta mission :** crée le `aws_vpc` (avec `enable_dns_support` et `enable_dns_hostnames`), puis active les **VPC Flow Logs** vers un groupe de logs CloudWatch.

**Indice :** `aws_vpc`, puis `aws_cloudwatch_log_group`, un `aws_iam_role` (que le service VPC Flow Logs peut assumer) et `aws_flow_log` (avec `traffic_type = "ALL"`). C'est plusieurs ressources liées — fais-toi expliquer la chaîne par Claude Code.

**Vérifie-toi :**
```bash
terraform plan   # doit montrer le VPC + le flow log + le log group
```

→ **commit :** `feat(network): VPC with DNS and flow logs`

---

### Étape 3 — Les sous-réseaux (3 tiers × 2 AZ)

**Pourquoi :** matérialiser la segmentation.

**Ta mission :** crée les sous-réseaux avec `for_each = local.subnets`. Chaque sous-réseau prend son `cidr_block` et son `availability_zone` depuis la map. Les sous-réseaux publics seulement peuvent recevoir `map_public_ip_on_launch = true` (et encore, on évite — le LB s'en charge).

**Indice :** `resource "aws_subnet" "this" { for_each = local.subnets ... }`, et `each.value.tier` / `each.value.az` / `each.value.cidr`. Ajoute un tag `Tier = each.value.tier` (utile plus tard pour la gouvernance et le CSPM).

**Vérifie-toi :** `terraform plan` doit annoncer **6 sous-réseaux**. Vérifie que les CIDR ne se chevauchent pas.

→ **commit :** `feat(network): subnets across 3 tiers and 2 AZ`

---

### Étape 4 — Le routing (LA brique de sécurité)

**Pourquoi :** c'est ici que se joue l'isolation. **L'absence de route est ta meilleure protection.**

**Ta mission, dans l'ordre :**
- une **Internet Gateway** attachée au VPC ;
- une table de routes **publique** avec une route `0.0.0.0/0 → IGW`, associée aux sous-réseaux **public** ;
- un **NAT Gateway** (dans un sous-réseau public, avec une EIP) ;
- une table de routes **app** avec une route `0.0.0.0/0 → NAT`, associée aux sous-réseaux **app** ;
- une table de routes **data** **SANS aucune route `0.0.0.0/0`**, associée aux sous-réseaux **data**.

**Indice :** `aws_internet_gateway`, `aws_eip`, `aws_nat_gateway`, `aws_route_table`, `aws_route`, `aws_route_table_association`.

**Le point critique :** la table data ne contient QUE la route locale implicite du VPC. Tu n'écris aucun `aws_route` vers l'extérieur pour elle. Vérifie-le deux fois.

**Garde-fou coût ⚠️ :** le NAT Gateway est l'élément le plus cher (~30 $/mois + le trafic). Pour un projet d'apprentissage, crée **un seul** NAT partagé (au lieu d'un par AZ). En entretien, sache dire le compromis : « un NAT par AZ pour la haute dispo en prod, un seul ici pour le coût ». Et `terraform destroy` en fin de session.

**Vérifie-toi (après apply) :**
```bash
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<ton-vpc>" \
  --query "RouteTables[].Routes[].DestinationCidrBlock"
# la table du tier data ne doit JAMAIS faire apparaître 0.0.0.0/0
```

→ **commit :** `feat(network): routing with isolated data tier (no internet route)`

---

### Étape 5 — Les NACLs (couche défense n°1, stateless)

**Pourquoi :** une barrière au niveau sous-réseau, *avant même* les Security Groups. Stateless = tu dois autoriser l'aller **et** le retour explicitement.

**Ta mission :** une NACL par tier, en *deny by default*, n'ouvrant que le strict nécessaire. La NACL data, par exemple, n'accepte d'entrée que depuis le CIDR du tier app, sur le port de la base.

**Indice :** `aws_network_acl` + `aws_network_acl_rule` (règles numérotées, pense aux ports éphémères `1024-65535` pour le trafic retour, puisque c'est stateless).

**Vérifie-toi :** `terraform plan`. Demande à Claude Code de te faire réfléchir aux ports retour — c'est le piège classique des NACL.

→ **commit :** `feat(network): tiered NACLs (stateless defense layer)`

---

### Étape 6 — Les Security Groups (micro-segmentation, stateful)

**Pourquoi :** la couche moindre privilège au niveau ressource. C'est ici que tu incarnes la micro-segmentation Est-Ouest.

**Ta mission :** un SG par tier. La règle d'or : **les SG se référencent entre eux par ID**. Exemple : le SG data autorise le port `5432` en entrée *uniquement depuis le SG app* — pas depuis un CIDR.

**Indice — pratique moderne :** utilise les ressources de règles dédiées `aws_vpc_security_group_ingress_rule` et `aws_vpc_security_group_egress_rule` (une règle = une ressource), avec `referenced_security_group_id` pour pointer un autre SG. C'est la façon recommandée aujourd'hui, plus lisible et auditable que les vieux blocs `ingress {}` inline ou `aws_security_group_rule`. Bon point à mentionner en entretien.

**Le réflexe à garder :** aucune règle entrante en `0.0.0.0/0` (ta politique OPA `deny_public_ingress.rego` du scaffold le vérifiera). L'egress aussi se restreint quand on peut.

**Vérifie-toi :** `terraform plan`, puis pousse — ta CI (Checkov + OPA) te dira immédiatement si un `0.0.0.0/0` a glissé.

→ **commit :** `feat(network): security groups with SG-to-SG micro-segmentation`

---

### Étape 7 — Les VPC Endpoints (connectivité privée, niveau senior)

**Pourquoi :** pour que le trafic du tier app vers les services AWS (S3, ECR, KMS…) ne sorte **jamais** sur Internet. Zero Trust appliqué à la connectivité — peu de juniors le posent.

**Ta mission :** deux types d'endpoints. Un endpoint **gateway** pour S3 (et DynamoDB), gratuit, attaché aux tables de routes. Des endpoints **interface** pour SSM, ECR (api + dkr), KMS, Secrets Manager, CloudWatch Logs, dans les sous-réseaux app, protégés par un SG dédié.

**Indice :** `aws_vpc_endpoint` avec `vpc_endpoint_type = "Gateway"` (et `route_table_ids`) ou `"Interface"` (et `subnet_ids` + `security_group_ids` + `private_dns_enabled = true`).

> ⚠️ Les endpoints interface sont facturés à l'heure : pour apprendre, commence par S3 (gateway, gratuit) + un seul interface, et `destroy` après.

→ **commit :** `feat(network): private connectivity via VPC endpoints`

---

### Étape 8 — Outputs propres

**Pourquoi :** les autres modules (compute, data) consommeront ces valeurs. Un module bien outillé expose ce qu'il faut, ni plus ni moins.

**Ta mission :** dans `outputs.tf`, expose `vpc_id`, et les ids de sous-réseaux **groupés par tier** (les modules suivants en auront besoin), plus les ids des SG.

**Indice :** filtre ta map, ex. `app_subnet_ids = [for k, v in aws_subnet.this : v.id if local.subnets[k].tier == "app"]`.

---

### Étape 9 — Valider, déployer, vérifier

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply       # relis le plan avant "yes"
```

Puis déroule les vérifications des étapes 4 et 6. **La plus importante** : confirme que le tier data n'a aucune route Internet.

> **Rappel coût :** `terraform destroy` en fin de session. NAT Gateway + endpoints interface tournent au compteur.

---

## Auto-évaluation (réponds à l'oral, sans regarder)

1. Pourquoi l'isolation du tier data repose-t-elle sur l'absence de route plutôt que sur un Security Group ?
2. Quelle est la différence stateless / stateful entre NACL et Security Group, et pourquoi en a-t-on **deux** ?
3. Qu'est-ce que la micro-segmentation Est-Ouest, et comment l'implémente-t-on concrètement ?
4. Pourquoi calculer les CIDR avec `cidrsubnet` plutôt que les écrire à la main ?
5. Pourquoi un seul NAT ici, et que ferais-tu différemment en production ?

---

## Pièges courants

Oublier les ports éphémères de retour sur les NACL (le trafic part mais ne revient pas) → le piège n°1 du stateless. Mettre la route `0.0.0.0/0` sur la table data « pour que ça marche » → tu casses toute ta thèse de sécurité ; si un service du tier data a besoin d'un accès AWS, c'est via un VPC endpoint, pas via une route Internet. Créer un NAT par AZ sans le vouloir → facture qui grimpe. Référencer un SG par CIDR au lieu de son ID → tu perds la micro-segmentation. Oublier `terraform destroy` → NAT + endpoints qui tournent tout le week-end.

---

## Comment en parler en entretien

> « Mon VPC est segmenté en trois tiers sur deux AZ. Le tier data est isolé par construction : sa table de routes ne contient aucune route vers Internet, donc même une base compromise ne peut rien exfiltrer. J'ai une défense en profondeur avec NACL au niveau subnet et Security Groups au niveau ressource, et je fais de la micro-segmentation en référençant les SG entre eux par ID plutôt que par CIDR. Le trafic vers les services AWS passe par des VPC endpoints privés, jamais par Internet. Et mon adressage est calculé en code avec cidrsubnet, donc ajouter un tier ne casse rien. »

Cette réponse, c'est un profil qui *pense réseau ET sécurité* — exactement ton positionnement unique.

---

## Et après ?

Une fois le réseau debout, la suite logique est le **Lab 03 — containeriser et déployer sur Fargate** dans le tier app (image non-root, scannée, signée), branché sur les sous-réseaux et SG que tu viens de créer. En parallèle, c'est le bon moment pour rédiger le **THREAT_MODEL.md** : maintenant que l'architecture existe, tu peux documenter chaque chemin d'attaque et le contrôle qui le ferme.
