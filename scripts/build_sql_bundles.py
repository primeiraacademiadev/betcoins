"""Render frozen SQL exports from canonical migrations. Never connects to a DB."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = re.compile(r"\{\{source:([a-zA-Z0-9_]+\.sql)\}\}")


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def within(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Bundle path must remain inside the repository')
    return path


def render(name, root=ROOT):
    bundles = json.loads((root / 'supabase/bundles.json').read_text(encoding='utf-8'))
    spec = bundles[name]
    sources = {}
    for entry in spec['sources']:
        path = within(root, entry['path'])
        if path.parent != (root / 'supabase/migrations').resolve():
            raise ValueError('Only canonical migrations may be embedded')
        content = path.read_text(encoding='utf-8').rstrip('\n')
        if digest(content) != entry['sha256']:
            raise ValueError(f'Frozen migration changed: {path.name}')
        if path.name in sources:
            raise ValueError('Duplicate migration in bundle manifest')
        sources[path.name] = content
    template = within(root, spec['template']).read_text(encoding='utf-8')
    requested = SOURCE.findall(template)
    if requested != list(sources):
        raise ValueError('Template and manifest must have identical source order')
    rendered = SOURCE.sub(lambda match: sources[match[1]], template)
    if digest(rendered) != spec['sha256']:
        raise ValueError('Generated export differs from the reviewed frozen SQL')
    return spec['output'], rendered


def build(name, root=ROOT):
    relative, content = render(name, root)
    output = within(root, relative)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding='utf-8', newline='\n')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', choices=('baseline', 'upgrade', 'all'))
    args = parser.parse_args()
    names = ('baseline', 'upgrade') if args.bundle == 'all' else (args.bundle,)
    for name in names:
        print(build(name).relative_to(ROOT))


if __name__ == '__main__':
    main()
