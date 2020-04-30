#!/bin/sh
set -e

GITHUB_OWNER="${GITHUB_REPOSITORY%%/*}"
GITHUB_PROJECT="${GITHUB_REPOSITORY##*/}"

##
# Utility functions
error() { echo "error: $*" >&2; }
die() { error "$*"; exit 1; }
toupper() { echo "$*" | tr '[a-z]' '[A-Z]'; }
tolower() { echo "$*" | tr '[A-Z]' '[a-z]'; }

if test "${INPUT_DEBUG}" = 'true'; then
	set -x
	: '## Args'
	: "$@"
	: '## Inputs'
	set +x
	env|grep '^INPUT'
	set -x
fi

: 'Generating terraform.tf'
cat<<EOF>terraform.tf
terraform {
	backend "s3" {
		encrypt = true
		region = "${AWS_REGION}"
		bucket = "${INPUT_REMOTE_STATE_BUCKET}"
		key = "${GITHUB_PROJECT}/remote.tfstate"
		dynamodb_table = "${INPUT_REMOTE_STATE_TABLE}"
       }
}
EOF

: 'Generating terraform.auto.tfvars'
tfvars()
{
	# Run in a function so we can use the functions argument array
	env|grep ^INPUT|while read INPUT; do
		set -- "${INPUT%%=*}" "${INPUT#*=}"
		printf '%s = "%s"\n' "$(tolower "${1##INPUT_}")" "${2}"
	done
}
if ! test -f 'terraform.auto.tfvars'; then
       	printf 'name = "%s"\n' "${GITHUB_PROJECT}" > 'terraform.auto.tfvars'
fi
tfvars >> 'terraform.auto.tfvars'

# Allow overriding our entrypoint for debugging/development purposes
test "$#" -eq '0' || exec "$@"

: 'Initializing Terraform'
terraform init
terraform workspace new prod  > /dev/null 2>&1 || :
terraform workspace new stage > /dev/null 2>&1 || :
terraform workspace new qa    > /dev/null 2>&1 || :
terraform workspace new dev   > /dev/null 2>&1 || :
terraform workspace select "${INPUT_WORKSPACE:=default}"
terraform init -reconfigure

# The above `exec` prevents us from reaching this code if the ENTRYPOINT was specified
: Terraform Plan
terraform plan \
	-input=false \
	-compact-warnings

exit 0 # FIXME Temporarily skip apply until the action is cleaned up

: Terraform Apply
terraform apply \
	-input=false \
	-compact-warnings \
	-auto-approve \
	${INPUT_ARGS}
