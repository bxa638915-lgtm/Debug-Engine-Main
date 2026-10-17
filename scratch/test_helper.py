import glob
import re

for path in glob.glob(r'.superpowers\sdd\**\FunkinLua*.hx', recursive=True):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        text = f.read()
    set_matches = re.findall(r'set\(\s*["\']([a-zA-Z0-9_]+)["\']', text)
    print(path, set(set_matches))
