#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-}
output=${2:-${repository_root}/deploy/ricochet-previews/values.yaml}

if [[ -z ${release_month} ]]; then
    release_metadata=$(find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print | sort -r | head -n 1)
else
    release_metadata="${repository_root}/releases/${release_month}/release.json"
fi

if [[ -z ${release_metadata:-} || ! -f ${release_metadata} ]]; then
    echo "Release metadata does not exist: ${release_metadata:-none}" >&2
    exit 1
fi

for command in jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

selected_environments=$(mktemp)
rendered_toml=$(mktemp)
rendered_values=$(mktemp)
remove_working_files() {
    rm -f "${selected_environments}" "${rendered_toml}" "${rendered_values}"
}
trap remove_working_files EXIT

jq -c '
    [.environments[]
        | select(
            (.id | test("^(r|python|julia)-ubuntu-resolute$")) or
            (.id | test("^(r|julia)-alpine-"))
        )]
    | sort_by(.id)
' "${release_metadata}" >"${selected_environments}"

for required in r-ubuntu-resolute python-ubuntu-resolute julia-ubuntu-resolute; do
    if ! jq -e --arg id "${required}" 'any(.[]; .id == $id)' "${selected_environments}" >/dev/null; then
        echo "Latest release does not contain required preview environment: ${required}" >&2
        exit 1
    fi
done

if [[ $(jq '[.[] | select(.id | test("-alpine-"))] | length' "${selected_environments}") -lt 2 ]]; then
    echo "Latest release does not contain Alpine preview environments" >&2
    exit 1
fi

normalize_os() {
    local recorded_os=$1

    case ${recorded_os} in
        "Alpine Linux v"*) printf 'alpine-%s\n' "${recorded_os#Alpine Linux v}" ;;
        "Ubuntu "*)
            os_version=${recorded_os#Ubuntu }
            printf 'ubuntu-%s\n' "$(cut -d. -f1,2 <<<"${os_version%% *}")"
            ;;
        *)
            echo "Unsupported preview operating system: ${recorded_os}" >&2
            return 1
            ;;
    esac
}

while IFS= read -r environment; do
    environment_id=$(jq -r '.id | gsub("\\."; "-")' <<<"${environment}")
    image=$(jq -r '.images.ricochetRegistry + "@" + .digest' <<<"${environment}")
    recorded_os=$(jq -r '.versions.os' <<<"${environment}")
    os=$(normalize_os "${recorded_os}")
    platforms=$(jq -r '.platforms | map("\"" + . + "\"") | join(", ")' <<<"${environment}")
    language=${environment_id%%-*}

    {
        printf '[image.%s]\n' "${environment_id}"
        printf 'image = "%s"\n' "${image}"
        printf 'os = "%s"\n' "${os}"
        printf 'description = "Latest %s preview environment from release %s"\n' "${language}" "$(jq -r '.release' "${release_metadata}")"
        printf 'arch = [%s]\n' "${platforms}"
    } >>"${rendered_toml}"

    case ${language} in
        r)
            echo 'r = [' >>"${rendered_toml}"
            jq -r '.versions.r[] | "  { version = \"" + . + "\", bin = \"/usr/local/bin/R" + (split(".")[0:2] | join(".")) + "\" },"' <<<"${environment}" >>"${rendered_toml}"
            echo ']' >>"${rendered_toml}"
            ;;
        python)
            echo 'python = [' >>"${rendered_toml}"
            jq -r '.versions.python[] | "  { version = \"" + . + "\", bin = \"/usr/local/bin/python" + (split(".")[0:2] | join(".")) + "\" },"' <<<"${environment}" >>"${rendered_toml}"
            echo ']' >>"${rendered_toml}"
            ;;
        julia)
            echo 'julia = [' >>"${rendered_toml}"
            jq -r '.versions.julia[] | "  { version = \"" + . + "\", bin = \"/usr/local/bin/julia" + (split(".")[0:2] | join(".")) + "\" },"' <<<"${environment}" >>"${rendered_toml}"
            echo ']' >>"${rendered_toml}"
            ;;
    esac

    quarto=$(jq -r '.versions.quarto' <<<"${environment}")
    if [[ ${quarto} != "Not installed" ]]; then
        printf 'quarto = [{ version = "%s", bin = "/opt/quarto/bin/quarto" }]\n' "${quarto}" >>"${rendered_toml}"
    fi
    echo >>"${rendered_toml}"
done < <(jq -c '.[]' "${selected_environments}")

{
    echo 'config:'
    echo '  backend:'
    echo '    default_image: r-ubuntu-resolute'
    echo '    allowed_images:'
    jq -r '.[] | "      - " + (.id | gsub("\\."; "-"))' "${selected_environments}"
    echo 'execEnv:'
    echo '  config: |'
    sed '/./s/^/    /' "${rendered_toml}"
} >"${rendered_values}"

mkdir -p "$(dirname "${output}")"
mv "${rendered_values}" "${output}"
