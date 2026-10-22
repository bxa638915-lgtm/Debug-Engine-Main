import subprocess
import time
import os
from PIL import ImageGrab

exe_path = r"c:\Users\esque\Downloads\A_1\A\Vs Impostor alternated Scripts Converts\DBE-Tests-Source\Debug Engine-Main\export\release\windows\bin\CodenameEngine.exe"
work_dir = r"c:\Users\esque\Downloads\A_1\A\Vs Impostor alternated Scripts Converts\DBE-Tests-Source\Debug Engine-Main\export\release\windows\bin"
shot_path = r"C:\Users\esque\.gemini\antigravity\brain\a141dc49-ae71-4c99-9d89-7d7b56fcead3\gameplay_snapshot.png"

print("Starting game for visual screenshot...")
proc = subprocess.Popen(
    [exe_path, "-mod", "MINDLESS", "-song", "mindless"],
    cwd=work_dir,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8",
    errors="replace"
)

# Wait 9 seconds for song to load and play
time.sleep(9)

try:
    img = ImageGrab.grab()
    img.save(shot_path)
    print(f"Screenshot successfully saved to {shot_path} (size: {img.size})")
except Exception as e:
    print(f"Screenshot error: {e}")

time.sleep(1)
proc.kill()
stdout, stderr = proc.communicate()
print("Game terminated.")
