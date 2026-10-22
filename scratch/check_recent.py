import json

with open(r'C:\Users\esque\.gemini\antigravity\brain\a141dc49-ae71-4c99-9d89-7d7b56fcead3\.system_generated\logs\transcript_full.jsonl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for line in lines:
    if '"USER_INPUT"' in line:
        data = json.loads(line)
        print(f"=== USER_INPUT (step {data.get('step_index')}) ===")
        print(data.get('content'))
