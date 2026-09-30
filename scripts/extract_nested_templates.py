"""Write each StackSet's inline TemplateBody to its own file, for cfn-lint.

cfn-lint does not descend into TemplateBody strings, so the member and data
templates are linted only once extracted. Usage: SCRIPT <template> <out_dir>
"""

import pathlib
import sys

import yaml


class _IgnoreTags(yaml.SafeLoader):
    pass


# Short-form intrinsics (!Ref, !Sub, ...) are irrelevant to finding TemplateBody.
_IgnoreTags.add_multi_constructor("!", lambda loader, suffix, node: None)


def main(template: str, out_dir: str) -> None:
    doc = yaml.load(pathlib.Path(template).read_text(), Loader=_IgnoreTags)
    found = 0
    for name, resource in doc["Resources"].items():
        if resource.get("Type") != "AWS::CloudFormation::StackSet":
            continue
        body = resource["Properties"]["TemplateBody"]
        pathlib.Path(out_dir, f"{name}.yaml").write_text(body)
        found += 1
    if found == 0:
        sys.exit(f"no StackSet with a TemplateBody in {template}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
