def matches($platform):
  any(.constraints[]?;
    .os == "linux" and .distribution == $platform.distribution and
    ((.versions // [$platform.version]) | index($platform.version)) != null);

def stable_unique:
  reduce .[] as $item ([]; if index($item) == null then . + [$item] else . end);

def command($platform):
  if .script != null then error("Review upstream script actions before generating")
  else .command | if $platform.family == "alma" then sub("^yum "; "dnf ") else . end end;

$config[0] as $config |
($config.platforms[] | select(.id == $id)) as $platform |
($config.overrides[$platform.family] + ($platform.overrides // {})) as $overrides |
($config.exclusions + ($platform.exclusions // {})) as $exclusions |
map({
  name: .name,
  dependencies: [.dependencies[] | select(matches($platform))]
}) as $rules |
[$rules[] | select($exclusions[.name] == null) |
  if $overrides[.name] != null then
    {name: .name, dependencies: [$overrides[.name]]}
  else . end] as $selected |
{
  revision: $config.revision,
  platform: $platform,
  exclusions: $exclusions,
  overrides: $overrides,
  unmapped: [$selected[] | select(.dependencies | length == 0) | .name],
  rules: ([$selected[] | select(.dependencies | length > 0) |
    {key: .name, value: [.dependencies[].packages[]?] | unique}] | from_entries),
  packages: ([$selected[].dependencies[].packages[]?] + $config.extras[$platform.family] | unique),
  pre_install: ([$selected[].dependencies[].pre_install[]? | command($platform)] | stable_unique),
  post_install: ([$selected[].dependencies[].post_install[]? | command($platform)] | stable_unique)
}
