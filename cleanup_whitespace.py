import os

path = r'c:\Users\User\Desktop\Manika\Chess_Manika\lib\ui\video_player_screen.dart'
try:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove redundant \r and then handle double \n
    content = content.replace('\r', '')
    # If the doubling was due to \r\n being treated as \n\n, this might help:
    while '\n\n\n' in content:
        content = content.replace('\n\n\n', '\n\n')
    
    # Even better, let's just strip every other line if it's strictly doubled
    lines = content.split('\n')
    # If the file size doubled, we can check if it's alternating empty lines
    if len(lines) > 1000:
        new_lines = []
        for i in range(len(lines)):
            if i % 2 == 0 or lines[i].strip() != '':
                new_lines.append(lines[i])
        # Wait, that's too risky. Let's just remove lines that are purely empty AND follow another empty line
        final_lines = []
        prev_empty = False
        for line in lines:
            if line.strip() == '':
                if not prev_empty:
                    final_lines.append(line)
                    prev_empty = True
            else:
                final_lines.append(line)
                prev_empty = False
        content = '\n'.join(final_lines)

    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)
    print("Successfully cleaned up whitespace")
except Exception as e:
    print(f"Error: {e}")
