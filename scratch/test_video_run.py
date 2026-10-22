import subprocess, time
from PIL import ImageGrab

exe = r'export/release/windows/bin/CodenameEngine.exe'
cwd = r'export/release/windows/bin'
shot_path = r'export/release/windows/bin/logs/video_step5_screenshot.png'

print('Starting engine for 45 seconds...')
p = subprocess.Popen([exe, '-mod', 'Suffering Siblings', '-song', 'Suffering-Siblings'], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

for i in range(45):
    time.sleep(1)
    ret = p.poll()
    if (i + 1) % 5 == 0:
        print(f'Second {i+1}, poll={ret}')
    if (i + 1) == 20:
        try:
            img = ImageGrab.grab()
            img.save(shot_path)
            print(f'Saved screenshot at second 20 to {shot_path}')
        except Exception as e:
            print('Screenshot error:', e)
    if ret is not None:
        break

if p.poll() is None:
    print('Still running after 25s. Terminating...')
    p.kill()

stdout, stderr = p.communicate()
print('STDOUT:\n', stdout.decode('utf-8', 'replace')[-1500:])
print('STDERR:\n', stderr.decode('utf-8', 'replace'))
