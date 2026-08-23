#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
release_metadata="${repository_root}/releases/${release_month}/release.json"

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${release_month}" >&2
    exit 1
fi

if [[ ! -f ${release_metadata} ]]; then
    echo "Release metadata does not exist: ${release_metadata}" >&2
    exit 1
fi

if ! command -v jq >/dev/null; then
    echo "Required command is unavailable: jq" >&2
    exit 1
fi

previous_month=$(find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print |
    while IFS= read -r archived_metadata; do basename "$(dirname "${archived_metadata}")"; done |
    LC_ALL=C sort |
    awk -v release_month="${release_month}" '$0 < release_month' |
    tail -n 1)

previous_metadata="${repository_root}/releases/${previous_month}/release.json"
if [[ -z ${previous_month} ]]; then
    previous_metadata=/dev/null
fi

jq -rn \
    --arg release_month "${release_month}" \
    --arg previous_month "${previous_month}" \
    --slurpfile current "${release_metadata}" \
    --slurpfile previous "${previous_metadata}" '
    def component_label:
        {os: "the operating system", r: "R", python: "Python", julia: "Julia", quarto: "Quarto"}[.];

    def component_version($environment; $component):
        if $component == "python" then ($environment.versions.python | join(", "))
        else ($environment.versions[$component] | tostring)
        end;

    def sentence_list:
        if length == 1 then .[0]
        elif length == 2 then "\(.[0]) and \(.[1])"
        else (.[:-1] | join(", ")) + ", and " + .[-1]
        end;

    def code_list:
        map("`" + . + "`") | sentence_list;

    ($current[0]) as $release
    | ($previous[0] // null) as $baseline
    | ($release.environments) as $now
    | (($baseline.environments) // []) as $before
    | ($now | map(.id)) as $now_ids
    | ($before | map(.id)) as $before_ids
    | ["os", "r", "python", "julia", "quarto"] as $components

    | ($now | map(select(.id | IN($before_ids[]) | not))) as $added
    | ($before | map(select(.id | IN($now_ids[]) | not))) as $removed
    | ($now | map(select(.id | IN($before_ids[])))
        | map(
            . as $environment
            | ($before[] | select(.id == $environment.id)) as $earlier
            | {
                id: $environment.id,
                changes: [
                    $components[]
                    | {
                        component: .,
                        from: component_version($earlier; .),
                        to: component_version($environment; .)
                    }
                    | select(.from != .to)
                ]
            }
        )) as $carried
    | ($carried | map(select(.changes | length > 0))) as $updated
    | ($carried | map(select(.changes | length == 0))) as $rebuilt

    | [
        "This release freezes \($now | length) exec environments to immutable digests and retains their registry tags through at least \($release.retentionUntil).",
        ""
      ]
    + (
        if $baseline == null then
            [
                "## Changes",
                "",
                "This is the first archived release, so it has no earlier month to compare against.",
                ""
            ]
        else
            ["## Changes since \($previous_month)", ""]
            + (if ($added | length) == 0 then [] else
                ["### Added environments", ""]
                + ($added | map("- `\(.id)` joins the release on \(.platforms | sentence_list)."))
                + [""]
              end)
            + (if ($removed | length) == 0 then [] else
                ["### Removed environments", ""]
                + ($removed | map("- `\(.id)` leaves the build matrix, and its earlier monthly archives stay retained."))
                + [""]
              end)
            + (if ($updated | length) == 0 then [] else
                ["### Updated software", ""]
                + ($updated | map(
                    "- `\(.id)` "
                    + (.changes | map(
                        if .from == "Not installed" then "adds \(.component | component_label) \(.to)"
                        elif .to == "Not installed" then "drops \(.component | component_label)"
                        else "moves \(.component | component_label) from \(.from) to \(.to)"
                        end
                      ) | sentence_list)
                    + "."
                  ))
                + [""]
              end)
            + (if ($rebuilt | length) == 0 then [] else
                ["### Rebuilt environments", ""]
                + [
                    (if ($rebuilt | length) == 1 then
                        "- One environment rebuilds"
                    else
                        "- \($rebuilt | length) environments rebuild"
                    end)
                    + " to a fresh digest with unchanged component versions: \($rebuilt | map(.id) | code_list)."
                  ]
                + [""]
              end)
        end
      )
    + [
        "## Environments",
        "",
        "| Environment | Operating system | R | Python | Julia | Quarto |",
        "| --- | --- | --- | --- | --- | --- |"
      ]
    + ($now | map("| [\(.id)](https://github.com/ricochet-rs/exec-envs/tree/main/releases/\($release.release)/\(.id)) | \(.versions.os) | \(.versions.r) | \(.versions.python | join(", ")) | \(.versions.julia) | \(.versions.quarto) |"))
    + [
        "",
        "## Pulling an environment",
        "",
        "Every environment is published only under its immutable calendar tag:",
        "",
        "```sh",
        "docker pull \($now[0].images.dockerHub)",
        "```",
        ""
      ]
    | join("\n")
'
