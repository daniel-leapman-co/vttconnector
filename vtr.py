"""Read-only reader for VT Transaction+ (.vtr) ledger files.

The format is a self-describing paged store.  The header identifies it as
"VT Data Storage"; after that the file is a tree of 4096-byte pages.

Layout
------
* A *directory page* holds up to 16 node descriptors of 256 bytes each:
  a 128-byte space-padded name followed by 32 little-endian uint32 fields.
  The fields used here are:

      [1]  node type   1=folder 2=records 3=property table 4=index 5=stream
      [3]  page-table page
      [4]  first data page
      [6]  number of data pages
      [7]  record count (high-water mark, includes deleted records)
      [8]  record size in bytes
      [11] slot size, for streams

* A *page table* is a page of uint32 page offsets.  For `stream` nodes the
  live entries start 0x400 into that page; for `records` nodes they start at
  the beginning and page 0 is the node's own `first data page`.

* Records live in a flat virtual byte stream that is mapped onto those pages,
  so a record may straddle a page boundary.  Record numbers are 1-based and
  record n starts at virtual offset (n-1) * size.

Strings are held in two streams of 32-byte slots.  GlobalStrings holds the
string properties of every object except transactions and entries; TEAStrings
holds transaction/entry narratives.  A string too long for one slot is chained
through a next-slot pointer.

Amounts are signed 64-bit integers in ten-thousandths of a unit.
Dates are day counts from 1899-12-30 (the same epoch spreadsheets use).
"""

from __future__ import annotations

import datetime
import struct
from dataclasses import dataclass, field

PAGE = 4096
MAGIC = b"VT Data Storage"
EPOCH = datetime.date(1899, 12, 30)
SCALE = 10_000  # amounts are stored in 1/10000 units

ROOT_PAGE = 0x80


def _u32(buf: bytes, off: int) -> int:
    return struct.unpack_from("<I", buf, off)[0]


@dataclass
class Node:
    name: str
    fields: tuple

    @property
    def type(self) -> int:
        return self.fields[1]

    @property
    def table_page(self) -> int:
        return self.fields[3]

    @property
    def first_page(self) -> int:
        return self.fields[4]

    @property
    def page_count(self) -> int:
        return self.fields[6]

    @property
    def count(self) -> int:
        return self.fields[7]

    @property
    def rec_size(self) -> int:
        return self.fields[8] or self.fields[11]


@dataclass
class Account:
    number: int
    name: str
    ledger: int
    ledger_name: str


@dataclass
class Transaction:
    number: int
    type: int
    type_name: str
    date: datetime.date
    ref: str
    text: str
    entries: list = field(default_factory=list)


@dataclass
class Entry:
    number: int
    transaction: int
    date: datetime.date
    account: int
    account_name: str
    amount: int  # in 1/10000 units
    text: str

    @property
    def value(self) -> float:
        return self.amount / SCALE


