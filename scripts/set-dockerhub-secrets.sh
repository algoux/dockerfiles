#!/usr/bin/env bash
# Keep tokens out of command arguments and logs, including under bash -x.
set +x
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: set-dockerhub-secrets.sh --repo OWNER/REPO --username USER [TOKEN_INPUT]

Set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN as GitHub repository Actions secrets.
Authenticate gh with an account that can manage the target repository's secrets.

Required:
  --repo OWNER/REPO    GitHub repository, for example algoux/dockerfiles
  --username USER     Docker Hub login user with push access to algoux/nodebase

Token input (choose at most one):
  --token-stdin       Read the Docker Hub access token from standard input
  --token-file PATH   Read the Docker Hub access token from a local file
  (default)          Prompt for the token with terminal echo disabled

Other:
  -h, --help          Show this help without making changes

The token is passed to gh through standard input, never as a command argument.
HELP
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

repository=''
username=''
token_source='prompt'
token_file=''
while (( $# > 0 )); do
  case "$1" in
    --repo)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail '--repo requires OWNER/REPO'
      [[ -z "$repository" ]] || fail '--repo may only be supplied once'
      repository="$2"
      shift 2
      ;;
    --username)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail '--username requires a Docker Hub login user'
      [[ -z "$username" ]] || fail '--username may only be supplied once'
      username="$2"
      shift 2
      ;;
    --token-stdin)
      [[ "$token_source" == prompt ]] || fail 'choose only one token input method'
      token_source='stdin'
      shift
      ;;
    --token-file)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail '--token-file requires a file path'
      [[ "$token_source" == prompt ]] || fail 'choose only one token input method'
      token_source='file'
      token_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail 'unknown argument (see --help)'
      ;;
  esac
done

[[ "$repository" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail '--repo must be OWNER/REPO'
[[ "$username" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || fail '--username must be a Docker Hub login user'
command -v gh >/dev/null 2>&1 || fail 'gh is required; install GitHub CLI and run gh auth login first'

dockerhub_token=''
trap 'unset dockerhub_token' EXIT
case "$token_source" in
  stdin)
    dockerhub_token="$(cat)"
    ;;
  file)
    [[ -f "$token_file" && -r "$token_file" ]] || fail '--token-file must be a readable regular file'
    dockerhub_token="$(cat -- "$token_file")"
    ;;
  prompt)
    [[ -t 0 ]] || fail 'interactive token input requires a terminal; use --token-stdin or --token-file'
    IFS= read -r -s -p 'Docker Hub access token: ' dockerhub_token || fail 'could not read token'
    printf '\n' >&2
    ;;
esac
[[ -n "$dockerhub_token" ]] || fail 'Docker Hub access token is empty'
[[ "$dockerhub_token" != *[[:space:]]* ]] || fail 'Docker Hub access token must be a single value without whitespace'

printf '%s' "$username" | gh secret set DOCKERHUB_USERNAME --repo "$repository"
printf '%s' "$dockerhub_token" | gh secret set DOCKERHUB_TOKEN --repo "$repository"
printf 'Configured DOCKERHUB_USERNAME and DOCKERHUB_TOKEN for %s.\n' "$repository"
