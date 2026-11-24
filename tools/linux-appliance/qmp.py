#!/usr/bin/env python3
"""QMP for the appliance's QEMU (run.sh, LINUX_QMP): qmp.py SOCKET COMMAND...

  screendump FILE.png        the guest's screen (the KMS scanout), whatever QEMU's display
  key KEY...                 press and release keys (QEMU's qcode names: a, ret, shift, ctrl, f1, ...), in order
  type TEXT                  type text (letters, digits, space, a few punctuation marks)
  click X Y [BUTTON]         move the tablet to X, Y (pixels of a 1920x1080 screen) and click (left, right, middle)
  move X Y                   move the tablet only
  powerdown | quit           ACPI power button | stop QEMU
"""
import json, socket, sys, time

def connect(path):
    s = socket.socket(socket.AF_UNIX); s.connect(path)
    f = s.makefile('rw')
    json.loads(f.readline())
    def cmd(name, **args):
        f.write(json.dumps({'execute': name, 'arguments': args} if args else {'execute': name}) + '\n'); f.flush()
        while True:
            r = json.loads(f.readline())
            if 'return' in r or 'error' in r:
                if 'error' in r: raise SystemExit(f'qmp: {name}: {r["error"]}')
                return r['return']
    cmd('qmp_capabilities')
    return cmd

CHARS = {' ': 'spc', '.': 'dot', ',': 'comma', '-': 'minus', '=': 'equal', '/': 'slash', ';': 'semicolon', "'": 'apostrophe',
         '\n': 'ret', '+': ('shift', 'equal'), ':': ('shift', 'semicolon'), '(': ('shift', '9'), ')': ('shift', '0'), '*': ('shift', '8')}

def keys(cmd, names, hold=()):
    ev = lambda k, down: {'type': 'key', 'data': {'down': down, 'key': {'type': 'qcode', 'data': k}}}
    cmd('input-send-event', events=[ev(k, True) for k in hold] + [ev(n, True) for n in names])
    time.sleep(0.03)
    cmd('input-send-event', events=[ev(n, False) for n in names] + [ev(k, False) for k in hold])
    time.sleep(0.03)

def move(cmd, x, y):
    abs_ = lambda axis, v: {'type': 'abs', 'data': {'axis': axis, 'value': int(v * 32767 / (1919 if axis == 'x' else 1079))}}
    cmd('input-send-event', events=[abs_('x', x), abs_('y', y)])

def main():
    cmd = connect(sys.argv[1]); op, args = sys.argv[2], sys.argv[3:]
    if op == 'screendump': cmd('screendump', filename=args[0], format='png')
    elif op == 'key':
        for k in args: keys(cmd, [k])
    elif op == 'type':
        for c in ' '.join(args):
            k = CHARS.get(c, c.lower())
            if isinstance(k, tuple): keys(cmd, [k[1]], hold=(k[0],))
            elif c.isupper(): keys(cmd, [k], hold=('shift',))
            else: keys(cmd, [k])
    elif op in ('click', 'move'):
        move(cmd, float(args[0]), float(args[1])); time.sleep(0.05)
        if op == 'click':
            b = args[2] if len(args) > 2 else 'left'
            for down in (True, False):
                cmd('input-send-event', events=[{'type': 'btn', 'data': {'down': down, 'button': b}}]); time.sleep(0.05)
    elif op == 'powerdown': cmd('system_powerdown')
    elif op == 'quit': cmd('quit')
    else: raise SystemExit(__doc__)

main()
