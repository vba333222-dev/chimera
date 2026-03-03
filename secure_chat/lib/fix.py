import os

ranges = {
    'models/chat_session.dart': (1, 37),
    'models/message.dart': (38, 73),
    'providers/providers.dart': (74, 171),
    'screens/biometric_login_screen.dart': (172, 635),
    'screens/chat_list_screen.dart': (636, 997),
    'screens/chat_room_screen.dart': (998, 1633),
    'screens/device_verification_screen.dart': (1634, 1940),
    'services/encryption_service.dart': (1941, 2034),
    'services/websocket_service.dart': (2035, 2109),
    'theme/app_theme.dart': (2110, 2185),
    'widgets/pixel_grid_background.dart': (2186, 2229),
    'widgets/scanline_overlay.dart': (2230, 2289),
    'widgets/terminal_container.dart': (2290, 2327),
}

base_dir = r"c:\Users\USER\Documents\Chimera 1.2\chimera\secure_chat\lib"
source_file = os.path.join(base_dir, "models", "message.dart")

with open(source_file, "r", encoding="utf-8") as f:
    lines = f.readlines()

for rel_path, (start, end) in ranges.items():
    file_path = os.path.join(base_dir, rel_path.replace("/", "\\"))
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    
    # Python slices are 0-indexed, end is exclusive
    chunk = lines[start - 1 : end]
    
    with open(file_path, "w", encoding="utf-8") as out_file:
        out_file.writelines(chunk)

print("Files have been restored.")
