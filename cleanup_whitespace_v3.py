import os

path = r'c:\Users\User\Desktop\Manika\Chess_Manika\lib\ui\video_player_screen.dart'
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Strictly take every other line since it was doubled
    # But let's verify if indices 1, 3, 5... are indeed empty
    is_doubled = all(l.strip() == '' for l in lines[1::2])
    
    if is_doubled:
        new_lines = lines[::2]
        print("Confirmed strict doubling. Deduplicating...")
    else:
        # Fallback to smart filtering if not strictly doubled
        new_lines = []
        for line in lines:
            if line.strip() != '':
                new_lines.append(line)
            elif new_lines and new_lines[-1].strip() != '':
                new_lines.append(line)
        print("Not strictly doubled. Using smart filter.")

    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.writelines(new_lines)
    print(f"Final line count: {len(new_lines)}")
except Exception as e:
    print(f"Error: {e}")
