#!/usr/bin/env bash
# Shared renderer for one environment's Ricochet `[image.<id>]` block.
# Every generator that emits a `bin` path sources this file so the install layout is written once.

# Reduce a recorded OS name to "<distribution> <version>", dropping codenames and LTS markers.
normalize_os() {
    local recorded_os=$1

    case ${recorded_os} in
        "Alpine Linux v"*) printf 'Alpine %s\n' "${recorded_os#Alpine Linux v}" ;;
        "AlmaLinux "*)
            os_version=${recorded_os#AlmaLinux }
            printf 'AlmaLinux %s\n' "${os_version%% *}"
            ;;
        "Ubuntu "*)
            os_version=${recorded_os#Ubuntu }
            printf 'Ubuntu %s\n' "${os_version%% *}"
            ;;
        *)
            echo "Unsupported operating system: ${recorded_os}" >&2
            return 1
            ;;
    esac
}

# render_environment_toml <environment json> <image field> <description> <release>
# Prints the `[image.<id>]` block, where <image field> selects `.images.dockerHub` or `.images.ricochetRegistry`.
render_environment_toml() {
    local environment=$1
    local image_field=$2
    local description=$3
    local release=$4
    local environment_id image recorded_os os platforms language quarto tool version

    environment_id=$(jq -r '.id | gsub("\\."; "-")' <<<"${environment}")
    image=$(jq -r --arg field "${image_field}" '.images[$field]' <<<"${environment}")
    recorded_os=$(jq -r '.versions.os' <<<"${environment}")
    os=$(normalize_os "${recorded_os}")
    platforms=$(jq -r '.platforms | map("\"" + . + "\"") | join(", ")' <<<"${environment}")
    language=${environment_id%%-*}

    printf '[image.%s]\n' "${environment_id}"
    printf 'image = "%s"\n' "${image}"
    printf 'os = "%s"\n' "${os}"
    printf 'description = "%s"\n' "${description}"
    printf 'release = "%s"\n' "${release}"
    printf 'arch = [%s]\n' "${platforms}"

    case ${language} in
        r)
            echo 'r = ['
            jq -r '.versions.r[] | "  { version = \"" + . + "\", bin = \"/opt/R/" + . + "/bin/R\" },"' <<<"${environment}"
            echo ']'
            ;;
        python)
            echo 'python = ['
            jq -r '.versions.python[] | "  { version = \"" + . + "\", bin = \"/usr/local/bin/python" + (split(".")[0:2] | join(".")) + "\" },"' <<<"${environment}"
            echo ']'
            ;;
        julia)
            echo 'julia = ['
            jq -r '.versions.julia[] | "  { version = \"" + . + "\", bin = \"/usr/local/bin/julia" + (split(".")[0:2] | join(".")) + "\" },"' <<<"${environment}"
            echo ']'
            ;;
    esac

    quarto=$(jq -r '.versions.quarto' <<<"${environment}")
    if [[ ${quarto} != "Not installed" ]]; then
        printf 'quarto = [{ version = "%s", bin = "/opt/quarto/bin/quarto" }]\n' "${quarto}"
    fi
    for tool in pandoc typst; do
        version=$(jq -r --arg tool "${tool}" '.versions[$tool]' <<<"${environment}")
        if [[ ${version} != "Not installed" && ${version} != null ]]; then
            printf '%s = "%s"\n' "${tool}" "${version}"
        fi
    done
}
