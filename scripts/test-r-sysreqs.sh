#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "${temporary}"' EXIT

jq -n '{revision:"test", platforms:[{id:"test", family:"ubuntu", distribution:"ubuntu", version:"24.04"}],
  exclusions:{excluded:"test"}, extras:{ubuntu:["shared", "extra"]},
  overrides:{ubuntu:{overridden:{packages:["replacement"]}}}}' >"${temporary}/config.json"
jq -n '
  def dep($distribution; $versions; $package):
    {constraints:[{os:"linux", distribution:$distribution, versions:$versions}], packages:[$package]};
  [
    {name:"matching", dependencies:[dep("ubuntu"; ["24.04"]; "shared") +
      {pre_install:[{command:"first"}, {command:"second"}, {command:"first"}], post_install:[{command:"last"}]}]},
    {name:"all_versions", dependencies:[dep("ubuntu"; null; "unversioned")]},
    {name:"wrong_version", dependencies:[dep("ubuntu"; ["26.04"]; "wrong")]},
    {name:"wrong_distro", dependencies:[dep("alpine"; null; "wrong")]},
    {name:"excluded", dependencies:[dep("ubuntu"; null; "excluded")]},
    {name:"overridden", dependencies:[dep("ubuntu"; null; "old") + {pre_install:[{command:"discard"}]}]}
  ]' >"${temporary}/rules.json"

jq --slurpfile config "${temporary}/config.json" --arg id test \
  -f "${repository_root}/scripts/render-r-sysreqs.jq" "${temporary}/rules.json" >"${temporary}/result.json"
jq -e '
  .packages == ["extra", "replacement", "shared", "unversioned"] and
  .unmapped == ["wrong_version", "wrong_distro"] and
  .pre_install == ["first", "second"] and .post_install == ["last"] and
  .rules.overridden == ["replacement"] and .rules.excluded == null
' "${temporary}/result.json" >/dev/null

jq '.platforms[0].family = "alma" |
  .platforms[0].exclusions = {all_versions:"Unavailable on this target"} |
  .extras.alma = .extras.ubuntu | .overrides.alma = .overrides.ubuntu' \
  "${temporary}/config.json" >"${temporary}/alma.json"
jq '.[0].dependencies[0].pre_install = [{command:"yum install -y epel-release"}, {command:"dnf install -y epel-release"}]' \
  "${temporary}/rules.json" >"${temporary}/alma-rules.json"
jq --slurpfile config "${temporary}/alma.json" --arg id test \
  -f "${repository_root}/scripts/render-r-sysreqs.jq" "${temporary}/alma-rules.json" |
  jq -e '.pre_install == ["dnf install -y epel-release"] and .rules.all_versions == null' >/dev/null

jq '.[0].dependencies[0].pre_install = [{script:"unsupported.sh"}]' \
  "${temporary}/rules.json" >"${temporary}/script-rule.json"
if jq --slurpfile config "${temporary}/config.json" --arg id test \
  -f "${repository_root}/scripts/render-r-sysreqs.jq" "${temporary}/script-rule.json" \
  >"${temporary}/result.json" 2>"${temporary}/error.log"; then
  echo "Expected upstream script actions to fail generation" >&2
  exit 1
fi
rg -q 'Review upstream script actions' "${temporary}/error.log"
echo "R system requirement generation tests passed"
