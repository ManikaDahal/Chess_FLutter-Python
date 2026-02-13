import os

path = r'c:\Users\User\Desktop\Manika\Chess_Manika\lib\ui\video_player_screen.dart'
try:
    with open(path, 'rb') as f:
        data = f.read(1000)
    print(f"Data repr: {repr(data)}")
    
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    print(f"First 10 lines: {[repr(l) for l in lines[:10]]}")
except Exception as e:
    print(f"Error: {e}")
