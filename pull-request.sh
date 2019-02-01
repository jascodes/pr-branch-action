#!/bin/bash

# Suggested by Github actions to be strict
set -e
set -o pipefail

################################################################################
# Global Variables (we can't use GITHUB_ prefix)
################################################################################

API_VERSION=v3
BASE=https://api.github.com
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
HEADER="Accept: application/vnd.github.${API_VERSION}+json"
HEADER="${HEADER}; application/vnd.github.antiope-preview+json"

# URLs
REPO_URL="${BASE}/repos/${GITHUB_REPOSITORY}"
PULLS_URL=$REPO_URL/pulls

################################################################################
# Helper Functions
################################################################################


check_credentials() {

    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo "You must include the GITHUB_TOKEN as an environment variable."
        exit 1
    fi

}

check_events_json() {

    if [[ ! -f "${GITHUB_EVENT_PATH}" ]]; then
        echo "Cannot find Github events file at ${GITHUB_EVENT_PATH}";
        exit 1;
    fi
    echo "Found ${GITHUB_EVENT_PATH}";
    
}

check_pull_request() {

    # Check if the branch already has a pull request open 

    SOURCE=${1}  # from this branch
    TARGET=${2}  # pull request TO this target
    DATA="{\"base\":\"${TARGET}\", \"head\":\"${SOURCE}\"}"
    RESPONSE=$(curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" --user "${GITHUB_ACTOR}" -X GET --data "${DATA}" ${PULLS_URL})
    PR=$(echo "${RESPONSE}" | jq --raw-output '.[] | .head.ref')
    echo "Response ref: ${PR}"
    if [[ "${PR}" == "${SOURCE}" ]]; then
            return 1;
    fi
    return 0;

}

create_pull_request() {

    SOURCE=${1}  # from this branch
    TARGET=${2}  # pull request TO this target

    # Check if the pull request is already submit
    check_pull_request "${SOURCE}" "${TARGET}"
    retval=$?
    echo "Return value is $retval."
    if [[ "${retval}" == "1" ]]; then
        echo "Pull request from ${SOURCE} to ${TARGET} is already open!"
    else
        TITLE="Update container ${SOURCE}"
        BODY="This is an automated pull request to update the container collection ${SOURCE}"

        # Post the pull request
        DATA="{\"title\":\"${TITLE}\", \"base\":\"${TARGET}\", \"head\":\"${SOURCE}\"}"
        echo "curl --user ${GITHUB_ACTOR} -X POST --data ${DATA} ${PULLS_URL}"
        curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" --user "${GITHUB_ACTOR}" -X POST --data "${DATA}" ${PULLS_URL}
        echo $?
    fi
}


main () {

    # path to file that contains the POST response of the event
    # Example: https://github.com/actions/bin/tree/master/debug
    # Value: /github/workflow/event.json
    check_events_json;

    # User specified branch to PR to, and check
    if [ -z "${BRANCH_PREFIX}" ]; then
        echo "No branch prefix is set, all branches will be used."
        BRANCH_PREFIX=""
        echo "Branch prefix is $BRANCH_PREFIX"
    fi

    if [ -z "${PULL_REQUEST_BRANCH}" ]; then
        PULL_REQUEST_BRANCH=master
    fi
    echo "Pull requests will go to ${PULL_REQUEST_BRANCH}"

    # Get the name of the action that was triggered
    BRANCH=$(jq --raw-output .ref "${GITHUB_EVENT_PATH}");
    BRANCH=$(echo "${BRANCH/refs\/heads\//}")
    echo "Found branch $BRANCH"
 
    # If it's to the target branch, ignore it
    if [[ "${BRANCH}" == "${PULL_REQUEST_BRANCH}" ]]; then
        echo "Target and current branch are identical (${BRANCH}), skipping."
    else

        # If the prefix for the branch matches
        if  [[ $BRANCH == ${BRANCH_PREFIX}* ]]; then

            # Ensure we have a GitHub token
            check_credentials
            create_pull_request $BRANCH $PULL_REQUEST_BRANCH

        fi

    fi
}

echo "==========================================================================
START: Running Pull Request on Branch Update Action!";
main;
echo "==========================================================================
END: Finished";
