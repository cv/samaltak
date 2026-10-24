#!/usr/bin/env python3
"""Samaltak seed bootstrapper: compiles src/**/*.st (chunk format) into a seed image.

usage: bootstrap.py SRC_DIR OUT_IMAGE
"""
import os
import re
import struct
import sys
from fractions import Fraction

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASK64 = (1 << 64) - 1
INT_MIN, INT_MAX = -(1 << 62), (1 << 62) - 1
BASE = 0x100000


def load_vm_constants():
    """The VM's exported constants: the #defines and enums between the BEGIN/END EXPORTED CONSTANTS markers of
    vm/src/vm.h (the C side of the definition; the image's is the VMConstants class)."""
    path = os.path.join(ROOT, 'vm/src/vm.h')
    text = open(path, encoding='utf-8').read()
    m = re.search(r'/\* BEGIN EXPORTED CONSTANTS \*/(.*?)/\* END EXPORTED CONSTANTS \*/', text, re.S)
    if not m:
        raise SystemExit(f'bootstrap: error: {path}: no EXPORTED CONSTANTS block')
    body = re.sub(r'/\*.*?\*/', ' ', m.group(1), flags=re.S)
    consts = {}

    def value(expr):
        expr = re.sub(r'\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]+\b', r'\1', expr.strip())
        return int(eval(expr, {'__builtins__': {}}, dict(consts)))

    for d in re.finditer(r'^\s*#define\s+(\w+)\s+(.+)$', body, re.M):
        consts[d.group(1)] = value(d.group(2))
    for e in re.finditer(r'\benum\s*\{(.*?)\}', body, re.S):
        nxt = 0
        for item in filter(None, (i.strip() for i in e.group(1).split(','))):
            name, _, expr = item.partition('=')
            nxt = value(expr) if expr else nxt
            consts[name.strip()] = nxt
            nxt += 1
    return consts


VMC = load_vm_constants()
F_EMPTY, F_FIXED, F_VAR, F_FIXVAR, F_WEAK, F_IMMEDIATE, F_W64, F_W32, F_BYTES = (VMC[n] for n in (
    'F_EMPTY', 'F_FIXED', 'F_VAR', 'F_FIXVAR', 'F_WEAK', 'F_IMMEDIATE', 'F_W64', 'F_W32', 'F_BYTES'))
CTX_SLACK = VMC['CTX_SLACK']

SPECIAL_SELECTORS = ['+', '-', '<', '>', '<=', '>=', '=', '~=', '*', '/', '\\\\', '@', 'bitShift:', '//', 'bitAnd:',
                     'bitOr:', 'at:', 'at:put:', 'size', '==', '~~', 'value', 'value:', 'isNil', 'notNil', 'new',
                     'new:', 'x', 'y', 'class', 'value:value:', 'max:']
SPECIAL_INDEX = {s: i for i, s in enumerate(SPECIAL_SELECTORS)}

VM_LAYOUTS = {
    'Behavior': 'superclass methodDict format',
    'ClassDescription': 'superclass methodDict format instanceVariables organization',
    'Class': 'superclass methodDict format instanceVariables organization subclasses name classPool sharedPools package comment',
    'Metaclass': 'superclass methodDict format instanceVariables organization thisClass',
    'MethodDictionary': 'tally keys values',
    'CompiledMethod': 'selector methodClass literals bytecodes numArgs numTemps frameSize primitive',
    'Context': 'sender pc stackp method closureOrNil receiver',
    'BlockClosure': 'outerContext startpc numArgs numTemps frameSize',
    'Process': 'nextLink suspendedContext priority myList name cpuTime',
    'ProcessorScheduler': 'quiescentProcessLists activeProcess',
    'LinkedList': 'firstLink lastLink',
    'Semaphore': 'firstLink lastLink excessSignals',
    'Association': 'key value',
    'Message': 'selector arguments',
    'Point': 'x y',
}
REQUIRED_CLASSES = ['Object', 'Behavior', 'ClassDescription', 'Class', 'Metaclass', 'UndefinedObject', 'True', 'False',
                    'SmallInteger', 'Character', 'SmallFloat64', 'BoxedFloat64', 'Array', 'ByteArray', 'ByteString',
                    'ByteSymbol', 'WideString', 'WideSymbol', 'CompiledMethod', 'Context', 'BlockClosure', 'Process',
                    'ProcessorScheduler', 'LinkedList', 'Semaphore', 'Association', 'Message', 'Point',
                    'LargePositiveInteger', 'LargeNegativeInteger', 'MethodDictionary', 'SystemDictionary',
                    'Dictionary']


class CompileError(Exception):
    def __init__(self, msg, file='?', line=0):
        super().__init__(msg)
        self.msg, self.file, self.line = msg, file, line

    def __str__(self):
        return f'{self.file}:{self.line}: {self.msg}'


# ---------------------------------------------------------------- literal values

class Sym(str):
    pass


class Chr:
    __slots__ = ('cp',)

    def __init__(self, cp):
        self.cp = cp

    def __eq__(self, o):
        return isinstance(o, Chr) and o.cp == self.cp

    def __hash__(self):
        return hash(('chr', self.cp))


class Const:
    def __init__(self, name):
        self.name = name

    def __repr__(self):
        return self.name


NIL, TRUE, FALSE = Const('nil'), Const('true'), Const('false')


def lit_key(v):
    if isinstance(v, Const):
        return ('const', v.name)
    if isinstance(v, Sym):
        return ('sym', str(v))
    if isinstance(v, str):
        return ('str', v)
    if isinstance(v, bool):
        raise TypeError('bool literal')
    if isinstance(v, int):
        return ('int', v)
    if isinstance(v, float):
        return ('float', struct.pack('<d', v))
    if isinstance(v, Chr):
        return ('chr', v.cp)
    if isinstance(v, tuple):
        return ('arr',) + tuple(lit_key(e) for e in v)
    if isinstance(v, bytes):
        return ('bytes', v)
    raise TypeError(repr(v))


# ---------------------------------------------------------------- scanner

BINARY_CHARS = set('+-*/\\<>=~@%&?,!')


class Tok:
    __slots__ = ('kind', 'val', 'pos', 'end')

    def __init__(self, kind, val, pos, end):
        self.kind, self.val, self.pos, self.end = kind, val, pos, end

    def __repr__(self):
        return f'{self.kind}:{self.val!r}'


def digit_value(c, radix):
    if '0' <= c <= '9':
        v = ord(c) - 48
    elif 'A' <= c <= 'Z':
        v = ord(c) - 55
    elif 'a' <= c <= 'z' and radix > 10:
        v = ord(c) - 87
    else:
        return 99
    return v


class Scanner:
    def __init__(self, src, err):
        self.src, self.err = src, err

    def tokens(self):
        src, n, i, out = self.src, len(self.src), 0, []
        while True:
            while i < n:
                if src[i].isspace():
                    i += 1
                elif src[i] == '"':
                    j = src.find('"', i + 1)
                    if j < 0:
                        self.err('unterminated comment', i)
                    i = j + 1
                else:
                    break
            if i >= n:
                out.append(Tok('eof', None, n, n))
                return out
            c, s = src[i], i
            if c.isalpha() or c == '_':
                j = i
                while j < n and (src[j].isalnum() or src[j] == '_'):
                    j += 1
                if j < n and src[j] == ':' and not (j + 1 < n and src[j + 1] == '='):
                    out.append(Tok('keyword', src[i:j + 1], s, j + 1))
                    i = j + 1
                else:
                    out.append(Tok('ident', src[i:j], s, j))
                    i = j
            elif c.isdigit():
                i = self.number(i, out)
            elif c == "'":
                v, i = self.string(i)
                out.append(Tok('str', v, s, i))
            elif c == '$':
                if i + 1 >= n:
                    self.err('character expected', i)
                out.append(Tok('chr', Chr(ord(src[i + 1])), s, i + 2))
                i += 2
            elif c == '#':
                j = i + 1
                while j < n and src[j] == '#':
                    j += 1
                d = src[j] if j < n else ''
                if d == '(':
                    out.append(Tok('lit_array', None, s, j + 1))
                    i = j + 1
                elif d == '[':
                    out.append(Tok('byte_array', None, s, j + 1))
                    i = j + 1
                elif d == "'":
                    v, i = self.string(j)
                    out.append(Tok('sym', Sym(v), s, i))
                elif d.isalpha() or d == '_':
                    k = j
                    while k < n and (src[k].isalnum() or src[k] in '_:'):
                        k += 1
                    out.append(Tok('sym', Sym(src[j:k]), s, k))
                    i = k
                elif d in BINARY_CHARS or d == '|':
                    k = j
                    while k < n and (src[k] in BINARY_CHARS or src[k] == '|'):
                        k += 1
                    out.append(Tok('sym', Sym(src[j:k]), s, k))
                    i = k
                else:
                    self.err('bad literal after #', i)
            elif c == ':':
                if i + 1 < n and src[i + 1] == '=':
                    out.append(Tok('assign', ':=', s, i + 2))
                    i += 2
                else:
                    out.append(Tok('colon', ':', s, i + 1))
                    i += 1
            elif c in '()[]{}.;^|':
                out.append(Tok(c, c, s, i + 1))
                i += 1
            elif c in BINARY_CHARS:
                j = i + 1
                while j < n and src[j] in BINARY_CHARS and not (src[j] == '-' and j + 1 < n and src[j + 1].isdigit()):
                    j += 1
                out.append(Tok('binary', src[i:j], s, j))
                i = j
            else:
                self.err(f'unexpected character {c!r}', i)

    def string(self, i):
        src, n, j, parts = self.src, len(self.src), i + 1, []
        while True:
            k = src.find("'", j)
            if k < 0:
                self.err('unterminated string', i)
            parts.append(src[j:k])
            if k + 1 < n and src[k + 1] == "'":
                parts.append("'")
                j = k + 2
            else:
                return ''.join(parts), k + 1

    def number(self, i, out):
        src, n, s = self.src, len(self.src), i
        j = i
        while j < n and src[j].isdigit():
            j += 1
        value, radix, neg = int(src[i:j]), 10, False
        if j < n and src[j] == 'r':
            radix = value
            if not 2 <= radix <= 36:
                self.err('bad radix', i)
            j += 1
            if j < n and src[j] == '-':
                neg, j = True, j + 1
            k = j
            while k < n and digit_value(src[k], radix) < radix:
                k += 1
            if k == j:
                self.err('digits expected', j)
            value, j = int(src[j:k], radix), k
        mant, scale, is_float = value, 0, False
        if j + 1 < n and src[j] == '.' and digit_value(src[j + 1], radix) < radix:
            k = j + 1
            while k < n and digit_value(src[k], radix) < radix:
                k += 1
            frac = src[j + 1:k]
            mant = value * radix ** len(frac) + int(frac, radix)
            scale, is_float, j = len(frac), True, k
        exp = 0
        if j < n and src[j] in 'edq':
            k = j + 1
            if k < n and src[k] == '-' and k + 1 < n and src[k + 1].isdigit():
                k += 1
            if k < n and src[k].isdigit():
                while k < n and src[k].isdigit():
                    k += 1
                exp, j = int(src[j + 1:k]), k
            elif not is_float and src[j] in 'dq' and radix == 10:
                j += 1  # 1.0d without exponent
        if neg:
            mant = -mant
        if is_float:
            v = float(Fraction(mant) * Fraction(radix) ** (exp - scale))
            out.append(Tok('float', v, s, j))
        else:
            v = Fraction(mant) * Fraction(radix) ** exp
            if v.denominator != 1:
                out.append(Tok('float', float(v), s, j))
            else:
                out.append(Tok('int', int(v), s, j))
        return j


