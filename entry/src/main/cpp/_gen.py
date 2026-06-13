import os
cpp_dir = r"D:/HarmonyOS/DevEcoStudioProjects/Kazumi/entry/src/main/cpp"

def write_file(name, content):
    with open(os.path.join(cpp_dir, name), "w", encoding="utf-8", newline=chr(10)) as f:
        f.write(content)
    print(f"Created {name}")
