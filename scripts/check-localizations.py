#!/usr/bin/env python3
"""Validate native localization resources without invoking a network service.
Run from any directory. Add supported languages in project.yml and resources together.
"""
from pathlib import Path
import collections
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
match = re.search(r'CFBundleLocalizations:\s*\[([^]]+)\]', (root / 'project.yml').read_text())
languages = [value.strip() for value in match[1].split(',')]
errors = []
placeholder = re.compile(r'%(?:\d+\$)?(?:lld|ld|d|lf|f|@)')
def signature(value):
    return collections.Counter(placeholder.findall(value.replace('%%', '')))
def units(value):
    if 'stringUnit' in value:
        return [value['stringUnit']['value']]
    if 'stringSet' in value:
        return value['stringSet']['values']
    result = []
    for group in value.get('variations', {}).values():
        for variation in group.values():
            result += units(variation)
    return result

tables = {}
for path in sorted((root / 'App').rglob('*.xcstrings')):
    catalog = json.loads(path.read_text())
    assert catalog['sourceLanguage'] == 'en', path
    table = path.stem
    tables[table] = catalog['strings']
    for key, entry in catalog['strings'].items():
        translations = entry.get('localizations', {})
        if not set(languages) <= translations.keys():
            errors.append(f'{path.name}:{key}: missing language')
            continue
        reference = signature(units(translations['en'])[-1])
        for language in languages:
            values = units(translations[language])
            if not values or any(signature(value) != reference for value in values):
                errors.append(f'{path.name}:{key}:{language}: placeholder mismatch')

# Allow only brand names, numeric/currency fields, and technical example placeholders
# as bare UI literals. Prose should go through a semantic localization key.
allowed_ui_literals = {"Paperclip", "$", "0", "https://paperclip.example.com", "pcp_board_…"}
def literal_parts(source, start):
    """Return static text, interpolation arity, and end position of a Swift literal."""
    i, result, arity = start, '', 0
    while i < len(source):
        if source[i] == '"': return result, arity, i + 1
        if source[i:i+2] == '\\(':
            arity += 1
            i += 2
            depth = 1
            while i < len(source) and depth:
                if source[i] == '"':
                    _, _, i = literal_parts(source, i + 1)
                    continue
                if source[i] == '(': depth += 1
                elif source[i] == ')': depth -= 1
                i += 1
        elif source[i] == '\\': i += 2
        else: result += source[i]; i += 1
    return result, arity, i

helpers = {'AppL10n': 'Localizable', 'TasksL10n': 'Tasks', 'AgentsL10n': 'Agents'}
used = collections.defaultdict(set)
for path in sorted((root / 'App').rglob('*.swift')):
    source = path.read_text()
    for helper, key in re.findall(r'(AppL10n|TasksL10n|AgentsL10n)\.text\(\s*"([^"]+)"', source):
        table = helpers[helper]
        used[table].add(key)
        if key not in tables[table]: errors.append(f'{path.relative_to(root)}: missing {table}:{key}')
    for match in re.finditer(r'(AppL10n|TasksL10n|AgentsL10n)\.text\(\s*"([^"]+)"\s*,\s*"', source):
        helper, key = match.group(1), match.group(2)
        entry = tables[helpers[helper]].get(key)
        if entry:
            _, arity, _ = literal_parts(source, match.end())
            expected = sum(signature(units(entry['localizations']['en'])[-1]).values())
            if arity != expected: errors.append(f'{path.relative_to(root)}:{key}: call has {arity} arguments, resource expects {expected}')
    for match in re.finditer(r'\b(?:Text|Button|Label|Section|TextField|SecureField|Picker|Toggle|LabeledContent|navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog)\("', source):
        line_start = source.rfind('\n', 0, match.start()) + 1
        if source[line_start:match.start()].strip().startswith('//'): continue
        prose, _, _ = literal_parts(source, match.end())
        if re.search(r'[A-Za-z\u3400-\u9fff]', prose) and prose not in allowed_ui_literals:
            errors.append(f'{path.relative_to(root)}: bare UI prose: {prose!r}')
    for number, line in enumerate(source.splitlines(), 1):
        if not line.strip().startswith('//') and re.search(r'[\u3400-\u9fff]', line):
            errors.append(f'{path.relative_to(root)}:{number}: hard-coded Chinese UI text')

kit = root / 'PaperclipKit/Sources/PaperclipKit/Resources'
kit_tables = {}
for language in languages:
    path = kit / f'{language}.lproj/Localizable.strings'
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True, check=True)
    kit_tables[language] = json.loads(result.stdout)
reference = kit_tables['en']
for language, translations in kit_tables.items():
    if translations.keys() != reference.keys(): errors.append(f'PaperclipKit:{language}: key mismatch')
    for key in reference.keys() & translations.keys():
        if signature(translations[key]) != signature(reference[key]): errors.append(f'PaperclipKit:{language}:{key}: placeholder mismatch')
for path in (root / 'PaperclipKit/Sources').rglob('*.swift'):
    for key in re.findall(r'KitL10n\.string\(\s*"([^"]+)"', path.read_text()):
        if key not in reference: errors.append(f'{path.name}: missing Kit key {key}')

if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {sum(len(v) for v in tables.values())} app keys + {len(reference)} package keys; languages: {", ".join(languages)}; keys and typed placeholders match.')
