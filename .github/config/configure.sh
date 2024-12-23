#!/usr/bin/env bash
set -o errexit -o errtrace -o nounset -o pipefail

owner="twelvelabs"
repos="$(gh repo list "${owner}" --source --no-archived --json nameWithOwner --jq '.[].nameWithOwner')"

{
    echo ""
    echo "Configured the following repos :wrench: :tada:"
    echo ""
} >>"${GITHUB_STEP_SUMMARY}"

for repo in $repos; do
    export GH_REPO="${repo}"

    echo "- [${repo}](https://github.com/${repo})" >>"${GITHUB_STEP_SUMMARY}"

    echo "[${repo}] Configuring repo"
    gh api -X PATCH /repos/:owner/:repo \
        --input=".github/config/repo.json" >/dev/null

    # Don't add protection rules on the repo that has the profile README
    # because it needs to be able to freely push to the default branch.
    if [[ "${repo}" != "${owner}/${owner}" ]]; then
        echo "[${repo}] Configuring branch and tag protection rules"
        branch=$(gh repo view "${repo}" --json defaultBranchRef --jq '.defaultBranchRef.name')
        gh api -X PUT "/repos/:owner/:repo/branches/${branch}/protection" \
            --input=".github/config/branch-protection.json" >/dev/null
        # Tag protection rules have been replaced with the new Rule Sets feature.
        # rule_id=$(gh api /repos/:owner/:repo/tags/protection \
        #     --jq '.[] | select(.pattern=="v.*") | .id')
        # if [[ "${rule_id}" == "" ]]; then
        #     gh api -X POST /repos/:owner/:repo/tags/protection -f pattern='v.*' >/dev/null
        # fi
    fi

    echo "[${repo}] Configuring automated security features"
    gh api -X PUT /repos/:owner/:repo/vulnerability-alerts >/dev/null
    gh api -X PUT /repos/:owner/:repo/automated-security-fixes >/dev/null

    # Check for rate limit
    remaining="$(gh api /rate_limit --jq '.rate.remaining')"
    echo "[${repo}] API calls remaining: ${remaining}"

    if ((remaining < 10)); then
        reset="$(gh api /rate_limit --jq '.rate.reset')"

        if [[ "$(uname -s)" == "Darwin" ]]; then
            formatted="$(date -r "${reset}" -Iseconds)"
        else
            formatted="$(date -d "@${reset}" -Iseconds)"
        fi
        echo ""
        echo "PAUSING UNTIL QUOTA RESET @ ${formatted}"
        echo ""

        sleep "${reset}"
    fi

    echo ""
done

{
    echo ""
    echo "Using"
    echo ""
    echo "- [branch-protection.json](https://github.com/${owner}/.github/blob/main/.github/config/branch-protection.json)"
    echo "- [repo.json](https://github.com/${owner}/.github/blob/main/.github/config/repo.json)"
    echo ""
} >>"${GITHUB_STEP_SUMMARY}"
