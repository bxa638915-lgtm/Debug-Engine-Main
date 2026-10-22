import subprocess
import time
import os

exe_path = r"c:\Users\esque\Downloads\A_1\A\Vs Impostor alternated Scripts Converts\DBE-Tests-Source\Debug Engine-Main\export\release\windows\bin\CodenameEngine.exe"
work_dir = r"c:\Users\esque\Downloads\A_1\A\Vs Impostor alternated Scripts Converts\DBE-Tests-Source\Debug Engine-Main\export\release\windows\bin"
log_path = r"scratch\game_test.log"

print("Starting game...")
proc = subprocess.Popen(
    [exe_path, "-mod", "MINDLESS", "-song", "mindless"],
    cwd=work_dir,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8",
    errors="replace"
)

# Wait 25 seconds
try:
    stdout, stderr = proc.communicate(timeout=50)
except subprocess.TimeoutExpired:
    proc.kill()
    stdout, stderr = proc.communicate()

with open(log_path, "w", encoding="utf-8") as f:
    f.write("--- STDOUT ---\n" + stdout + "\n--- STDERR ---\n" + stderr)

print(f"Game run finished. Output length: {len(stdout)}. Log saved to {log_path}.")
