import sys
import os

def fix_needed(filepath):
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())
    
    old = b'libmpv.so.2\x00'
    new = b'libmpv.so\x00\x00\x00'
    
    count = 0
    pos = 0
    while True:
        pos = data.find(old, pos)
        if pos == -1:
            break
        data[pos:pos+len(old)] = new
        count += 1
        pos += len(old)
    
    if count > 0:
        with open(filepath, 'wb') as f:
            f.write(data)
        print(f"Fixed {count} NEEDED reference(s): libmpv.so.2 -> libmpv.so")
    else:
        print("No libmpv.so.2 NEEDED reference found")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix_needed.py <path_to_so>")
        sys.exit(1)
    fix_needed(sys.argv[1])