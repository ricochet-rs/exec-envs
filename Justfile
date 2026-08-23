# Container image build recipes

set dotenv-load

# Render the generated build and merge workflows from release/environments
render-release-workflows:
    scripts/render-release-workflows.sh

# Lint Containerfiles
lint-docker:
    find . -type f \( -iname \*.containerfile -o -iname Containerfile \) -print0 | sort -z | xargs -0 hadolint

# Create a monthly release and inventory its contents
release release_month:
    RELEASE_CLEANUP_IMAGES=true scripts/create-release.sh "{{release_month}}"
    scripts/format-release.sh "{{release_month}}"

# List build-matrix environments active for a monthly release
list-release-environments release_month:
    scripts/list-release-environments.sh "{{release_month}}"

# Prepare build matrices and defaults for the next monthly release
prepare-next-release release_month:
    scripts/prepare-next-release.sh "{{release_month}}"

# Discard a month's archive and build it again from the current matrix
re-release release_month:
    scripts/re-release.sh "{{release_month}}"
    scripts/format-release.sh "{{release_month}}"

# Rebuild an archived month, keeping its recorded R, Python, Julia and Quarto versions
rebuild-release release_month:
    RELEASE_REBUILD=true RELEASE_CLEANUP_IMAGES=true scripts/create-release.sh "{{release_month}}"
    scripts/format-release.sh "{{release_month}}"

# Render the GitHub release notes for a monthly release
release-notes release_month:
    scripts/render-release-notes.sh "{{release_month}}"

# Publish or refresh the GitHub release for every archived month
publish-release-notes:
    scripts/publish-release-notes.sh

# Validate archived files and generated links
check-releases:
    scripts/check-releases.sh

# Validate archived files, generated links, and retained registry tags
check-releases-remote:
    scripts/check-releases.sh --remote
