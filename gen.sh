#!/bin/bash
set -e

# Define output file
OUTPUT_FILE="skaffold-auto.yaml"

# Create base YAML structure using yq
yq eval -n '
  .apiVersion = "skaffold/v4beta9" |
  .kind = "Config" |
  .build.cluster.namespace = "iride-datalake" |
  .build.cluster.serviceAccount = "kaniko-sa" |
  .build.cluster.volumes = [{
    "name": "kaniko-secret",
    "secret": {
      "secretName": "kaniko-secret",
      "items": [{"key": ".dockerconfigjson", "path": "config.json"}]
    }
  }] |
  .build.artifacts = []
' > "$OUTPUT_FILE"

# Function to generate an artifact block using yq
generate_artifact() {
    local tool="$1"
    local tool_path="$2"

    etool=$tool etool_path=$tool_path yq e -n '
      .image = "cr.terradue.com/earthquake-monitoring/\(env(etool))" |
      .context = env(etool_path) |
      .kaniko.volumeMounts = [{"name": "kaniko-secret", "mountPath": "kaniko/.docker"}]'
}

#generate_artifact "etool" "etoolpath"

# Extract tools from project.toml and append them dynamically
tomlq -r '.tools | to_entries | .[] | "\(.key) \(.value.context)"' project.toml | while read -r tool tool_path; do
    t=$( generate_artifact "$tool" "$tool_path" )
    coso=$t yq eval -P ".build.artifacts += env(coso)" -i "$OUTPUT_FILE"
done

echo "✅ Skaffold configuration generated in $OUTPUT_FILE"
cwl=$( tomlq -r '.workflows."water-bodies".path' project.toml )
#cat $OUTPUT_FILE | skaffold build -f - -q > build.json
i=0
tomlq -r '.tools | keys[]' project.toml | while read -r tool; do
    img=$( cat build.json | index=$i yq ".builds[env(index)].tag")
    i=$((i+1))
    s="${tool}" t="${img}" yq -i eval '(.$graph[] | select (.id == env(s)) ).hints.DockerRequirement.dockerPull = env(t)' -i $cwl
done