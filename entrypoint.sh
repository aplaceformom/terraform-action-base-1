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
regexp() {
        : 'regexp():' "$@"
        awk "/${1}/{exit 0;}{exit 1;}" <<EOF
${2}
EOF
}

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

: 'Generating _action_inputs.tf'
tfvar_number() {
cat<<EOF
variable "${1}" {
	type = number
	default = ${2}
}
EOF
}
tfvar_string() {
cat<<EOF
variable "${1}" {
	type = string
	default = "${2}"
}
EOF
}
tfvar_bool() {
cat<<EOF
variable "${1}" {
	type = bool
	default = ${2}
}
EOF
}
tfvars()
{
	# Run in a function so we can use the functions argument array
	env|grep ^INPUT|while read INPUT; do
		set -- "${INPUT%%=*}" "${INPUT#*=}"
		set -- "$(tolower "${1#INPUT_}")" "${2}"
		if regexp '^[0-9]+$' "${2}"; then
			tfvar_number "${1}" "${2}"
		elif test "${2}" = 'true'; then
			tfvar_bool "${1}" "${2}"
		elif test "${2}" = 'false'; then
			tfvar_bool "${1}" "${2}"
		else
			tfvar_string "${1}" "${2}"
		fi
	done
}
export INPUT_NAME="${GITHUB_PROJECT}"
tfvars >> '_action_inputs.tf'

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
