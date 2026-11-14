# The contract with the bench repo: everything it may rely on, under one SSM path.
# Values are identifiers and ARNs, never secrets (the secrets stay in Secrets Manager).

resource "aws_ssm_parameter" "this" {
  for_each = var.parameters
  #checkov:skip=CKV2_AWS_34:Identifiers and ARNs, not secrets.

  name  = "${var.prefix}/${each.key}"
  type  = "String"
  value = each.value
}

resource "aws_ssm_parameter" "list" {
  for_each = var.list_parameters
  #checkov:skip=CKV2_AWS_34:Identifiers, not secrets.

  name  = "${var.prefix}/${each.key}"
  type  = "StringList"
  value = join(",", each.value)
}

# The deploy workflow writes the Alembic revision after `migrate`. Terraform only
# creates the parameter, so destroy removes it with the rest of the contract.
resource "aws_ssm_parameter" "schema_version" {
  #checkov:skip=CKV2_AWS_34:An Alembic revision id, not a secret.
  name  = "${var.prefix}/schema_version"
  type  = "String"
  value = "none"

  lifecycle {
    ignore_changes = [value]
  }
}
