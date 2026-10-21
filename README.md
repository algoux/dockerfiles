# Docker base images

## Node.js 22

`nodebase/Dockerfile.22` builds from `node:22.23.4-bookworm`, the patched Node 22
release for the [October 2026 security advisory](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases).
It retains jemalloc 5.3.0 and the existing `vim`, `curl`, `telnet`, and `dnsutils`
tools. The Node 16 and Node 20 images and workflows are unchanged.

The `Build nodebase 22` workflow builds `linux/amd64` and `linux/arm64`. Each
architecture must pass the Dockerfile's runtime checks before publishing: exact
Node version `22.23.4`, presence of
`zlib.constants.BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH`, and a normal Brotli
compress/decompress round-trip. This is a runtime/patch check, not an exploit test.
The workflow publishes both tags:

- `algoux/nodebase:22`
- `algoux/nodebase:22.23.4`

Use the explicit `22.23.4` tag in application Dockerfiles for this rollout. The
`22` tag is a moving major-version alias. This workflow does not enforce registry
tag immutability; record or pin the published digest when reproducing a release.
Both build steps use `pull: true`; the second step reuses the verified build cache,
and any rebuilt layer must pass the same Dockerfile checks.

## Configure Docker Hub credentials before the first publish

The workflow uses the existing Actions secret names `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN`. The image namespace is fixed at `algoux/nodebase`; the login
username is the Docker Hub account owning the token, which must have push access
to that namespace. Using a different login username does not change the image
namespace.

The helper requires `gh` authenticated to GitHub with permission to manage
repository Actions secrets. Create a Docker Hub access token with push permission,
then run locally:

```sh
gh auth login
./scripts/set-dockerhub-secrets.sh --repo algoux/dockerfiles --username algoux
```

The script prompts for the Docker Hub token with input hidden. It sets both
repository secrets and never passes the token as a command-line argument. It can
also read an existing local token file or standard input:

```sh
./scripts/set-dockerhub-secrets.sh --repo algoux/dockerfiles --username algoux \
  --token-file /secure/path/dockerhub-token

cat /secure/path/dockerhub-token | \
  ./scripts/set-dockerhub-secrets.sh --repo algoux/dockerfiles --username algoux \
  --token-stdin

./scripts/set-dockerhub-secrets.sh --help
```

Keep token files outside the repository and restrict their permissions. The script
intentionally has no token command-line argument. `--help` makes no changes.
Existing values with the same secret names are replaced; the Node 16 and Node 20
workflows also use these credentials. Those older workflows derive their image
namespace from `DOCKERHUB_USERNAME`, so keep `--username algoux` if continuing to
publish their images to the same namespace without changing those workflows.

## Publish and consume in order

1. Configure the two secrets above before pushing the new workflow to `master`.
2. Commit and push the Node 22 Dockerfile and workflow when ready. A push to
   `master` affecting either file starts the workflow. It can also be started
   manually with `gh workflow run nodebase-22.yml --repo algoux/dockerfiles --ref master`
   after the workflow exists on the default branch.
3. Wait for `Build nodebase 22` to succeed and inspect the published manifest:
   `docker buildx imagetools inspect algoux/nodebase:22.23.4`. Both `linux/amd64`
   and `linux/arm64` must be present.
4. Build the application using `algoux/nodebase:22.23.4` only after that image is
   available. Deploy through the application's normal release process and verify
   `process.versions.node` and the Brotli patch marker in every running instance.

For a local build and runtime check (no registry push):

```sh
docker build --pull -f nodebase/Dockerfile.22 -t algoux/nodebase:22.23.4 ./nodebase
docker run --rm algoux/nodebase:22.23.4 node -p \
  'JSON.stringify({node: process.versions.node, brotli: process.versions.brotli, patchMarker: require("node:zlib").constants.BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH})'
```
