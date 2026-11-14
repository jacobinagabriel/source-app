#!/usr/bin/env bash
# Checks the contract the bench repo reads (docs/PLAN.md, "Contract v3"): every
# parameter exists under /source-app/<env>/ and the values make sense.
# Needs AWS credentials (e.g. AWS_PROFILE) for the account.
set -euo pipefail

ENV=${ENV:-prod}
prefix="/source-app/$ENV"

aws ssm get-parameters-by-path --path "$prefix" --recursive --output json \
  | python3 -c '
import json, sys

prefix = sys.argv[1]
params = {p["Name"].removeprefix(prefix + "/"): p["Value"] for p in json.load(sys.stdin)["Parameters"]}

required = [
    "contract_version", "vpc_id", "private_subnet_ids", "public_subnet_ids",
    "db_cluster_arn", "db_cluster_id", "db_endpoint", "db_reader_endpoint", "db_port",
    "db_name", "db_schema", "db_engine", "db_engine_version", "db_security_group_id",
    "db_admin_secret_arn", "db_app_secret_arn", "schema_version",
    "logical_replication_enabled", "db_cluster_parameter_group_name",
    "db_max_replication_slots", "db_multi_az", "ecs_cluster_name", "image_tag",
]
failures = [f"missing {name}" for name in required if name not in params]

def check(ok, message):
    if not ok:
        failures.append(message)

if not failures:
    version, engine = params["db_engine_version"], params["db_engine"]
    major, minor = (int(x) for x in version.split(".")[:2])
    check(params["contract_version"] == "3", "contract_version is not 3")
    check(engine == "aurora-postgresql", f"db_engine is {engine}")
    check((major, minor) >= (17, 4), f"db_engine_version {version} is below 17.4 (zero-ETL)")
    check(params["logical_replication_enabled"] == "true", "logical replication is off")
    check(params["schema_version"] != "none", "schema_version not recorded: run the deploy workflow")
    check(len(params["private_subnet_ids"].split(",")) >= 2, "fewer than 2 private subnets")
    check(params["db_cluster_arn"].startswith("arn:aws:rds:"), "db_cluster_arn is not an RDS ARN")

for name in sorted(params):
    print(f"{name:34} {params[name]}")
if failures:
    print("\nFAIL: " + "; ".join(failures))
    sys.exit(1)
print(f"\ncontract {prefix} ok")
' "$prefix"