# ---------------------------------------------------------------- AST

class Node:
    pos = 0


class Lit(Node):
    def __init__(self, value, pos=0):
        self.value, self.pos = value, pos


class Var(Node):
    def __init__(self, name, pos=0):
        self.name, self.pos = name, pos


class Assign(Node):
    def __init__(self, var, value, pos):
        self.var, self.value, self.pos = var, value, pos


class Send(Node):
    def __init__(self, rcv, sel, args, pos):
        self.rcv, self.sel, self.args, self.pos = rcv, sel, args, pos


class CascadeRcv(Node):
    pass


class Cascade(Node):
    def __init__(self, rcv, msgs, pos):
        self.rcv, self.msgs, self.pos = rcv, msgs, pos


class Block(Node):
    def __init__(self, args, temps, stmts, pos):
        self.args, self.temps, self.stmts, self.pos = args, temps, stmts, pos


class Return(Node):
    def __init__(self, value, pos):
        self.value, self.pos = value, pos


class Brace(Node):
    def __init__(self, elems, pos):
        self.elems, self.pos = elems, pos


class MethodNode:
    def __init__(self, sel, args, temps, pragmas, stmts):
        self.sel, self.args, self.temps, self.pragmas, self.stmts = sel, args, temps, pragmas, stmts


# ---------------------------------------------------------------- parser

