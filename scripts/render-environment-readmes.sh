#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-}
output_root=${2:-${repository_root}}

if [[ -z ${release_month} ]]; then
    release_metadata=$(find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print | sort -r | head -n 1)
    if [[ -z ${release_metadata} ]]; then
        echo "No monthly release metadata exists" >&2
        exit 1
    fi
    release_month=$(jq -r '.release' "${release_metadata}")
else
    release_metadata="${repository_root}/releases/${release_month}/release.json"
fi

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${release_month}" >&2
    exit 1
fi

if [[ ! -f ${release_metadata} ]]; then
    echo "Release metadata does not exist: ${release_metadata}" >&2
    exit 1
fi

for command in jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

normalize_os() {
    local recorded_os=$1

    case ${recorded_os} in
        "AlmaLinux "*)
            os_version=${recorded_os#AlmaLinux }
            os_version=${os_version%%.*}
            os_id="alma-${os_version}"
            os_name="AlmaLinux ${os_version}"
            ;;
        "Alpine Linux v"*)
            os_version=${recorded_os#Alpine Linux v}
            os_id="alpine-${os_version}"
            os_name="Alpine Linux ${os_version}"
            ;;
        "Ubuntu "*)
            os_version=${recorded_os#Ubuntu }
            os_version=${os_version%% *}
            os_version=$(cut -d. -f1,2 <<<"${os_version}")
            os_id="ubuntu-${os_version}"
            os_name="Ubuntu ${os_version}"
            ;;
        *)
            echo "Unsupported operating system in release metadata: ${recorded_os}" >&2
            return 1
            ;;
    esac
}

render_environment() {
    local environment=$1
    local environment_id
    local image_reference
    local platforms
    local recorded_os
    local toml_id

    environment_id=$(jq -r '.id' <<<"${environment}")
    image_reference=$(jq -r '.images.dockerHub' <<<"${environment}")
    platforms=$(jq -r '.platforms | map("\"" + . + "\"") | join(", ")' <<<"${environment}")
    recorded_os=$(jq -r '.versions.os' <<<"${environment}")
    toml_id=${environment_id//./-}
    normalize_os "${recorded_os}"

    printf '[image.%s]\n' "${toml_id}"
    printf 'image = "%s"\n' "${image_reference}"
    printf 'os = "%s"\n' "${os_id}"
    printf 'arch = [%s]\n' "${platforms}"

    case ${language} in
        R)
            printf 'description = "R execution environment for %s"\n' "${os_name}"
            echo 'r = ['
            jq -r '.versions.r[] | "  { version = \"\(.)\", bin = \"/usr/local/bin/R\(. | split(".")[0:2] | join("."))\" },"' <<<"${environment}"
            echo ']'
            ;;
        Python)
            printf 'description = "Python execution environment for %s"\n' "${os_name}"
            echo 'python = ['
            jq -r '.versions.python[] | "  { version = \"\(.)\", bin = \"/usr/local/bin/python\(. | split(".")[0:2] | join("."))\" },"' <<<"${environment}"
            echo ']'
            ;;
        Julia)
            if [[ $(jq -r '.versions.julia | type' <<<"${environment}") == array ]]; then
                printf 'description = "Julia execution environment for %s"\n' "${os_name}"
                echo 'julia = ['
                jq -r '.versions.julia[] | "  { version = \"\(.)\", bin = \"/usr/local/bin/julia\(. | split(".")[0:2] | join("."))\" },"' <<<"${environment}"
                echo ']'
            else
                julia_version=$(jq -r '.versions.julia' <<<"${environment}")
                julia_series=$(cut -d. -f1,2 <<<"${julia_version}")
                printf 'description = "Julia %s execution environment for %s"\n' "${julia_series}" "${os_name}"
                printf 'julia = [{ version = "%s", bin = "/opt/julia/bin/julia" }]\n' "${julia_version}"
            fi
            ;;
    esac
}

for definition in "${repository_root}"/release/environments/*.yaml; do
    image=$(yq -r '.image' "${definition}")
    containerfile=$(yq -r '.containerfile' "${definition}")
    target_directory="${output_root}/${containerfile%/*}"
    target_readme="${target_directory}/README.md"
    rendered_readme=$(mktemp)
    environment_count=$(jq --arg image "${image}" '[.environments[] | select(.image == $image)] | length' "${release_metadata}")

    if [[ ${environment_count} == 0 ]]; then
        echo "Release ${release_month} does not contain ${image}" >&2
        exit 1
    fi

    case ${image%%-*} in
        r) language=R ;;
        python) language=Python ;;
        julia) language=Julia ;;
        *)
            echo "Unsupported language image: ${image}" >&2
            exit 1
            ;;
    esac

    case ${image#*-} in
        alma) operating_system=AlmaLinux ;;
        alpine) operating_system="Alpine Linux" ;;
        ubuntu) operating_system=Ubuntu ;;
        *)
            echo "Unsupported operating system image: ${image}" >&2
            exit 1
            ;;
    esac

    {
        printf '# %s on %s\n\n' "${language}" "${operating_system}"
        if [[ ${environment_count} == 1 ]]; then
            echo "Copy this environment from the latest release into \`ricochet-exec-env.toml\`."
            printf 'The calendar-versioned tag keeps the configured %s and %s versions reproducible.\n\n' "${language}" "${operating_system}"
        else
            echo "Copy the environments you want from the latest release into \`ricochet-exec-env.toml\`."
            printf 'The calendar-versioned tags keep the configured %s and %s versions reproducible.\n\n' "${language}" "${operating_system}"
        fi
        echo '```toml'
        first=true
        while IFS= read -r environment; do
            if [[ ${first} == false ]]; then
                echo
            fi
            render_environment "${environment}"
            first=false
        done < <(jq -c --arg image "${image}" '.environments[] | select(.image == $image)' "${release_metadata}" | sort)
        echo '```'
    } >"${rendered_readme}"

    mkdir -p "${target_directory}"
    mv "${rendered_readme}" "${target_readme}"
done
