import os

path = r'c:\Users\User\Desktop\Manika\Chess_Manika\lib\ui\video_player_screen.dart'
try:
    with open(path, 'rb') as f:
        content = f.read().decode('utf-16')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Successfully converted to UTF-8")
except Exception as e:
    print(f"Error: {e}")
