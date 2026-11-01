#!/usr/bin/python
# Runs on the build Mac with the system Python 2.7. Copies RemotePanel crash
# logs off the USB-connected iPad through the com.apple.crashreportcopymobile
# lockdown service, using the private MobileDevice.framework via ctypes.
# Writes logs to ~/rp-crash/ and prints their names.
import ctypes, ctypes.util, os, sys, time

MD = ctypes.CDLL('/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice')
CF = ctypes.CDLL(ctypes.util.find_library('CoreFoundation'))
CF.CFStringCreateWithCString.restype = ctypes.c_void_p
CF.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
def cfstr(s): return CF.CFStringCreateWithCString(None, s, 0x08000100)

UDID = sys.argv[1] if len(sys.argv) > 1 else ''
OUT = os.path.expanduser('~/rp-crash')
if not os.path.isdir(OUT): os.makedirs(OUT)

CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
found = []
def on_note(info, arg):
    dev = ctypes.cast(info, ctypes.POINTER(ctypes.c_void_p))[0]
    found.append(dev)
cb = CB(on_note)
notif = ctypes.c_void_p()
MD.AMDeviceNotificationSubscribe(cb, 0, 0, None, ctypes.byref(notif))
CF.CFRunLoopRunInMode.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_bool]
mode = ctypes.c_void_p.in_dll(CF, 'kCFRunLoopDefaultMode')
deadline = time.time() + 8
while time.time() < deadline and not found:
    CF.CFRunLoopRunInMode(mode, 0.5, False)

MD.AMDeviceCopyDeviceIdentifier.restype = ctypes.c_void_p
CF.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
MD.AMDeviceGetInterfaceType.restype = ctypes.c_int
dev = None
for d in found:
    buf = ctypes.create_string_buffer(128)
    CF.CFStringGetCString(MD.AMDeviceCopyDeviceIdentifier(ctypes.c_void_p(d)), buf, 128, 0x08000100)
    if (not UDID or buf.value == UDID) and MD.AMDeviceGetInterfaceType(ctypes.c_void_p(d)) == 1:  # 1 = USB
        dev = ctypes.c_void_p(d); break
if dev is None:
    print('NO_USB_DEVICE'); sys.exit(2)

for fn in ('AMDeviceConnect', 'AMDeviceValidatePairing', 'AMDeviceStartSession'):
    rc = getattr(MD, fn)(dev)
    if rc != 0: print('%s failed %d' % (fn, rc)); sys.exit(3)

# Move pending reports into the copy area first (crashreportmover), then copy.
conn = ctypes.c_void_p()
MD.AMDeviceStartService.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p]
if MD.AMDeviceStartService(dev, cfstr('com.apple.crashreportmover'), ctypes.byref(conn), None) == 0:
    time.sleep(2)
rc = MD.AMDeviceStartService(dev, cfstr('com.apple.crashreportcopymobile'), ctypes.byref(conn), None)
if rc != 0: print('copymobile start failed %d' % rc); sys.exit(4)

AFC = MD
AFC.AFCConnectionOpen.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
afc = ctypes.c_void_p()
if AFC.AFCConnectionOpen(conn, 0, ctypes.byref(afc)) != 0: print('AFC open failed'); sys.exit(5)

AFC.AFCDirectoryOpen.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
AFC.AFCDirectoryRead.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
AFC.AFCFileRefOpen.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint64, ctypes.POINTER(ctypes.c_uint64)]
AFC.AFCFileRefRead.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
AFC.AFCFileRefClose.argtypes = [ctypes.c_void_p, ctypes.c_uint64]

def listdir(path):
    h = ctypes.c_void_p(); names = []
    if AFC.AFCDirectoryOpen(afc, path, ctypes.byref(h)) != 0: return names
    while True:
        p = ctypes.c_char_p()
        AFC.AFCDirectoryRead(afc, h, ctypes.byref(p))
        if not p.value: break
        if p.value not in ('.', '..'): names.append(p.value)
    return names

def read(path):
    fh = ctypes.c_uint64()
    if AFC.AFCFileRefOpen(afc, path, 1, ctypes.byref(fh)) != 0: return None
    out = []; buf = ctypes.create_string_buffer(65536)
    while True:
        n = ctypes.c_uint32(65536)
        if AFC.AFCFileRefRead(afc, fh.value, buf, ctypes.byref(n)) != 0 or n.value == 0: break
        out.append(buf.raw[:n.value])
    AFC.AFCFileRefClose(afc, fh.value)
    return ''.join(out)

hits = []
for name in listdir('/'):
    low = name.lower()
    if 'remotepanel' in low or low.startswith('jetsamevent') or low.startswith('lowmemory'):
        hits.append(name)
hits.sort()
for name in hits[-12:]:
    data = read('/' + name)
    if data is None: continue
    open(os.path.join(OUT, name), 'wb').write(data)
    print(name)
print('DONE %d' % len(hits))