class VtrFile:
    def __init__(self, path: str):
        with open(path, "rb") as fh:
            self.data = fh.read()
        if not self.data.startswith(MAGIC):
            raise ValueError(f"{path} is not a VT data storage file")
        self._load()

    # -- low level ---------------------------------------------------------

    def nodes(self, page: int) -> dict:
        out = {}
        for i in range(16):
            off = page + i * 0x100
            name = self.data[off:off + 0x80].decode("latin-1").rstrip(" \x00")
            if not name.strip("\x00"):
                continue
            out[name] = Node(name, struct.unpack_from("<32I", self.data, off + 0x80))
        return out

    def _pages(self, node: Node) -> list:
        skip = 0x400 if node.type == 5 else 0  # stream page tables start 1KB in
        base = node.table_page + skip
        pages = [node.first_page] if node.first_page else []
        if node.table_page:
            slots = (PAGE - skip) // 4
            pages += list(struct.unpack_from(f"<{slots}I", self.data, base))
        return [p for p in pages if p]

    def _record(self, pages: list, size: int, number: int):
        """Fetch 1-based record `number` from a paged virtual stream."""
        vo = (number - 1) * size
        out = bytearray()
        while len(out) < size:
            pi, po = divmod(vo, PAGE)
            if pi >= len(pages):
                return None
            take = min(PAGE - po, size - len(out))
            out += self.data[pages[pi] + po:pages[pi] + po + take]
            vo += take
        return bytes(out)

    def records(self, node: Node):
        """Yield (number, bytes) for every record slot in a records node."""
        pages = self._pages(node)
        size = node.rec_size
        capacity = len(pages) * PAGE // size
        for n in range(1, min(node.count, capacity) + 1):
            rec = self._record(pages, size, n)
            if rec is None:
                break
            yield n, rec

    def _string_reader(self, node: Node):
        """Strings live in 32-byte slots addressed by 1-based id.

        Slot header is [0:2] slot count and [2:6] a length or a next-slot id:

          count == 1       single slot, [2:6] is the byte length
          count == n > 1   head of an n-slot chain, [2:6] is the next slot id
          count == 0xFFFF  continuation slot; [2:6] is the next slot id, except
                           in the final slot where it is the total byte length
        """
        pages = self._pages(node)
        size = node.rec_size
        payload = size - 6

        def get(sid: int):
            if sid <= 0:
                return None
            rec = self._record(pages, size, sid)
            if rec is None:
                return None
            count = struct.unpack_from("<H", rec, 0)[0]
            if count == 0xFFFF or count == 0:
                return None
            if count == 1:
                return rec[6:6 + min(_u32(rec, 2), payload)].decode("latin-1")
            chunks = [rec[6:]]
            nxt = _u32(rec, 2)
            for _ in range(count - 1):
                slot = self._record(pages, size, nxt)
                if slot is None:
                    return None
                chunks.append(slot[6:])
                nxt = _u32(slot, 2)
            return b"".join(chunks)[:nxt].decode("latin-1")  # last hop is the length

        return get

    # -- object model ------------------------------------------------------

    def _load(self):
        entity = self.nodes(ROOT_PAGE)["Entity"]
        company_node = self.nodes(entity.first_page)["Company"]
        self.company = self.nodes(company_node.first_page)

        self.gstr = self._string_reader(self.company["GlobalStrings"])
        self.tstr = self._string_reader(self.company["TEAStrings"])

        self._ledgers = self._load_ledgers()
        self._user_names = self._load_user_names()
        self.accounts = self._load_accounts()
        self._trantypes = self._load_trantypes()
        self.transactions = self._load_transactions()
        self.entries = self._load_entries()
        for e in self.entries:
            t = self.transactions.get(e.transaction)
            if t is not None:
                t.entries.append(e)

    def _sub(self, group: str, child: str) -> Node:
        return self.nodes(self.company[group].first_page)[child]

    def _load_ledgers(self) -> dict:
        out = {}
        for n, rec in self.records(self._sub("Ledgers", "Records")):
            name = self.gstr(_u32(rec, 0))
            if name:
                out[n] = name
        return out

    def _load_user_names(self) -> dict:
        """Names of user-created accounts, keyed by their negative name id.

        Built-in chart-of-accounts names are GlobalStrings ids; accounts the
        user created carry a negative id instead.  Those names are held in the
        first phrase book chunk stream, one record per account, in id order:
        id -k is the k-th record.  Each record is three int32s followed by the
        name.  Inferred from this file rather than documented, so treat a
        missing entry as "unknown" rather than an error.
        """
        try:
            node = self.nodes(0x15000)["PhraseBookChunks1"]
        except KeyError:
            return {}
        pages = self._pages(node)
        size = node.rec_size
        out = {}
        for i in range(1, 256):
            rec = self._record(pages, size, i)
            if rec is None:
                break
            count = struct.unpack_from("<H", rec, 0)[0]
            if count != 1:
                continue
            body = rec[6:6 + min(_u32(rec, 2), size - 6)]
            if len(body) <= 12:
                continue
            out[-i] = body[12:].decode("latin-1")
        return out

    def _load_accounts(self) -> dict:
        out = {}
        for n, rec in self.records(self._sub("Accounts", "Records")):
            sid = struct.unpack_from("<i", rec, 0)[0]
            name = self.gstr(sid) if sid > 0 else self._user_names.get(sid)
            if not name:
                continue
            led = _u32(rec, 4)
            out[n] = Account(n, name, led, self._ledgers.get(led, ""))
        return out

    def _load_trantypes(self) -> dict:
        """Record holds the short code at offset 0 and the full name at 4."""
        out = {}
        for n, rec in self.records(self._sub("TranTypes", "Records")):
            out[n] = self.gstr(_u32(rec, 4)) or self.gstr(_u32(rec, 0)) or f"Type {n}"
        return out

    def _load_transactions(self) -> dict:
        out = {}
        for n, rec in self.records(self._sub("Transactions", "Records")):
            tt = _u32(rec, 0)
            if tt not in self._trantypes:
                continue
            serial = _u32(rec, 12)
            if not 20000 < serial < 80000:
                continue
            out[n] = Transaction(
                number=n,
                type=tt,
                type_name=self._trantypes.get(tt, ""),
                date=EPOCH + datetime.timedelta(days=serial),
                ref=str(_u32(rec, 8) // 1000),  # LongRefNumber is the ref x1000
                text="",  # transaction-level text field not yet located
            )
        return out

    def _load_entries(self) -> list:
        out = []
        for n, rec in self.records(self._sub("Entries", "Records")):
            tran = _u32(rec, 0)
            if tran not in self.transactions:
                continue
            serial = _u32(rec, 4)
            if not 20000 < serial < 80000:
                continue
            acct = _u32(rec, 8)
            out.append(Entry(
                number=n,
                transaction=tran,
                date=EPOCH + datetime.timedelta(days=serial),
                account=acct,
                account_name=self.accounts[acct].name if acct in self.accounts else "",
                amount=struct.unpack_from("<q", rec, 12)[0],
                text=self.tstr(_u32(rec, 20)) or "",
            ))
        return out

    # -- analysis ----------------------------------------------------------

    def trial_balance(self, at: datetime.date, exclude_year_end: bool = True) -> dict:
        """Net balance per account number, in 1/10000 units."""
        bal = {}
        for e in self.entries:
            if e.date > at:
                continue
            t = self.transactions[e.transaction]
            if exclude_year_end and t.type_name == "Year End" and t.date >= at:
                continue
            bal[e.account] = bal.get(e.account, 0) + e.amount
        return {k: v for k, v in bal.items() if v}
