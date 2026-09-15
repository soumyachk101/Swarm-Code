import struct, zlib

def chunk(ctype, data):
 c = ctype + data
 return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

def make_png(width, height, rgba_data):
 header = b'\x89PNG\r\n\x1a\n'
 ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
 raw = bytearray()
 for y in range(height):
 raw.append(0)
 for x in range(width):
 i = (y * width + x) * 4
 raw.extend(rgba_data[i:i+4])
 compressed = zlib.compress(bytes(raw))
 return header + chunk(b'IHDR', ihdr) + chunk(b'IDAT', compressed) + chunk(b'IEND', b'')

base = '/Users/soumyachakraborty/Documents/droppy-code/SwarmAI_tauri/src-tauri/icons'

def make_icon(sz, name):
 cx, cy = sz // 2, sz // 2
 r = sz // 2 - 2
 pixels = []
 for y in range(sz):
 for x in range(sz):
 dx, dy = x - cx, y - cy
 dist = (dx * dx + dy * dy) ** 0.5
 if dist <= r:
 pixels.extend([99, 102, 241, 255])
 else:
 pixels.extend([0, 0, 0, 0])
 data = make_png(sz, sz, pixels)
 with open(f'{base}/{name}', 'wb') as f:
 f.write(data)

make_icon(32, '32x32.png')
print('Created 32x32.png')
make_icon(128, '128x128.png')
print('Created 128x128.png')
make_icon(256, '128x128@2x.png')
print('Created 128x128@2x.png')
make_icon(256, '256x256.png')
print('Created 256x256.png')
