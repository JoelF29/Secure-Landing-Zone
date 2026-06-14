package main

# Garde-fou policy-as-code : refuse tout Security Group ouvert au monde entier.
# Testé en CI via `conftest test terraform --policy policies/opa`.

deny[msg] {
    resource := input.resource.aws_security_group_rule[name]
    resource.type == "ingress"
    resource.cidr_blocks[_] == "0.0.0.0/0"
    msg := sprintf("Security group rule '%s' autorise un ingress depuis 0.0.0.0/0 — interdit (Zero Trust).", [name])
}
