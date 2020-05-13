#!/bin/sh
set -e

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
fi

test -n "${INPUT_REGION:=${AWS_DEFAULT_REGION}}" || die 'region unset'
echo "::set-env name=AWS_DEFAULT_REGION::${INPUT_REGION}"

test -n "${INPUT_WORKSPACE:=${TF_WORKSPACE}}" || die 'workspace unset'
echo "::set-env name=TF_WORKSPACE::${INPUT_WORKSPACE}"
echo '::set-env name=TF_IN_AUTOMATION::true'
export TF_WORKSPACE=

test -n "${INPUT_REMOTE_STATE_BUCKET:=${REMOTE_STATE_BUCKET}}" || die 'remote_state_bucket unset'
echo "::set-env name=REMOTE_STATE_BUCKET::${INPUT_REMOTE_STATE_BUCKET}"

test -n "${INPUT_REMOTE_LOCK_TABLE:=${REMOTE_LOCK_TABLE}}" || die 'remote_lock_table unset'
echo "::set-env name=REMOTE_LOCK_TABLE::${INPUT_REMOTE_LOCK_TABLE}"

GITHUB_OWNER="${GITHUB_REPOSITORY%%/*}"
export GITHUB_OWNER
echo "::set-env name=GITHUB_OWNER::${GITHUB_OWNER}"

GITHUB_PROJECT="${GITHUB_REPOSITORY##*/}"
export GITHUB_PROJECT
echo "::set-env name=GITHUB_PROJECT::${GITHUB_PROJECT}"
export INPUT_NAME="${GITHUB_PROJECT}"

##
# Attempt to track multiple invocations of the same action
GITHUB_ACTION_INSTANCE="${GITHUB_ACTION_INSTANCE:=${GITHUB_ACTION}_0}"
GITHUB_ACTION_INSTANCE="${GITHUB_ACTION}_$((${GITHUB_ACTION_INSTANCE##*_} + 1))"
export GITHUB_ACTION_INSTANCE
echo "::set-env name=GITHUB_ACTION_INSTANCE::${GITHUB_ACTION_INSTANCE}"

: 'Generating terraform.tf'
cat<<EOF>terraform.tf
terraform {
	backend "s3" {
		encrypt = true
		region = "${AWS_DEFAULT_REGION}"
		bucket = "${INPUT_REMOTE_STATE_BUCKET}"
		key="${GITHUB_REPOSITORY}/${GITHUB_ACTION_INSTANCE}"
		dynamodb_table = "${INPUT_REMOTE_LOCK_TABLE}"
       }
}
EOF

: 'Generating _action_inputs.tf'
tfvar_number() {
cat<<EOF
variable "${1}" {
	type = number
}
EOF
}
tfvar_string() {
cat<<EOF
variable "${1}" {
	type = string
}
EOF
}
tfvar_bool() {
cat<<EOF
variable "${1}" {
	type = bool
}
EOF
}
tfvars()
{
	echo "INPUTS:" >&2
	##
	# Override any TF_VAR_*'s via INPUT_*'s
	# We have to itterate this in the current shell-context in order to
	# export the new values
	for key in $(env|grep '^INPUT_'|cut -d= -f1); do
		test "${key}" != 'workspace' || continue
		eval export "TF_VAR_$(tolower "${key#INPUT_}")='$(eval echo "\$${key}")'"
	done

	##
	# Itterate all TF_VAR settings into Terraform variable's on stdout
	env|grep ^TF_VAR|while read TF_VAR; do
                set -- "${TF_VAR%%=*}" "${TF_VAR#*=}"
                set -- "${1#TF_VAR_}" "${2}"
		if test "${1}" = 'workspace'; then
			continue
		elif regexp '^[0-9]+$' "${2}"; then
			tfvar_number "${1}"
		elif test "${2}" = 'true'; then
			tfvar_bool "${1}"
		elif test "${2}" = 'false'; then
			tfvar_bool "${1}"
		else
			tfvar_string "${1}"
		fi
	done
}

# Allow overriding our entrypoint for debugging/development purposes
test "$#" -eq '0' || exec "$@"

: 'Initializing Terraform'
cleanup() { rm -rf .terraform .terraform.tfstate.d .terraform.d; }
trap cleanup 0
terraform init
terraform workspace new prod  > /dev/null 2>&1 || :
terraform workspace new stage > /dev/null 2>&1 || :
terraform workspace new qa    > /dev/null 2>&1 || :
terraform workspace new dev   > /dev/null 2>&1 || :
terraform workspace select "${INPUT_WORKSPACE:=default}"

tfvars > _action_tfvars.tf
terraform init -reconfigure

# The above `exec` prevents us from reaching this code if the ENTRYPOINT was specified
: Terraform Plan
terraform plan \
	-input=false \
	-compact-warnings

if test "${INPUT_DESTROY}" = 'true'; then
	: Terraform Destroy
	terraform destroy \
		-input=false \
		-compact-warnings \
		-auto-approve \
		${INPUT_ARGS}
else
	: Terraform Apply
	terraform apply \
		-input=false \
		-compact-warnings \
		-auto-approve \
		${INPUT_ARGS}
fi

# Produce our Outputs
tf_json()
{
	: _tf_json: "${@}"
	if test -z "${TERRAFORM_JSON}"; then
		export TERRAFORM_JSON="$(terraform output -json)"
	fi
	echo "${TERRAFORM_JSON}"
}
tf_keys()
{
	: _tf_keys: "${@}"
	tf_json | jq -rc ".${1#.}|keys|.[]"
}
tf_get()
{
	: _tf_get: "${@}"
	tf_json | jq -rc ".${1#.}"
}
tf_out()
{
	: _tf_out: "${@}"
	_tf_get_key="${1}"
	shift
	while test "$#" -gt '0'; do
		echo "::set-output name=${_tf_get_key}_${1}::$(tf_get "${_tf_get_key}.value[\"${1}\"]")"
		echo "::set-env name=TF_VAR_${_tf_get_key}_${1}::$(tf_get "${_tf_get_key}.value[\"${1}\"]")"
		shift 1
	done
}
tf_each()
{
	: _tf_each: "${@}"
	while test "$#" -gt '0'; do
		if test "${1}" = "type" || test "${1}" = "value"; then
			shift
			continue
		fi
		if test "$(tf_get "${1}.sensitive")" = 'true'; then
			shift
			continue
		fi
		if test "$(tf_get "${1}.type[0]")" != 'map' ; then
			tf_each $(tf_keys "${1}")
		fi
		tf_out "${1}" $(tf_keys "${1}.value")
		shift
	done
}

export TERRAFORM_JSON="$(terraform output -json)"
tf_each $(tf_keys)
