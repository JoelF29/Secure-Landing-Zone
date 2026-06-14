.PHONY: init scan plan apply destroy fmt

TF_DIR := terraform

fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

init:
	terraform -chdir=$(TF_DIR) init

# Garde-fous de sécurité : doivent passer AVANT tout déploiement
scan:
	checkov -d $(TF_DIR) --quiet
	tfsec $(TF_DIR)
	gitleaks detect --no-banner --source .
	conftest test $(TF_DIR) --policy policies/opa

plan:
	terraform -chdir=$(TF_DIR) plan -var-file=environments/prod/terraform.tfvars

apply:
	terraform -chdir=$(TF_DIR) apply -var-file=environments/prod/terraform.tfvars

destroy:
	terraform -chdir=$(TF_DIR) destroy -var-file=environments/prod/terraform.tfvars
