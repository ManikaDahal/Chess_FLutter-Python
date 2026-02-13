import os

path = r'c:\Users\User\Desktop\Manika\Chess_Manika\lib\ui\video_player_screen.dart'
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    for line in lines:
        # Replace the 500ms initial settled delay
        if 'await Future.delayed(const Duration(milliseconds: 500));' in line:
            new_lines.append(line.replace('500', '2500'))
        # Replace the 1000ms cleanup delay
        elif 'await Future.delayed(const Duration(milliseconds: 1000));' in line:
            new_lines.append(line.replace('1000', '2500'))
        else:
            new_lines.append(line)
            
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.writelines(new_lines)
    print("Successfully updated hardware delays")
except Exception as e:
    print(f"Error: {e}")
