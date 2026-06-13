import sys
import struct

def set_soname(filepath, new_soname):
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())
    
    # Find the ELF dynamic section and modify DT_SONAME
    # ELF64 header
    e_phoff = struct.unpack_from('<Q', data, 32)[0]
    e_phnum = struct.unpack_from('<H', data, 56)[0]
    e_phentsize = struct.unpack_from('<H', data, 54)[0]
    
    # Find PT_DYNAMIC
    dyn_offset = 0
    dyn_size = 0
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', data, off)[0]
        if p_type == 2:  # PT_DYNAMIC
            p_offset = struct.unpack_from('<Q', data, off + 8)[0]
            p_filesz = struct.unpack_from('<Q', data, off + 32)[0]
            dyn_offset = p_offset
            dyn_size = p_filesz
            break
    
    if dyn_offset == 0:
        print("No PT_DYNAMIC found")
        return False
    
    # Find DT_STRTAB and DT_STRSZ
    strtab_addr = 0
    strsz = 0
    soname_offset_in_strtab = -1
    
    # First pass: find STRTAB and STRSZ
    pos = dyn_offset
    while pos < dyn_offset + dyn_size:
        d_tag = struct.unpack_from('<q', data, pos)[0]
        d_val = struct.unpack_from('<Q', data, pos + 8)[0]
        if d_tag == 5:  # DT_STRTAB
            strtab_addr = d_val
        elif d_tag == 10:  # DT_STRSZ
            strsz = d_val
        pos += 16
    
    if strtab_addr == 0 or strsz == 0:
        print("No string table found")
        return False
    
    # Find the actual file offset of strtab (need to map virtual addr to file offset)
    strtab_file_offset = 0
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', data, off)[0]
        if p_type == 1:  # PT_LOAD
            p_vaddr = struct.unpack_from('<Q', data, off + 16)[0]
            p_offset = struct.unpack_from('<Q', data, off + 8)[0]
            p_filesz = struct.unpack_from('<Q', data, off + 32)[0]
            if p_vaddr <= strtab_addr < p_vaddr + p_filesz:
                strtab_file_offset = p_offset + (strtab_addr - p_vaddr)
                break
    
    # Find DT_SONAME
    pos = dyn_offset
    while pos < dyn_offset + dyn_size:
        d_tag = struct.unpack_from('<q', data, pos)[0]
        d_val = struct.unpack_from('<Q', data, pos + 8)[0]
        if d_tag == 14:  # DT_SONAME
            soname_str_offset = strtab_file_offset + d_val
            old_soname = b''
            j = soname_str_offset
            while data[j] != 0:
                old_soname += bytes([data[j]])
                j += 1
            print(f"Old SONAME: {old_soname.decode()}")
            
            new_bytes = new_soname.encode('ascii') + b'\x00'
            if len(new_bytes) > len(old_soname) + 1:
                print(f"Error: new soname ({len(new_bytes)}) is longer than old ({len(old_soname)+1})")
                return False
            
            # Write new soname
            for k in range(len(new_bytes)):
                data[soname_str_offset + k] = new_bytes[k]
            # Zero fill remaining
            for k in range(len(new_bytes), len(old_soname) + 1):
                data[soname_str_offset + k] = 0
            
            with open(filepath, 'wb') as f:
                f.write(data)
            print(f"New SONAME: {new_soname}")
            return True
        pos += 16
    
    print("DT_SONAME not found")
    return False

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: set_soname.py <path_to_so> <new_soname>")
        sys.exit(1)
    set_soname(sys.argv[1], sys.argv[2])