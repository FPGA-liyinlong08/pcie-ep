"""K09独立PCIe BAR/Completion参考算法。

该文件只依赖冻结接口，不读取RTL状态。Completion Byte Count按AMD PG156/PG213的
地址跨度规则计算；不能替换成BE popcount。
"""

from dataclasses import dataclass
from typing import List


def first_offset(be: int) -> int:
    be &= 0xF
    if be == 0:
        return 0
    for index in range(4):
        if be & (1 << index):
            return index
    raise AssertionError("unreachable")


def trailing_disabled(be: int) -> int:
    be &= 0xF
    if be == 0:
        return 0
    for index in range(3, -1, -1):
        if be & (1 << index):
            return 3 - index
    raise AssertionError("unreachable")


def request_byte_count(length_dw: int, first_be: int, last_be: int) -> int:
    assert 1 <= length_dw <= 1024
    first_be &= 0xF
    last_be &= 0xF
    if length_dw == 1 and first_be == 0:
        return 1
    if length_dw == 1:
        return 4 - first_offset(first_be) - trailing_disabled(first_be)
    return length_dw * 4 - first_offset(first_be) - trailing_disabled(last_be)


def plan_chunks(address: int, length_dw: int) -> List[int]:
    """按Endpoint 128B RCB、128B MPS和4KiB边界返回DWORD分段。"""
    assert address & 3 == 0
    assert 1 <= length_dw <= 1024
    result = []
    current = address
    remaining = length_dw
    while remaining:
        to_4k = 1024 - ((current & 0xFFF) >> 2)
        if remaining <= 32:
            chunk = min(remaining, to_4k)
        else:
            to_128 = 32 - ((current >> 2) & 0x1F)
            chunk = min(remaining, 32, to_128, to_4k)
        if chunk <= 0:
            raise ValueError("请求跨越4KiB边界")
        result.append(chunk)
        current += chunk * 4
        remaining -= chunk
    return result


def byte_mask_for_dw(index: int, length_dw: int, first_be: int,
                     last_be: int) -> int:
    if length_dw == 1:
        return first_be & 0xF
    if index == 0:
        return first_be & 0xF
    if index == length_dw - 1:
        return last_be & 0xF
    return 0xF


def apply_be(data: int, be: int) -> int:
    value = 0
    for lane in range(4):
        if be & (1 << lane):
            value |= data & (0xFF << (8 * lane))
    return value


@dataclass(frozen=True)
class ExpectedCompletion:
    status: int
    has_data: int
    byte_count: int
    lower_address: int
    length_dw: int
    requester_id: int
    completer_id: int
    tag: int
    tc: int
    attr: int
    payload: bytes


def make_sc_completions(memory: bytearray, bar_base: int, address: int,
                        length_dw: int, first_be: int, last_be: int,
                        requester_id: int, completer_id: int, tag: int,
                        tc: int, attr: int) -> List[ExpectedCompletion]:
    assert len(memory) == 4096
    offset = address - bar_base
    assert 0 <= offset and offset + length_dw * 4 <= 4096

    if length_dw == 1 and (first_be & 0xF) == 0:
        return [ExpectedCompletion(
            status=0, has_data=1, byte_count=1,
            lower_address=address & 0x7F, length_dw=1,
            requester_id=requester_id, completer_id=completer_id,
            tag=tag, tc=tc, attr=attr, payload=bytes(4))]

    words = []
    for index in range(length_dw):
        pos = offset + index * 4
        word = int.from_bytes(memory[pos:pos + 4], "little")
        word = apply_be(word, byte_mask_for_dw(
            index, length_dw, first_be, last_be))
        words.append(word)

    chunks = plan_chunks(address, length_dw)
    result = []
    remaining_bc = request_byte_count(length_dw, first_be, last_be)
    word_index = 0
    current_address = address
    first_off = first_offset(first_be)
    last_tail = trailing_disabled(first_be if length_dw == 1 else last_be)

    for chunk_index, chunk_dw in enumerate(chunks):
        is_first = chunk_index == 0
        is_last = chunk_index == len(chunks) - 1
        lower = ((current_address + first_off) & 0x7F) if is_first else 0
        payload = b"".join(
            words[word_index + k].to_bytes(4, "little")
            for k in range(chunk_dw))
        result.append(ExpectedCompletion(
            status=0, has_data=1, byte_count=remaining_bc,
            lower_address=lower, length_dw=chunk_dw,
            requester_id=requester_id, completer_id=completer_id,
            tag=tag, tc=tc, attr=attr, payload=payload))

        span = chunk_dw * 4
        if is_first:
            span -= first_off
        if is_last:
            span -= last_tail
        remaining_bc -= span
        word_index += chunk_dw
        current_address += chunk_dw * 4

    assert remaining_bc == 0
    return result


def make_error_completion(status: int, requester_id: int,
                          completer_id: int, tag: int,
                          tc: int, attr: int) -> ExpectedCompletion:
    assert status in (1, 4)
    return ExpectedCompletion(
        status=status, has_data=0, byte_count=0, lower_address=0,
        length_dw=0, requester_id=requester_id,
        completer_id=completer_id, tag=tag, tc=tc, attr=attr,
        payload=b"")
