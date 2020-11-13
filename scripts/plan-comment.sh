#!/usr/bin/env sh

set -e

GITHUB_COMMENT_URL=$(cat "${GITHUB_EVENT_PATH}" | jq --raw-output '.pull_request._links.comments.href // empty' )

echo "comment url: ${GITHUB_COMMENT_URL}"
echo "deployments url: ${DEPLOYMENTS_URL}"

mkdir -p .artifacts

set +e

terraform plan -input=false -detailed-exitcode -out ./.artifacts/terraform.plan

PLAN_EXIT_CODE=$?

if [ "${PLAN_EXIT_CODE}" -eq "0" ]; then
	# success with no changes
	echo "::set-output name=has_changes::false"
	exit 0
elif [ "${PLAN_EXIT_CODE}" -eq "2" ]; then
	# success with changes
	echo "::set-output name=has_changes::true"
	CHANGES_DESCRIPTION="has changes :yellow_circle:"
else
	# fail
	echo "terraform plan failed ${PLAN_EXIT_CODE}"
	exit ${PLAN_EXIT_CODE}
fi

set -e

form show -json ./.artifacts/terraform.plan > ./.artifacts/terraform.plan.json

PLAN_TEXT=$(terraform show ./.artifacts/terraform.plan -no-color )

GITHUB_COMMENT_TEXT=$( cat << END
<details>
<summary>
<b>${PROJECT_NAME} terraform plan</b>
${CHANGES_DESCRIPTION}
</summary>

\`\`\`
${PLAN_TEXT}
\`\`\`

</details>
END
)

if [ "${GITHUB_TOKEN}" != "" ]; then
	if [ "${GITHUB_COMMENT_URL}" != "" ]; then
		echo "adding comment to pull request"
		GITHUB_COMMENT_BODY=$( jq --null-input --arg body "${GITHUB_COMMENT_TEXT}" '{body:$body}' )
		CREATED_COMMENT=$( curl --silent --fail --request POST --url "${GITHUB_COMMENT_URL}" --header "authorization: Bearer ${GITHUB_TOKEN}" --data "${GITHUB_COMMENT_BODY}" )
	else
		STATUS_BODY=$( jq --null-input --arg context "Plan Approval ${PROJECT_NAME}" '{state:"pending", target_url:"https://www.google.com", description:"waiting for approval", context:$context }' )
		STATUS_URL=$( jq --arg url "${GITHUB_STATUSES_URL}" --arg sha "${GITHUB_SHA}" --null-input --raw-output '$url | sub("{sha}";$sha)' )
		CREATED_STATUS=$( curl --silent --fail --request POST --url "${STATUS_URL}" --header "authorization: Bearer ${GITHUB_TOKEN}" --data "${STATUS_BODY}" )
	fi
fi

# ENCODED_PLAN=$( echo "${PLAN_TEXT}" | sed -z 's/%/%25/g; s/\n/%0A/g; s/\r/%0D/g' )
# echo "::set-output name=plan::${ENCODED_PLAN}"
