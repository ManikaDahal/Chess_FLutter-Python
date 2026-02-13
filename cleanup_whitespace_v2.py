import os

path = r'c:\Users\User\Desktop\Manika\Chess_Manika\lib\ui\video_player_screen.dart'
try:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Normalize all \r\n to \n
    content = content.replace('\r\n', '\n').replace('\r', '\n')
    
    # Recursively replace double \n with single \n
    # Keep one \n\n if it was a double line break, but for now let's just collapse ALL blank lines to 1
    # Actually, let's just remove lines that are ONLY whitespace and follow another line break.
    lines = content.split('\n')
    new_lines = []
    
    for line in lines:
        if line.strip() == '':
            if not new_lines or new_lines[-1].strip() != '':
                new_lines.append('')
        else:
            new_lines.append(line)
            
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(new_lines))
    print(f"Successfully cleaned up whitespace. New line count: {len(new_lines)}")
except Exception as e:
    print(f"Error: {e}")
