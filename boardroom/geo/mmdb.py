"""Minimal read-only MaxMind DB (.mmdb) reader, standard library only.

Enough of the format (https://maxmind.github.io/MaxMind-DB/) to look up an IP
in DB-IP's City Lite database: the binary search tree with 24/28/32-bit
records and the data-section decoder. The file is mmap'd, so a lookup pages in
only the few tree nodes and records it touches rather than the whole file.
"""
import ipaddress
import mmap
import struct

_METADATA_MARKER = b"\xab\xcd\xefMaxMind.com"


class Reader:
    def __init__(self, path):
        with open(path, "rb") as fh:
            self._buf = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        marker = self._buf.rfind(_METADATA_MARKER)
        if marker < 0:
            raise ValueError("not a MaxMind DB: " + path)
        self.metadata, _ = _Decoder(self._buf, marker + len(_METADATA_MARKER)).decode(
            marker + len(_METADATA_MARKER))

        self._node_count = self.metadata["node_count"]
        self._record_size = self.metadata["record_size"]
        self._ip_version = self.metadata["ip_version"]
        self._node_bytes = self._record_size * 2 // 8
        self._tree_size = self._node_count * self._node_bytes
        # Pointers in the data section are relative to its start, which sits
        # after the tree and a 16-byte zero separator.
        self._decoder = _Decoder(self._buf, self._tree_size + 16)
        self._ipv4_start = None

    def close(self):
        self._buf.close()

    def get(self, ip):
        addr = ipaddress.ip_address(ip)
        if addr.version == 6 and self._ip_version == 4:
            return None
        bits = addr.max_prefixlen
        packed = int(addr)

        node = 0
        if addr.version == 4 and self._ip_version == 6:
            node = self._ipv4_start_node()

        for i in range(bits):
            if node >= self._node_count:
                break
            bit = (packed >> (bits - 1 - i)) & 1
            node = self._read_record(node, bit)

        if node == self._node_count:
            return None
        if node > self._node_count:
            offset = self._tree_size + (node - self._node_count)
            value, _ = self._decoder.decode(offset)
            return value
        raise ValueError("corrupt MaxMind DB search tree")

    def _ipv4_start_node(self):
        # IPv4 lives under ::/96 in an IPv6 tree: follow 96 zero bits once.
        if self._ipv4_start is None:
            node = 0
            for _ in range(96):
                if node >= self._node_count:
                    break
                node = self._read_record(node, 0)
            self._ipv4_start = node
        return self._ipv4_start

    def _read_record(self, node, index):
        base = node * self._node_bytes
        b = self._buf
        if self._record_size == 24:
            off = base + index * 3
            return int.from_bytes(b[off:off + 3], "big")
        if self._record_size == 28:
            if index == 0:
                return ((b[base + 3] & 0xF0) << 20) | int.from_bytes(b[base:base + 3], "big")
            return ((b[base + 3] & 0x0F) << 24) | int.from_bytes(b[base + 4:base + 7], "big")
        if self._record_size == 32:
            off = base + index * 4
            return int.from_bytes(b[off:off + 4], "big")
        raise ValueError("unsupported record size %d" % self._record_size)


class _Decoder:
    def __init__(self, buf, pointer_base):
        self._buf = buf
        self._pointer_base = pointer_base

    def decode(self, offset):
        ctrl = self._buf[offset]
        offset += 1
        kind = ctrl >> 5

        if kind == 1:  # pointer: follow it, but return the offset after the pointer
            size_bits = (ctrl >> 3) & 0x3
            v = ctrl & 0x7
            b = self._buf
            if size_bits == 0:
                ptr = (v << 8) | b[offset]
                offset += 1
            elif size_bits == 1:
                ptr = ((v << 16) | int.from_bytes(b[offset:offset + 2], "big")) + 2048
                offset += 2
            elif size_bits == 2:
                ptr = ((v << 24) | int.from_bytes(b[offset:offset + 3], "big")) + 526336
                offset += 3
            else:
                ptr = int.from_bytes(b[offset:offset + 4], "big")
                offset += 4
            value, _ = self.decode(self._pointer_base + ptr)
            return value, offset

        if kind == 0:  # extended type in the next byte
            kind = 7 + self._buf[offset]
            offset += 1

        size = ctrl & 0x1F
        if size >= 29:
            extra = size - 28
            raw = int.from_bytes(self._buf[offset:offset + extra], "big")
            offset += extra
            size = (29, 285, 65821)[extra - 1] + raw

        b = self._buf
        if kind == 2:  # utf-8 string
            return b[offset:offset + size].decode("utf-8"), offset + size
        if kind == 3:  # double
            return struct.unpack(">d", b[offset:offset + 8])[0], offset + 8
        if kind == 4:  # bytes
            return bytes(b[offset:offset + size]), offset + size
        if kind in (5, 6, 9, 10):  # unsigned ints
            return int.from_bytes(b[offset:offset + size], "big"), offset + size
        if kind == 7:  # map
            out = {}
            for _ in range(size):
                key, offset = self.decode(offset)
                out[key], offset = self.decode(offset)
            return out, offset
        if kind == 8:  # int32
            raw = int.from_bytes(b[offset:offset + size], "big")
            if size == 4 and raw & 0x80000000:
                raw -= 1 << 32
            return raw, offset + size
        if kind == 11:  # array
            out = []
            for _ in range(size):
                item, offset = self.decode(offset)
                out.append(item)
            return out, offset
        if kind == 14:  # boolean: value is the size field
            return bool(size), offset
        if kind == 15:  # float
            return struct.unpack(">f", b[offset:offset + 4])[0], offset + 4
        raise ValueError("unsupported MaxMind data type %d" % kind)