class Parser:
    def __init__(self, src, file, line0):
        self.src, self.file, self.line0 = src, file, line0
        self.toks = Scanner(src, self.error).tokens()
        self.i = 0

    def error(self, msg, pos=None):
        if pos is None:
            pos = self.tok.pos
        raise CompileError(msg, self.file, self.line0 + self.src.count('\n', 0, pos))

    @property
    def tok(self):
        return self.toks[self.i]

    def peek(self, k=1):
        return self.toks[min(self.i + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def expect(self, kind, what=None):
        if self.tok.kind != kind:
            self.error(f'{what or kind} expected')
        return self.next()

    def is_binary(self, val=None):
        t = self.tok
        return (t.kind == 'binary' or t.kind == '|') and (val is None or t.val == val)

    # method := pattern body
    def parse_method(self):
        t = self.tok
        if t.kind == 'ident':
            self.next()
            sel, args = t.val, []
        elif t.kind in ('binary', '|'):
            self.next()
            sel, args = t.val, [self.expect('ident', 'argument name').val]
        elif t.kind == 'keyword':
            parts, args = [], []
            while self.tok.kind == 'keyword':
                parts.append(self.next().val)
                args.append(self.expect('ident', 'argument name').val)
            sel = ''.join(parts)
        else:
            self.error('method pattern expected')
        temps, pragmas = [], []
        while True:
            if self.is_binary('<'):
                pragmas.append(self.parse_pragma())
            elif self.tok.kind == '|':
                temps += self.parse_temps()
            else:
                break
        stmts = self.parse_statements('eof')
        return MethodNode(sel, args, temps, pragmas, stmts)

    def parse_temps(self):
        self.expect('|')
        names = []
        while self.tok.kind == 'ident':
            names.append(self.next().val)
        self.expect('|', "'|'")
        return names

    def parse_pragma(self):
        pos = self.next().pos
        if self.tok.kind == 'ident':
            sel, args = self.next().val, []
        else:
            parts, args = [], []
            while self.tok.kind == 'keyword':
                parts.append(self.next().val)
                if self.tok.kind == 'ident' and self.tok.val not in ('true', 'false', 'nil'):
                    args.append(Var(self.next().val))
                else:
                    args.append(self.parse_literal())
            if not parts:
                self.error('pragma expected')
            sel = ''.join(parts)
        if not self.is_binary('>'):
            self.error("'>' expected")
        self.next()
        return (sel, args, pos)

    def parse_literal(self):
        t = self.tok
        if t.kind in ('int', 'float', 'str', 'sym', 'chr'):
            self.next()
            return t.val
        if t.kind == 'binary' and t.val == '-' and self.peek().kind in ('int', 'float') and self.peek().pos == t.end:
            self.next()
            return -self.next().val
        if t.kind == 'ident' and t.val in ('true', 'false', 'nil'):
            self.next()
            return {'true': TRUE, 'false': FALSE, 'nil': NIL}[t.val]
        if t.kind == 'lit_array':
            self.next()
            return self.parse_literal_array_body()
        if t.kind == 'byte_array':
            self.next()
            return self.parse_byte_array_body()
        self.error('literal expected')

    def parse_literal_array_body(self):
        elems = []
        while True:
            t = self.tok
            if t.kind == ')':
                self.next()
                return tuple(elems)
            if t.kind == 'eof':
                self.error("')' expected")
            if t.kind in ('(', 'lit_array'):
                self.next()
                elems.append(self.parse_literal_array_body())
            elif t.kind in ('[', 'byte_array'):
                self.next()
                elems.append(self.parse_byte_array_body())
            elif t.kind == 'ident':
                self.next()
                elems.append({'true': TRUE, 'false': FALSE, 'nil': NIL}.get(t.val, Sym(t.val)))
            elif t.kind == 'keyword':
                s, end = self.next().val, t.end
                while self.tok.kind == 'keyword' and self.tok.pos == end:
                    end = self.tok.end
                    s += self.next().val
                elems.append(Sym(s))
            elif t.kind == 'binary' and not (t.val == '-' and self.peek().kind in ('int', 'float') and
                                             self.peek().pos == t.end):
                self.next()
                elems.append(Sym(t.val))
            elif t.kind == '|':
                self.next()
                elems.append(Sym('|'))
            else:
                elems.append(self.parse_literal())

    def parse_byte_array_body(self):
        out = bytearray()
        while self.tok.kind != ']':
            t = self.expect('int', 'byte')
            if not 0 <= t.val <= 255:
                self.error('byte out of range', t.pos)
            out.append(t.val)
        self.next()
        return bytes(out)

    def parse_statements(self, end):
        stmts = []
        while True:
            while self.tok.kind == '.':
                self.next()
            if self.tok.kind == end:
                self.next()
                return stmts
            if self.tok.kind == '^':
                pos = self.next().pos
                stmts.append(Return(self.parse_expression(), pos))
                while self.tok.kind == '.':
                    self.next()
                if self.tok.kind != end:
                    self.error('statement after return')
                continue
            stmts.append(self.parse_expression())
            if self.tok.kind == '.':
                continue
            if self.tok.kind != end:
                self.error(f"'{end}' expected" if end != 'eof' else 'end of method expected')

    def parse_expression(self):
        t = self.tok
        if t.kind == 'ident' and self.peek().kind == 'assign':
            self.next()
            self.next()
            return Assign(Var(t.val, t.pos), self.parse_expression(), t.pos)
        e = self.parse_messages(self.parse_primary())
        if self.tok.kind == ';':
            if not isinstance(e, Send):
                self.error('cascade without message')
            msgs = [Send(CascadeRcv(), e.sel, e.args, e.pos)]
            rcv = e.rcv
            while self.tok.kind == ';':
                self.next()
                m = self.parse_messages(CascadeRcv())
                if not isinstance(m, Send):
                    self.error('message expected in cascade')
                msgs.append(m)
            return Cascade(rcv, msgs, e.pos)
        return e

    def parse_unary(self, rcv):
        while self.tok.kind == 'ident':
            t = self.next()
            rcv = Send(rcv, t.val, [], t.pos)
        return rcv

    def parse_binary(self, rcv):
        while self.is_binary():
            t = self.next()
            rcv = Send(rcv, t.val, [self.parse_unary(self.parse_primary())], t.pos)
        return rcv

    def parse_messages(self, rcv):
        rcv = self.parse_binary(self.parse_unary(rcv))
        if self.tok.kind == 'keyword':
            pos, parts, args = self.tok.pos, [], []
            while self.tok.kind == 'keyword':
                parts.append(self.next().val)
                args.append(self.parse_binary(self.parse_unary(self.parse_primary())))
            rcv = Send(rcv, ''.join(parts), args, pos)
        return rcv

    def parse_primary(self):
        t = self.tok
        if t.kind == 'ident':
            self.next()
            if t.val in ('true', 'false', 'nil'):
                return Lit({'true': TRUE, 'false': FALSE, 'nil': NIL}[t.val], t.pos)
            return Var(t.val, t.pos)
        if t.kind in ('int', 'float', 'str', 'sym', 'chr', 'lit_array', 'byte_array') or (
                t.kind == 'binary' and t.val == '-' and self.peek().kind in ('int', 'float') and
                self.peek().pos == t.end):
            return Lit(self.parse_literal(), t.pos)
        if t.kind == '[':
            return self.parse_block()
        if t.kind == '(':
            self.next()
            e = self.parse_expression()
            self.expect(')', "')'")
            return e
        if t.kind == '{':
            self.next()
            elems = []
            while True:
                while self.tok.kind == '.':
                    self.next()
                if self.tok.kind == '}':
                    self.next()
                    return Brace(elems, t.pos)
                elems.append(self.parse_expression())
                if self.tok.kind not in ('.', '}'):
                    self.error("'}' expected")
        self.error('expression expected')

    def parse_block(self):
        pos = self.next().pos
        args = []
        while self.tok.kind == 'colon':
            self.next()
            args.append(self.expect('ident', 'block argument').val)
        if args and self.tok.kind != ']':
            self.expect('|', "'|'")
        temps = self.parse_temps() if self.tok.kind == '|' else []
        return Block(args, temps, self.parse_statements(']'), pos)


# ---------------------------------------------------------------- code generator

class RealScope:
    """A scope that owns a context: the method or a non-inlined block."""

    def __init__(self, is_block):
        self.is_block = is_block
        self.nslots = 0
        self.nargs = 0
        self.depth = 0
        self.max = 0

    def alloc(self):
        self.nslots += 1
        if self.nslots > 255:
            raise CompileError('too many temporaries')
        return self.nslots - 1


class Frame:
    def __init__(self, real, parent):
        self.real, self.parent, self.names, self.args = real, parent, {}, set()


class MethodCompiler:
    def __init__(self, image, cls, meta, file, line0, src, pkg):
        self.image, self.cls, self.meta, self.pkg = image, cls, meta, pkg
        self.file, self.line0, self.src = file, line0, src
        self.code = bytearray()
        self.lits, self.lit_index = [], {}
        # superinstructions (as the Smalltalk compiler's BytecodeEncoder): the last two pushes
        # (start, end, kind, operand) and the last pc anything may jump to or record
        self.pushes, self.barrier = [], 0

    def error(self, msg, pos):
        raise CompileError(msg, self.file, self.line0 + self.src.count('\n', 0, pos))

    # -- emission
    def emit(self, *bs, delta=0):
        self.code.extend(bs)
        self.adj(delta)

    def adj(self, d):
        r = self.real
        r.depth += d
        if r.depth > r.max:
            r.max = r.depth

    def set_depth(self, d):
        self.real.depth = d

    def here(self):
        self.barrier = len(self.code)
        return len(self.code)

    def note_push(self, kind, operand, start):
        self.pushes = (self.pushes + [(start, len(self.code), kind, operand)])[-2:]

    def fuse_send(self, special):
        """push temp; push temp | literal | int8; binary special send -> 16r97 / 16r98 / 16r99 temp operand op,
        for + - < > <= >= 16r9A / 16rF0 / 16rF6 + selector index, temp operand."""
        if not (0 <= special <= 16) or special == 11 or len(self.pushes) < 2:
            return False
        (s1, e1, k1, a), (s2, e2, k2, b) = self.pushes
        if not (e2 == len(self.code) and e1 == s2 and k1 == 'temp' and self.barrier <= s1 and a <= 255):
            return False
        if k2 == 'int':
            b &= 255
        if b > 255:
            return False
        del self.code[s1:]
        if special <= 5:
            self.code.extend(((0x9A if k2 == 'temp' else 0xF0 if k2 == 'lit' else 0xF6) + special, a, b))
        else:
            self.code.extend((0x97 if k2 == 'temp' else 0x98 if k2 == 'lit' else 0x99, a, b, 0xA0 + special))
        self.pushes = []
        return True

    def jump(self, op):
        p = self.here()
        self.emit(op, 0, 0, delta=0 if op == 0x90 else -1)
        return p

    def patch(self, p, target=None):
        off = (self.here() if target is None else target) - (p + 3)
        if not -32768 <= off <= 32767:
            raise CompileError('jump too far', self.file, self.line0)
        self.code[p + 1], self.code[p + 2] = off & 255, (off >> 8) & 255

    def jump_back(self, target, op=0x90):
        p = self.jump(op)
        self.patch(p, target)

    def literal(self, key, value):
        i = self.lit_index.get(key)
        if i is None:
            i = len(self.lits)
            if i > 255:
                raise CompileError('too many literals', self.file, self.line0)
            self.lits.append(value)
            self.lit_index[key] = i
        return i

    def const_index(self, v):
        return self.literal(lit_key(v), ('const', v))

    def assoc_index(self, assoc):
        return self.literal(('assoc', id(assoc)), ('assoc', assoc))

    def push_lit(self, v):
        start = len(self.code)
        if v is NIL:
            self.emit(0x73, delta=1)
        elif v is TRUE:
            self.emit(0x71, delta=1)
        elif v is FALSE:
            self.emit(0x72, delta=1)
        elif type(v) is int and v in (0, 1):
            self.emit(0x74 + v, delta=1)
            self.note_push('int', v, start)
        elif type(v) is int and -32768 <= v <= 32767:
            self.emit(0x93, v & 255, (v >> 8) & 255, delta=1)
            if -128 <= v <= 127:
                self.note_push('int', v, start)
        else:
            i = self.const_index(v)
            self.emit(0x20 + i if i < 32 else 0x82, *([] if i < 32 else [i]), delta=1)
            self.note_push('lit', i, start)

    def send(self, sel, argc, sup=False):
        if not sup and SPECIAL_INDEX.get(sel) is not None and selector_argc(sel) == argc:
            if argc == 1 and self.fuse_send(SPECIAL_INDEX[sel]):
                self.adj(-1)
                return
            self.emit(0xA0 + SPECIAL_INDEX[sel], delta=-argc)
            return
        l = self.const_index(Sym(sel))
        if sup:
            self.emit(0x8E, l, argc, delta=-argc)
        elif l < 16 and argc <= 2:
            self.emit(0xC0 + 16 * argc + l, delta=-argc)
        else:
            if argc > 255:
                raise CompileError('too many arguments', self.file, self.line0)
            self.emit(0x8D, l, argc, delta=-argc)

    # -- variables
    def lookup(self, name, pos):
        f, depth, real = self.frame, 0, self.frame.real
        while f:
            if f.real is not real:
                depth += 1
                real = f.real
            if name in f.names:
                return ('temp', depth, f.names[name], name in f.args)
            f = f.parent
        iv = self.image.inst_var_index(self.cls, self.meta, name)
        if iv is not None:
            return ('ivar', iv)
        assoc = self.image.resolve_binding(self.cls, name)
        if assoc is not None:
            if assoc is self.image.globals.get(name):
                self.image.layer_check(name, self.pkg, self.file, self.line0 + self.src.count('\n', 0, pos))
            return ('assoc', assoc)
        if name[:1].isupper():
            return ('assoc', self.image.undeclared(name, self.file, self.line0 + self.src.count('\n', 0, pos)))
        self.error(f'undefined variable {name}', pos)

    def push_var(self, node):
        n = node.name
        if n in ('self', 'super'):
            return self.emit(0x70, delta=1)
        if n == 'thisContext':
            return self.emit(0x76, delta=1)
        v = self.lookup(n, node.pos)
        if v[0] == 'temp':
            _, d, i, _ = v
            if d == 0:
                start = len(self.code)
                self.emit(i, delta=1) if i < 16 else self.emit(0x80, i, delta=1)
                self.note_push('temp', i, start)
            else:
                self.emit(0x8A, d, i, delta=1)
        elif v[0] == 'ivar':
            i = v[1]
            self.emit(0x10 + i, delta=1) if i < 16 else self.emit(0x81, i, delta=1)
        else:
            i = self.assoc_index(v[1])
            self.emit(0x40 + i, delta=1) if i < 32 else self.emit(0x83, i, delta=1)

    def store_var(self, node, pop):
        n = node.name
        if n in ('self', 'super', 'thisContext', 'nil', 'true', 'false'):
            self.error(f'cannot assign to {n}', node.pos)
        v = self.lookup(n, node.pos)
        if v[0] == 'temp':
            _, d, i, is_arg = v
            if is_arg:
                self.error(f'cannot assign to argument {n}', node.pos)
            if d == 0:
                if pop:
                    self.emit(0x60 + i, delta=-1) if i < 8 else self.emit(0x87, i, delta=-1)
                else:
                    self.emit(0x84, i)
            else:
                self.emit(0x8C if pop else 0x8B, d, i, delta=-1 if pop else 0)
        elif v[0] == 'ivar':
            self.emit(0x85, v[1])
            if pop:
                self.emit(0x78, delta=-1)
        else:
            i = self.assoc_index(v[1])
            self.emit(0x89 if pop else 0x86, i, delta=-1 if pop else 0)

    # -- expressions
    def value(self, node):
        if isinstance(node, Lit):
            self.push_lit(node.value)
        elif isinstance(node, Var):
            self.push_var(node)
        elif isinstance(node, Assign):
            self.value(node.value)
            self.store_var(node.var, False)
        elif isinstance(node, Send):
            self.gen_send(node)
        elif isinstance(node, Cascade):
            self.gen_cascade(node)
        elif isinstance(node, Block):
            self.gen_block(node)
        elif isinstance(node, Brace):
            if len(node.elems) > 255:
                self.error('brace array too large', node.pos)
            for e in node.elems:
                self.value(e)
            self.emit(0x94, len(node.elems), delta=1 - len(node.elems))
        else:
            self.error('unexpected node', getattr(node, 'pos', 0))

    def effect(self, node):
        if isinstance(node, Assign):
            self.value(node.value)
            self.store_var(node.var, True)
        elif isinstance(node, Lit):
            pass
        elif isinstance(node, Var):
            if node.name not in ('self', 'super', 'thisContext'):
                self.lookup(node.name, node.pos)
        else:
            self.value(node)
            self.emit(0x78, delta=-1)

    def gen_return(self, node):
        if not self.real.is_block and isinstance(node.value, Var) and node.value.name == 'self':
            self.emit(0x7A)
            return
        self.value(node.value)
        self.emit(0x7C if self.real.is_block else 0x79, delta=-1)

    def statements_value(self, stmts):
        """Leaves one value (unreachable after a return, but depth stays consistent)."""
        base = self.real.depth
        if not stmts:
            self.push_lit(NIL)
        for k, s in enumerate(stmts):
            if isinstance(s, Return):
                self.gen_return(s)
                self.set_depth(base + 1)
                return True
            if k == len(stmts) - 1:
                self.value(s)
            else:
                self.effect(s)
        return False

    def gen_send(self, node):
        rcv = node.rcv
        sup = isinstance(rcv, Var) and rcv.name == 'super'
        if not sup:
            inl = INLINERS.get(node.sel)
            if inl and inl(self, node):
                return
        self.value(rcv)
        for a in node.args:
            self.value(a)
        self.send(node.sel, len(node.args), sup)

    def gen_cascade(self, node):
        sup = isinstance(node.rcv, Var) and node.rcv.name == 'super'
        self.value(node.rcv)
        for k, m in enumerate(node.msgs):
            last = k == len(node.msgs) - 1
            if not last:
                self.emit(0x77, delta=1)
            self.cascade_part(m, sup)
            if not last:
                self.emit(0x78, delta=-1)

    def cascade_part(self, m, sup):
        if isinstance(m.rcv, CascadeRcv):
            for a in m.args:
                self.value(a)
            self.send(m.sel, len(m.args), sup)
        else:
            self.cascade_part(m.rcv, sup)
            for a in m.args:
                self.value(a)
            self.send(m.sel, len(m.args))

    def declare(self, frame, name, idx, pos, is_arg=False):
        if name in frame.names:
            self.error(f'duplicate variable {name}', pos)
        frame.names[name] = idx
        if is_arg:
            frame.args.add(name)

    def gen_block(self, node):
        if len(node.args) > 255:
            self.error('too many block arguments', node.pos)
        p = self.here()
        self.emit(0x8F, len(node.args), 0, 0, 0, 0, delta=1)
        outer_frame, outer_real = self.frame, self.real
        real = RealScope(True)
        self.real, self.frame = real, Frame(real, outer_frame)
        for a in node.args:
            self.declare(self.frame, a, real.alloc(), node.pos, True)
        real.nargs = len(node.args)
        for t in node.temps:
            self.declare(self.frame, t, real.alloc(), node.pos)
        if not self.statements_value(node.stmts):
            self.emit(0x7B, delta=-1)
        ntemps, fsize = real.nslots - real.nargs, real.nslots + real.max
        if ntemps > 255 or fsize > 255:
            self.error('block frame too large', node.pos)
        size = self.here() - (p + 6)
        if size > 0xFFFF:
            self.error('block too large', node.pos)
        self.code[p + 2], self.code[p + 3] = ntemps, fsize
        self.code[p + 4], self.code[p + 5] = size >> 8, size & 255
        self.frame, self.real = outer_frame, outer_real

    def inlined(self, block, arg_slots=()):
        """Generates a literal block's body in the current context; leaves its value."""
        outer = self.frame
        self.frame = Frame(self.real, outer)
        for a, s in zip(block.args, arg_slots):
            self.declare(self.frame, a, s, block.pos, True)
        for t in block.temps:
            i = self.real.alloc()
            self.declare(self.frame, t, i, block.pos)
            self.push_lit(NIL)
            self.emit(0x60 + i if i < 8 else 0x87, *([] if i < 8 else [i]), delta=-1)
        self.statements_value(block.stmts)
        self.frame = outer

    # -- method
    def compile(self, m, prim, error_temp):
        self.real = RealScope(False)
        self.frame = Frame(self.real, None)
        for a in m.args:
            self.declare(self.frame, a, self.real.alloc(), 0, True)
        self.real.nargs = len(m.args)
        if error_temp:
            self.declare(self.frame, error_temp, self.real.alloc(), 0)
        for t in m.temps:
            self.declare(self.frame, t, self.real.alloc(), 0)
        ended = False
        for s in m.stmts:
            if isinstance(s, Return):
                self.gen_return(s)
                ended = True
                break
            self.effect(s)
        if not ended:
            self.emit(0x7A)
        r = self.real
        return dict(numArgs=r.nargs, numTemps=r.nslots - r.nargs, frameSize=r.nslots + r.max)


def is_block(node, nargs):
    return isinstance(node, Block) and len(node.args) == nargs


def inline_if(c, node):
    if not all(is_block(b, 0) for b in node.args):
        return False
    c.value(node.rcv)
    first_true = node.sel.startswith('ifTrue:')
    j = c.jump(0x92 if first_true else 0x91)
    d = c.real.depth
    c.inlined(node.args[0])
    j2 = c.jump(0x90)
    c.patch(j)
    c.set_depth(d)
    if len(node.args) == 2:
        c.inlined(node.args[1])
    else:
        c.push_lit(NIL)
    c.patch(j2)
    return True


def inline_and_or(c, node):
    if not is_block(node.args[0], 0):
        return False
    c.value(node.rcv)
    is_and = node.sel == 'and:'
    j = c.jump(0x92 if is_and else 0x91)
    d = c.real.depth
    c.inlined(node.args[0])
    j2 = c.jump(0x90)
    c.patch(j)
    c.set_depth(d)
    c.push_lit(FALSE if is_and else TRUE)
    c.patch(j2)
    return True


def inline_while(c, node):
    if not is_block(node.rcv, 0) or (node.args and not is_block(node.args[0], 0)):
        return False
    top = c.here()
    c.inlined(node.rcv)
    if not node.args:
        c.jump_back(top, 0x91 if node.sel == 'whileTrue' else 0x92)
        c.push_lit(NIL)
        return True
    j = c.jump(0x92 if node.sel.startswith('whileTrue') else 0x91)
    c.inlined(node.args[0])
    c.emit(0x78, delta=-1)
    c.jump_back(top)
    c.patch(j)
    c.push_lit(NIL)
    return True


def inline_repeat(c, node):
    if not is_block(node.rcv, 0):
        return False
    top = c.here()
    d = c.real.depth
    c.inlined(node.rcv)
    c.emit(0x78, delta=-1)
    c.jump_back(top)
    c.set_depth(d)
    c.push_lit(NIL)
    return True


def inline_to_do(c, node):
    block = node.args[-1]
    step = 1
    if len(node.args) == 3:
        s = node.args[1]
        if not (isinstance(s, Lit) and type(s.value) is int and s.value != 0):
            return False
        step = s.value
    if not is_block(block, 1):
        return False
    limit = node.args[0]
    c.value(node.rcv)
    var = c.real.alloc()
    c.emit(0x60 + var if var < 8 else 0x87, *([] if var < 8 else [var]), delta=-1)
    lim_lit = isinstance(limit, Lit) and type(limit.value) is int
    if not lim_lit:
        c.value(limit)
        lim = c.real.alloc()
        c.emit(0x60 + lim if lim < 8 else 0x87, *([] if lim < 8 else [lim]), delta=-1)
    def test():  # before the loop and again at its bottom: one jump per iteration
        push_t(c, var)
        if lim_lit:
            c.push_lit(limit.value)
        else:
            push_t(c, lim)
        c.send('<=' if step > 0 else '>=', 1)
    test()
    j = c.jump(0x92)
    top = c.here()
    c.inlined(block, [var])
    c.emit(0x78, delta=-1)
    push_t(c, var)
    c.push_lit(step)
    c.send('+', 1)
    c.emit(0x60 + var if var < 8 else 0x87, *([] if var < 8 else [var]), delta=-1)
    test()
    c.jump_back(top, 0x91)
    c.patch(j)
    c.push_lit(NIL)
    return True


def push_t(c, i):
    start = len(c.code)
    c.emit(i, delta=1) if i < 16 else c.emit(0x80, i, delta=1)
    c.note_push('temp', i, start)


def pop_t(c, i):
    c.emit(0x60 + i if i < 8 else 0x87, *([] if i < 8 else [i]), delta=-1)


def inline_if_nil(c, node):
    sel, args = node.sel, node.args
    parts = sel.split(':')[:-1]
    blocks = dict(zip(parts, args))
    nil_b, notnil_b = blocks.get('ifNil'), blocks.get('ifNotNil')
    if nil_b is not None and not is_block(nil_b, 0):
        return False
    if notnil_b is not None and not (is_block(notnil_b, 0) or is_block(notnil_b, 1)):
        return False
    c.value(node.rcv)
    c.emit(0x77, delta=1)
    c.push_lit(NIL)
    c.send('==', 1)
    d = c.real.depth - 1

    def not_nil_branch():
        if notnil_b.args:
            s = c.real.alloc()
            pop_t(c, s)
            c.inlined(notnil_b, [s])
        else:
            c.emit(0x78, delta=-1)
            c.inlined(notnil_b)

    def nil_branch():
        c.emit(0x78, delta=-1)
        c.inlined(nil_b)

    if notnil_b is None:
        j = c.jump(0x92)
        nil_branch()
        c.patch(j)
    elif nil_b is None:
        j = c.jump(0x91)
        not_nil_branch()
        c.patch(j)
    else:
        first_nil = parts[0] == 'ifNil'
        j = c.jump(0x92 if first_nil else 0x91)
        (nil_branch if first_nil else not_nil_branch)()
        j2 = c.jump(0x90)
        c.patch(j)
        c.set_depth(d + 1)
        (not_nil_branch if first_nil else nil_branch)()
        c.patch(j2)
    c.set_depth(d + 1)
    return True


INLINERS = {
    'ifTrue:': inline_if, 'ifFalse:': inline_if, 'ifTrue:ifFalse:': inline_if, 'ifFalse:ifTrue:': inline_if,
    'and:': inline_and_or, 'or:': inline_and_or,
    'whileTrue:': inline_while, 'whileFalse:': inline_while, 'whileTrue': inline_while, 'whileFalse': inline_while,
    'repeat': inline_repeat, 'to:do:': inline_to_do, 'to:by:do:': inline_to_do,
    'ifNil:': inline_if_nil, 'ifNotNil:': inline_if_nil, 'ifNil:ifNotNil:': inline_if_nil,
    'ifNotNil:ifNil:': inline_if_nil,
}


def selector_argc(sel):
    if not sel:
        return 0
    if sel[0].isalpha() or sel[0] == '_':
        return sel.count(':')
    return 1


# ---------------------------------------------------------------- object model

class Obj:
    __slots__ = ('cls', 'fmt', 'slots', 'data', 'hash', 'immutable', 'addr', 'tag')

    def __init__(self, cls, fmt, slots=None, data=None):
        self.cls, self.fmt, self.slots, self.data = cls, fmt, slots, data
        self.hash = 0
        self.immutable = False
        self.addr = 0
        self.tag = None

    def nslots(self):
        f = self.fmt
        if f <= F_WEAK:
            return len(self.slots)
        if f == F_W64:
            return len(self.data)
        if f == F_W32:
            return (len(self.data) + 1) // 2
        return (len(self.data) + 7) // 8


def smallfloat_bits(v):
    b = struct.unpack('<Q', struct.pack('<d', v))[0]
    if (b << 1) & MASK64 == 0:
        return ((b >> 63) << 3) | 4
    e = (b >> 52) & 0x7FF
    if 896 < e < 1151:
        r = (((b << 1) | (b >> 63)) & MASK64) - (896 << 53)
        return ((r << 3) & MASK64) | 4
    return None


def fnv_hash(s):
    h = 2166136261
    for ch in s:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h & 0x3FFFFFFF


class ClassDef:
    def __init__(self, name, sup, kind, ivars, cvars, package, file, line):
        self.name, self.sup, self.kind, self.ivars, self.cvars = name, sup, kind, ivars, cvars
        self.package, self.file, self.line = package, file, line
        self.src_pkg = None  # the package (src/ directory) the definition was read from
        self.class_ivars = []
        self.comment = None
        self.obj = self.meta = None
        self.all_ivars = self.meta_ivars = None
        self.inst_spec = 0
        self.pool = {}  # name -> association Obj
        self.methods, self.class_methods = {}, {}


DEF_KINDS = {'subclass:': 'fixed', 'variableSubclass:': 'pointers', 'variableByteSubclass:': 'bytes',
             'variableWordSubclass:': 'words', 'variableDoubleWordSubclass:': 'doublewords',
             'weakSubclass:': 'weak', 'immediateSubclass:': 'immediate'}


class Image:
    def __init__(self, src_dir):
        self.src_dir = src_dir
        self.objects = []
        self.seed = 0x5A4D414C54414B
        self.classes = {}
        self.order = []
        self.symbols = {}
        self.globals = {}  # name -> association
        self.undeclared_map = {}
        self.global_decls = []
        self.method_chunks = []
        self.packages = []
        self.layers, self.uses, self.exports = {}, {}, {}  # packages.txt: layer, uses, (package, global) -> layer
        self.layer_errors = []
        self.prims = load_primitives()
        self.warnings = 0

    def warn(self, msg):
        self.warnings += 1
        print(f'bootstrap: warning: {msg}', file=sys.stderr)

    def next_hash(self):
        self.seed = (self.seed * 6364136223846793005 + 1442695040888963407) & MASK64
        return ((self.seed >> 40) & VMC['H_HASH_MASK']) or 1

    def new(self, cls, fmt, slots=None, data=None):
        o = Obj(cls, fmt, slots, data)
        o.hash = self.next_hash()
        self.objects.append(o)
        return o

    # -- reading sources
    def read_packages(self):
        path = os.path.join(self.src_dir, 'packages.txt')
        for ln, line in enumerate(open(path, encoding='utf-8'), 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if parts[0] == 'export' and len(parts) >= 4 and re.fullmatch(r'\d+', parts[2]):
                for g in parts[3:]:
                    self.exports[(parts[1], g)] = int(parts[2])
                continue
            if len(parts) < 2 or not re.fullmatch(r'-?\d+', parts[1]) or (len(parts) > 2 and (
                    parts[2] != 'uses' or len(parts) == 3)):
                raise CompileError('expected "Name layer [uses Package...]" or "export Package layer Global..."',
                                   path, ln)
            self.packages.append((parts[0], int(parts[1])))
            self.layers[parts[0]] = int(parts[1])
            self.uses[parts[0]] = set(parts[3:])
        for other in set().union(*self.uses.values(), (p for p, _ in self.exports)):
            if other not in self.layers:
                raise CompileError(f'unknown package {other}', path, 0)
        for pkg, _ in self.packages:
            d = os.path.join(self.src_dir, pkg)
            if not os.path.isdir(d):
                raise CompileError(f'package directory {pkg} missing', path, 0)
            files = sorted(f for f in os.listdir(d) if f.endswith('.st'))
            files.sort(key=lambda f: f.endswith('.extension.st'))
            for f in files:
                self.read_file(os.path.join(d, f), pkg)

    def read_file(self, path, pkg):
        text = open(path, encoding='utf-8').read()
        rel = path if not os.path.isabs(path) else os.path.relpath(path, os.getcwd())
        if rel.startswith('../..'):
            rel = path
        chunks, buf, i, n, line, start = [], [], 0, len(text), 1, 1
        while i < n:
            c = text[i]
            if c == '!':
                if i + 1 < n and text[i + 1] == '!':
                    buf.append('!')
                    i += 2
                    continue
                chunks.append((''.join(buf), start))
                buf = []
                i += 1
                start = line
                continue
            if c == '\n':
                line += 1
            buf.append(c)
            i += 1
        if ''.join(buf).strip():
            chunks.append((''.join(buf), start))
        mode = None
        for raw, ln in chunks:
            stripped = raw.lstrip()
            ln += raw[:len(raw) - len(stripped)].count('\n')
            body = stripped.rstrip()
            if body.endswith('$') and len(stripped) > len(body):
                body = stripped[:len(body) + 1]  # keep the character of a trailing `$ ` literal
            if mode is not None:
                if not body:
                    mode = None
                    continue
                self.method_chunks.append((mode[0], mode[1], mode[2], body, rel, ln, pkg))
                continue
            if not body:
                continue
            m = re.fullmatch(r"(\w+)(\s+class)?\s+methodsFor:\s*'((?:[^']|'')*)'(?:\s+stamp:\s*'[^']*')?", body)
            if m:
                mode = (m.group(1), bool(m.group(2)), m.group(3).replace("''", "'"))
                continue
            self.top_level(body, rel, ln, pkg)

    def top_level(self, body, file, line, pkg):
        p = Parser(body, file, line)
        e = p.parse_expression()
        while p.tok.kind == '.':
            p.next()
        if p.tok.kind != 'eof':
            p.error('end of definition expected')
        if not isinstance(e, Send):
            raise CompileError('definition expected', file, line)
        parts = re.findall(r'\w+:', e.sel)
        rcv = e.rcv
        if parts and parts[0] in DEF_KINDS and isinstance(rcv, (Var, Lit)):
            sup = None if isinstance(rcv, Lit) and rcv.value is NIL else getattr(rcv, 'name', None)
            if isinstance(rcv, Lit) and rcv.value is not NIL:
                raise CompileError('bad superclass', file, line)
            kw = dict(zip(parts, e.args))

            def lit(k, default=''):
                a = kw.get(k)
                if a is None:
                    return default
                if not isinstance(a, Lit) or not isinstance(a.value, str):
                    raise CompileError(f'{k} expects a literal', file, line)
                return a.value

            name = lit(parts[0])
            if name in self.classes:
                raise CompileError(f'class {name} defined twice', file, line)
            cd = ClassDef(name, sup, DEF_KINDS[parts[0]], lit('instanceVariableNames:').split(),
                          lit('classVariableNames:').split(), lit('package:', lit('category:', pkg)), file, line)
            cd.src_pkg = pkg
            self.classes[name] = cd
            self.order.append(cd)
            self.layer_check(sup, pkg, file, line)
            return
        if e.sel == 'comment:' and isinstance(rcv, Var):
            cd = self.class_named(rcv.name, file, line)
            if not (isinstance(e.args[0], Lit) and isinstance(e.args[0].value, str)):
                raise CompileError('comment: expects a string', file, line)
            cd.comment = e.args[0].value
            return
        if e.sel == 'instanceVariableNames:' and isinstance(rcv, Send) and rcv.sel == 'class' and isinstance(
                rcv.rcv, Var):
            cd = self.class_named(rcv.rcv.name, file, line)
            cd.class_ivars = e.args[0].value.split()
            return
        if e.sel == 'at:put:' and isinstance(rcv, Var) and rcv.name == 'Smalltalk' and isinstance(e.args[0], Lit):
            if not isinstance(e.args[1], Lit):
                raise CompileError('Smalltalk at:put: expects a literal value', file, line)
            self.global_decls.append((str(e.args[0].value), e.args[1].value, file, line, pkg))
            return
        raise CompileError('unsupported top-level chunk', file, line)

    def class_named(self, name, file, line):
        cd = self.classes.get(name)
        if cd is None:
            raise CompileError(f'unknown class {name}', file, line)
        return cd

    # -- class graph
    def sort_classes(self):
        done, out = set(), []

        def visit(cd, stack):
            if cd.name in done:
                return
            if cd.name in stack:
                raise CompileError(f'superclass cycle at {cd.name}', cd.file, cd.line)
            if cd.sup is not None:
                sup = self.classes.get(cd.sup)
                if sup is None:
                    raise CompileError(f'unknown superclass {cd.sup}', cd.file, cd.line)
                visit(sup, stack | {cd.name})
            done.add(cd.name)
            out.append(cd)

        for cd in self.order:
            visit(cd, set())
        self.order = out
        for n in REQUIRED_CLASSES:
            if n not in self.classes:
                raise CompileError(f'required class {n} is not defined', 'src', 0)

    def compute_layouts(self):
        for cd in self.order:
            sup = self.classes[cd.sup] if cd.sup else None
            cd.all_ivars = (sup.all_ivars if sup else []) + cd.ivars
            isize = len(cd.all_ivars)
            kind = cd.kind
            if kind == 'fixed' and sup is not None and sup.inst_spec not in (F_EMPTY, F_FIXED):
                kind = {F_VAR: 'pointers', F_FIXVAR: 'pointers', F_WEAK: 'weak', F_IMMEDIATE: 'immediate',
                        F_W64: 'doublewords', F_W32: 'words', F_BYTES: 'bytes'}[sup.inst_spec]
            if cd.name == 'BoxedFloat64':
                kind = 'doublewords'
            spec = {'fixed': F_FIXED if isize else F_EMPTY, 'pointers': F_FIXVAR if isize else F_VAR, 'weak': F_WEAK,
                    'immediate': F_IMMEDIATE, 'doublewords': F_W64, 'words': F_W32, 'bytes': F_BYTES}[kind]
            if spec in (F_IMMEDIATE, F_W64, F_W32, F_BYTES) and isize:
                raise CompileError(f'{cd.name}: non-pointer classes cannot have instance variables', cd.file, cd.line)
            cd.inst_spec = spec
            cd.format = (spec << VMC['CLS_SPEC_SHIFT']) | isize
        class_ivars = self.classes['Class'].all_ivars
        for cd in self.order:
            sup = self.classes[cd.sup] if cd.sup else None
            cd.meta_ivars = (sup.meta_ivars if sup else class_ivars) + cd.class_ivars
        for name, layout in VM_LAYOUTS.items():
            cd = self.classes.get(name)
            if cd is None:
                continue
            want = layout.split()
            if cd.all_ivars[:len(want)] != want:
                raise CompileError(f'{name} must start with instance variables: {layout} (has {" ".join(cd.all_ivars)})',
                                   cd.file, cd.line)
        if self.classes['Context'].inst_spec != F_FIXVAR:
            raise CompileError('Context must be a variableSubclass:', self.classes['Context'].file, 0)

    def instance_of(self, cd, values=None, extra=0):
        """A pointer instance of class cd with ivars set by name."""
        n, spec = len(cd.all_ivars), cd.inst_spec
        o = self.new(cd.obj, spec if spec in (F_VAR, F_FIXVAR, F_WEAK) else (F_FIXED if n else F_EMPTY),
                     [self.nil] * (n + extra))
        for k, v in (values or {}).items():
            if k in cd.all_ivars:
                o.slots[cd.all_ivars.index(k)] = v
            elif v is not self.nil:
                raise CompileError(f'{cd.name} lacks instance variable {k}', cd.file, cd.line)
        return o

    def build_classes(self):
        C = self.classes
        for cd in self.order:
            cd.meta = Obj(None, F_FIXED)
            cd.obj = Obj(None, F_FIXED)
            for o in (cd.meta, cd.obj):
                o.hash = self.next_hash()
                self.objects.append(o)
        self.nil = self.new(C['UndefinedObject'].obj, F_EMPTY, [])
        self.true = self.new(C['True'].obj, F_EMPTY, [])
        self.false = self.new(C['False'].obj, F_EMPTY, [])
        meta_cls = C['Metaclass']
        for cd in self.order:
            cd.meta.cls = meta_cls.obj
            cd.meta.slots = [self.nil] * len(meta_cls.all_ivars)
            cd.obj.cls = cd.meta
            cd.obj.slots = [self.nil] * len(cd.meta_ivars)
            cd.meta.fmt = F_FIXED if cd.meta.slots else F_EMPTY
            cd.obj.fmt = F_FIXED if cd.obj.slots else F_EMPTY
        for cd in self.order:
            for v in cd.cvars:
                cd.pool[v] = self.association(self.intern(v), self.nil)

    def intern(self, s):
        o = self.symbols.get(s)
        if o is None:
            if all(ord(ch) < 256 for ch in s):
                o = self.new(self.classes['ByteSymbol'].obj, F_BYTES, None, s.encode('latin-1'))
            else:
                o = self.new(self.classes['WideSymbol'].obj, F_W32, None, [ord(ch) for ch in s])
            o.immutable = True
            o.tag = s
            self.symbols[s] = o
        return o

    def string(self, s, immutable=False):
        if all(ord(ch) < 256 for ch in s):
            o = self.new(self.classes['ByteString'].obj, F_BYTES, None, s.encode('latin-1'))
        else:
            o = self.new(self.classes['WideString'].obj, F_W32, None, [ord(ch) for ch in s])
        o.immutable = immutable
        return o

    def array(self, elems, immutable=False):
        o = self.new(self.classes['Array'].obj, F_VAR, list(elems))
        o.immutable = immutable
        return o

    def association(self, key, value):
        return self.instance_of(self.classes['Association'], {'key': key, 'value': value})

    def to_obj(self, v):
        """Literal value -> heap value (immutable)."""
        if v is NIL:
            return self.nil
        if v is TRUE:
            return self.true
        if v is FALSE:
            return self.false
        if isinstance(v, Sym):
            return self.intern(str(v))
        if isinstance(v, str):
            return self.string(v, True)
        if isinstance(v, Chr):
            return v
        if isinstance(v, bool):
            raise TypeError('bool')
        if isinstance(v, int):
            if INT_MIN <= v <= INT_MAX:
                return v
            mag = abs(v)
            o = self.new(self.classes['LargeNegativeInteger' if v < 0 else 'LargePositiveInteger'].obj, F_BYTES, None,
                         mag.to_bytes((mag.bit_length() + 7) // 8, 'little'))
            o.immutable = True
            return o
        if isinstance(v, float):
            if smallfloat_bits(v) is not None:
                return v
            o = self.new(self.classes['BoxedFloat64'].obj, F_W64, None, [struct.unpack('<Q', struct.pack('<d', v))[0]])
            o.immutable = True
            return o
        if isinstance(v, tuple):
            return self.array([self.to_obj(e) for e in v], True)
        if isinstance(v, bytes):
            o = self.new(self.classes['ByteArray'].obj, F_BYTES, None, v)
            o.immutable = True
            return o
        raise TypeError(repr(v))

    # -- variable resolution (used by the compiler)
    def inst_var_index(self, cd, meta, name):
        ivars = cd.meta_ivars if meta else cd.all_ivars
        if name in ivars:
            return len(ivars) - 1 - ivars[::-1].index(name)
        return None

    def resolve_binding(self, cd, name):
        c = cd
        while c is not None:
            if name in c.pool:
                return c.pool[name]
            c = self.classes[c.sup] if c.sup else None
        return self.globals.get(name)

    def global_package(self, name):
        cd = self.classes.get(name)
        if cd is not None:
            return cd.src_pkg
        return next((pkg for n, _, _, _, pkg in self.global_decls if n == name), None)

    def layer_check(self, name, pkg, file, line):
        """Record a reference from package pkg to the global name unless packages.txt's layering allows it: own layer,
        the layer directly below, layer 0, exported globals (export lines) and listed packages (uses)."""
        owner = self.global_package(name) if name else None
        if owner is None or owner == pkg or owner in self.uses.get(pkg, ()):
            return
        mine, theirs = self.layers[pkg], self.layers[owner]
        if theirs in (0, mine, mine - 1) or mine >= self.exports.get((owner, name), mine + 1):
            return
        self.layer_errors.append(f'{file}:{line}: {pkg} (layer {mine}) uses {name} of {owner} (layer {theirs})')

    def undeclared(self, name, file, line):
        a = self.undeclared_map.get(name)
        if a is None:
            self.warn(f'{file}:{line}: undeclared variable {name} (bound in Undeclared)')
            a = self.association(self.intern(name), self.nil)
            self.undeclared_map[name] = a
        return a

    def define_globals(self):
        for cd in self.order:
            self.globals[cd.name] = self.association(self.intern(cd.name), cd.obj)
        for n in ('Smalltalk', 'Processor', 'Undeclared'):
            self.globals.setdefault(n, self.association(self.intern(n), self.nil))
        for name, value, file, line, _ in self.global_decls:
            if name in self.globals and name in self.classes:
                raise CompileError(f'{name} is a class', file, line)
            self.globals[name] = self.association(self.intern(name), self.to_obj(value))

    # -- methods
    def compile_methods(self):
        errors = []
        for cname, meta, cat, body, file, line, pkg in self.method_chunks:
            try:
                cd = self.class_named(cname, file, line)
                m = self.compile_method(cd, meta, cat, body, file, line, pkg)
                table = cd.class_methods if meta else cd.methods
                if m[0] in table and table[m[0]][2] == pkg:
                    self.warn(f'{file}:{line}: {cname}{" class" if meta else ""}>>{m[0]} redefined')
                table[m[0]] = (m[1], file, pkg)
            except CompileError as e:
                errors.append(e)
                if len(errors) >= 50:
                    break
        if errors:
            for e in errors:
                print(f'bootstrap: error: {e}', file=sys.stderr)
            raise SystemExit(1)
        if self.layer_errors:
            for e in self.layer_errors:
                print(f'bootstrap: error: {e}', file=sys.stderr)
            print(f'bootstrap: {len(self.layer_errors)} layering violation(s); the rule and its exceptions (export, uses) '
                  f'are in {os.path.join(self.src_dir, "packages.txt")}', file=sys.stderr)
            raise SystemExit(1)

    def compile_method(self, cd, meta, cat, src, file, line, pkg):
        p = Parser(src, file, line)
        mnode = p.parse_method()
        prim, error_temp, pragmas = 0, None, []
        for sel, args, pos in mnode.pragmas:
            if sel in ('primitive:', 'primitive:error:', 'primitive:module:', 'primitive:module:error:'):
                if 'module:' in sel:
                    p.error('primitive modules are not supported', pos)
                a = args[0]
                if isinstance(a, str) and not isinstance(a, Sym):
                    if a not in self.prims:
                        p.error(f'unknown primitive {a!r}', pos)
                    prim = self.prims[a]
                elif type(a) is int:
                    prim = a
                else:
                    p.error('primitive name or number expected', pos)
                if sel.endswith('error:'):
                    if not isinstance(args[1], Var):
                        p.error('error code variable expected', pos)
                    error_temp = args[1].name
            else:
                if any(isinstance(a, Var) for a in args):
                    p.error('pragma arguments must be literals', pos)
                pragmas.append((sel, args))
        c = MethodCompiler(self, cd, meta, file, line, src, pkg)
        shape = c.compile(mnode, prim, error_temp)
        if shape['frameSize'] > 255 or shape['numTemps'] > 255:
            raise CompileError('method frame too large', file, line)
        lits = []
        for kind, v in c.lits:
            lits.append(self.to_obj(v) if kind == 'const' else v)
        cm_cd = self.classes['CompiledMethod']
        bytecodes = self.new(self.classes['ByteArray'].obj, F_BYTES, None, bytes(c.code))
        prag = self.nil
        if pragmas:
            msg = self.classes['Message']
            prag = self.array([self.instance_of(msg, {'selector': self.intern(s), 'arguments': self.array(
                [self.to_obj(a) for a in args], True)}) for s, args in pragmas])
        method = self.instance_of(cm_cd, {
            'selector': self.intern(mnode.sel), 'methodClass': cd.meta if meta else cd.obj,
            'literals': self.array(lits), 'bytecodes': bytecodes, 'numArgs': shape['numArgs'],
            'numTemps': shape['numTemps'], 'frameSize': shape['frameSize'],
            'primitive': prim | (VMC['CM_PRIM_ERROR_FLAG'] if error_temp else 0), 'source': self.string(src),
            'category': self.string(cat), 'pragmas': prag})
        return mnode.sel, method

    # -- hashed collections
    def hashed(self, cd, items, hash_fn):
        cap = 4
        while cap < 2 * len(items):
            cap *= 2
        arr = [self.nil] * cap
        for it in items:
            i = hash_fn(it) % cap
            while arr[i] is not self.nil:
                i = (i + 1) % cap
            arr[i] = it
        return self.instance_of(cd, {'tally': len(items), 'array': self.array(arr)})

    def dictionary(self, cd, assocs):
        return self.hashed(cd, assocs, lambda a: fnv_hash(a.slots[0].tag))

    def method_dict(self, methods):
        cap = 4
        while cap < 2 * len(methods):
            cap *= 2
        keys, vals = [self.nil] * cap, [self.nil] * cap
        for sel, (m, _, _) in methods.items():
            s = self.intern(sel)
            i = s.hash & (cap - 1)
            while keys[i] is not self.nil:
                i = (i + 1) & (cap - 1)
            keys[i], vals[i] = s, m
        return self.instance_of(self.classes['MethodDictionary'],
                                {'tally': len(methods), 'keys': self.array(keys), 'values': self.array(vals)})

    def fill_classes(self):
        C = self.classes
        meta_cd, class_cd, dict_cd = C['Metaclass'], C['Class'], C['Dictionary']
        subclasses = {cd.name: [] for cd in self.order}
        for cd in self.order:
            if cd.sup:
                subclasses[cd.sup].append(cd)

        def setf(o, layout, name, v):
            if name in layout:
                o.slots[layout.index(name)] = v

        for cd in self.order:
            sup = C[cd.sup] if cd.sup else None
            lay = cd.meta_ivars
            o = cd.obj
            setf(o, lay, 'superclass', sup.obj if sup else self.nil)
            setf(o, lay, 'methodDict', self.method_dict(cd.methods))
            setf(o, lay, 'format', cd.format)
            setf(o, lay, 'instanceVariables', self.array([self.string(v) for v in cd.ivars]))
            setf(o, lay, 'subclasses', self.array([s.obj for s in subclasses[cd.name]]))
            setf(o, lay, 'name', self.intern(cd.name))
            setf(o, lay, 'classPool', self.dictionary(dict_cd, list(cd.pool.values())) if cd.pool else self.nil)
            setf(o, lay, 'package', self.string(cd.package))
            setf(o, lay, 'comment', self.string(cd.comment) if cd.comment is not None else self.nil)
            m, mlay = cd.meta, meta_cd.all_ivars
            setf(m, mlay, 'superclass', sup.meta if sup else class_cd.obj)
            setf(m, mlay, 'methodDict', self.method_dict(cd.class_methods))
            nmeta = len(cd.meta_ivars)
            setf(m, mlay, 'format', ((F_FIXED if nmeta else F_EMPTY) << VMC['CLS_SPEC_SHIFT']) | nmeta)
            setf(m, mlay, 'instanceVariables', self.array([self.string(v) for v in cd.class_ivars]))
            setf(m, mlay, 'thisClass', o)

    def build(self):
        self.read_packages()
        self.sort_classes()
        self.compute_layouts()
        self.build_classes()
        self.define_globals()
        self.compile_methods()
        C = self.classes
        sysdict_cd = C['SystemDictionary']
        smalltalk = self.instance_of(sysdict_cd)
        self.globals['Smalltalk'].slots[1] = smalltalk
        if 'PackageList' in sysdict_cd.pool:
            sysdict_cd.pool['PackageList'].slots[1] = self.array(
                [self.array([self.string(n), layer]) for n, layer in self.packages])
        # Processor and the startup process
        ll = C['LinkedList']
        lists = self.array([self.instance_of(ll) for _ in range(80)])
        sched = self.instance_of(C['ProcessorScheduler'], {'quiescentProcessLists': lists})
        self.globals['Processor'].slots[1] = sched
        start = self.lookup(sysdict_cd, 'bootstrapStartUp')
        if start is None:
            raise CompileError('SystemDictionary>>bootstrapStartUp is not defined', 'src', 0)
        ms = dict(zip(C['CompiledMethod'].all_ivars, start.slots))
        if ms['numArgs'] != 0:
            raise CompileError('bootstrapStartUp must be unary', 'src', 0)
        ctx = self.instance_of(C['Context'], {'pc': 0, 'stackp': ms['numTemps'], 'method': start,
                                              'receiver': smalltalk}, extra=ms['frameSize'] + CTX_SLACK)
        proc = self.instance_of(C['Process'], {'suspendedContext': ctx, 'priority': 40,
                                               'name': self.string('bootstrap'), 'cpuTime': 0})
        sched.slots[C['ProcessorScheduler'].all_ivars.index('activeProcess')] = proc
        self.globals['Undeclared'].slots[1] = self.dictionary(C['Dictionary'], list(self.undeclared_map.values()))
        primfailed = self.intern('primitiveFailed')
        specials_syms = [self.intern(s) for s in ('doesNotUnderstand:', 'mustBeBoolean', 'cannotReturn:',
                                                  'aboutToReturn:through:', 'attemptToAssign:withIndex:',
                                                  'stackOverflow:')]
        special_selectors = self.array([self.intern(s) for s in SPECIAL_SELECTORS])
        self.fill_classes()
        if sysdict_cd.all_ivars[:2] != ['tally', 'array']:
            raise CompileError('SystemDictionary must start with instance variables: tally array', sysdict_cd.file, 0)
        sd = self.dictionary(sysdict_cd, list(self.globals.values()))
        smalltalk.slots[:2] = sd.slots[:2]
        self.objects.remove(sd)
        g = lambda n: C[n].obj if n in C else self.nil
        so = {'SO_NIL': self.nil, 'SO_FALSE': self.false, 'SO_TRUE': self.true, 'SO_PROCESSOR': sched,
              'SO_SMALLTALK': smalltalk, 'SO_SMALLINTEGER': g('SmallInteger'), 'SO_CHARACTER': g('Character'),
              'SO_SMALLFLOAT': g('SmallFloat64'), 'SO_BOXEDFLOAT': g('BoxedFloat64'), 'SO_ARRAY': g('Array'),
              'SO_BYTEARRAY': g('ByteArray'), 'SO_BYTESTRING': g('ByteString'), 'SO_BYTESYMBOL': g('ByteSymbol'),
              'SO_WIDESTRING': g('WideString'), 'SO_COMPILEDMETHOD': g('CompiledMethod'), 'SO_CONTEXT': g('Context'),
              'SO_BLOCKCLOSURE': g('BlockClosure'), 'SO_PROCESS': g('Process'), 'SO_SEMAPHORE': g('Semaphore'),
              'SO_POINT': g('Point'), 'SO_LARGEPOS': g('LargePositiveInteger'),
              'SO_LARGENEG': g('LargeNegativeInteger'), 'SO_MESSAGE': g('Message'),
              'SO_ASSOCIATION': g('Association'), 'SO_BITMAP': g('Bitmap'), 'SO_SEL_DNU': specials_syms[0],
              'SO_SEL_MUSTBEBOOLEAN': specials_syms[1], 'SO_SEL_CANNOTRETURN': specials_syms[2],
              'SO_SEL_ABOUTTORETURN': specials_syms[3], 'SO_SEL_ATTEMPTTOASSIGN': specials_syms[4],
              'SO_SPECIAL_SELECTORS': special_selectors, 'SO_TIMER_SEMAPHORE': self.nil,
              'SO_EXTERNAL_OBJECTS': self.array([self.nil] * VMC['EXTERNAL_OBJECTS_SIZE']),
              'SO_WIDESYMBOL': g('WideSymbol'), 'SO_SEL_PRIMITIVEFAILED': primfailed,
              'SO_FINALIZATION_SEMAPHORE': self.nil, 'SO_SEL_STACKOVERFLOW': specials_syms[5]}
        specials = [self.nil] * VMC['SO_COUNT']
        for name, v in so.items():
            specials[VMC[name]] = v
        if len(so) != VMC['SO_COUNT']:
            raise CompileError('special objects in vm/src/vm.h and boot/bootstrap.py differ', 'vm/src/vm.h', 0)
        self.specials = self.array(specials)
        holder = next((cd for cd in self.order if 'SymbolTable' in cd.pool), None)
        if holder is not None:
            set_cd = C.get('Set') or C['Dictionary']
            if set_cd.all_ivars[:2] != ['tally', 'array']:
                raise CompileError(f'{set_cd.name} must start with instance variables: tally array', set_cd.file, 0)
            syms = list(self.symbols.values())
            holder.pool['SymbolTable'].slots[1] = self.hashed(set_cd, syms, lambda s: fnv_hash(s.tag))

    def lookup(self, cd, sel):
        while cd is not None:
            if sel in cd.methods:
                return cd.methods[sel][0]
            cd = self.classes[cd.sup] if cd.sup else None
        return None

    # -- writing
    def oop(self, v):
        if isinstance(v, Obj):
            return v.addr
        if isinstance(v, Chr):
            return (v.cp << 3) | 2
        if isinstance(v, bool):
            raise TypeError('bool in heap')
        if isinstance(v, int):
            return ((v << 1) | 1) & MASK64
        if isinstance(v, float):
            return smallfloat_bits(v)
        raise TypeError(repr(v))

    def write(self, path):
        addr = BASE
        for o in self.objects:
            o.addr = addr
            addr += 16 + 8 * o.nslots()
        out = bytearray()
        for o in self.objects:
            n = o.nslots()
            f = o.fmt
            if f == F_BYTES:
                f = F_BYTES + (8 - len(o.data) % 8) % 8
            elif f == F_W32:
                f = F_W32 + len(o.data) % 2
            hdr = n | (f << VMC['H_FMT_SHIFT']) | (o.hash << VMC['H_HASH_SHIFT']) | (VMC['H_IMMUTABLE'] if o.immutable else 0)
            out += struct.pack('<QQ', hdr, o.cls.addr)
            if o.fmt <= F_WEAK:
                out += struct.pack(f'<{n}Q', *[self.oop(v) for v in o.slots])
            elif o.fmt == F_W64:
                out += struct.pack(f'<{n}Q', *o.data)
            elif o.fmt == F_W32:
                out += struct.pack(f'<{len(o.data)}I', *o.data) + b'\0' * (4 * (len(o.data) % 2))
            else:
                out += o.data + b'\0' * ((8 - len(o.data) % 8) % 8)
        assert len(out) == addr - BASE
        hdr = b'SAMALTK1' + struct.pack('<QQQQQQQ', 1, 64, len(out), BASE, self.specials.addr, self.seed, 0)
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(hdr + out)
        return len(out)


def load_primitives():
    prims = {}
    for rel in ('vm/src/prims.def', 'vm/platform/prims_platform.def'):
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            continue
        for m in re.finditer(r'^\s*PRIM\(\s*(\w+)\s*,\s*"([^"]+)"\s*,', open(p).read(), re.M):
            n = m.group(1)
            prims[m.group(2)] = int(n) if n.isdigit() else VMC[n]
    return prims


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 64
    img = Image(argv[1])
    try:
        img.build()
    except CompileError as e:
        print(f'bootstrap: error: {e}', file=sys.stderr)
        return 1
    n = img.write(argv[2])
    nm = sum(len(cd.methods) + len(cd.class_methods) for cd in img.order)
    print(f'bootstrap: {len(img.order)} classes, {nm} methods, {len(img.objects)} objects, {n} bytes -> {argv[2]}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
